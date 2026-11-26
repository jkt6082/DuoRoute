-- DuoRoute: core state, player tracking and learning
local ADDON, DR = ...
DuoRoute = DR

DR.VERSION = "1.0"
DR.D = DuoRoute_Data
DR.Q = DR.D.Q
DR.Z = DR.D.Z

-- quest record fields (see Data.lua)
DR.F = { NAME = 1, LVL = 2, REQ = 3, RACES = 4, CLASSES = 5, ZONE = 6, PREG = 7, PRES = 8, EXCL = 9,
  NEXT = 10, FLAGS = 11, XP = 12, SZ = 13, SX = 14, SY = 15, STARTER = 16, FZ = 17, FX = 18, FY = 19,
  MAX = 20, BC = 21, PARENT = 22, OBJ = 23, FINISHER = 24 }
DR.FLAG = { SKILL = 2, ITEM = 4, REPREQ = 8, ALLIANCE_ONLY = 16, HORDE_ONLY = 32, EVENT = 64, UNLOCATED = 128 }

local RACE_BIT = { [1] = 1, [2] = 2, [3] = 4, [4] = 8, [5] = 16, [6] = 32, [7] = 64, [8] = 128,
  [9] = 256, [10] = 512, [11] = 1024, [22] = 2097152, [95] = 4294967296, [96] = 8589934592 }
DR.RACE_BIT = RACE_BIT

function DR.Msg(...) print("|cff66ccffDuoRoute|r:", ...) end
function DR.Debug(...) if DuoRouteDB and DuoRouteDB.debug then DR.Msg("|cff888888", ...) end end

-- Works with masks above 32 bits (Forever's Skyborne races), unlike the bit library
function DR.HasBit(mask, bit)
  if not mask or not bit or bit <= 0 then return false end
  return math.floor(mask / bit) % 2 == 1
end

local function now() return time() end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local function InitSaved()
  DuoRouteDB = DuoRouteDB or {}
  DuoRouteDB.partners = DuoRouteDB.partners or {}
  DuoRouteDB.ui = DuoRouteDB.ui or {}
  DuoRouteChar = DuoRouteChar or {}
  local c = DuoRouteChar
  c.history = c.history or {}        -- { {q=, t=, xp=, est=, lvl=, map=} }
  c.zoneStats = c.zoneStats or {}    -- [uiMapID] = { xp=, secs= }
  c.ignored = c.ignored or {}        -- [questID] = true (player hid it)
  c.skipped = c.skipped or {}        -- [questID] = count of times abandoned
  c.calib = c.calib or { actual = 0, est = 0, n = 0 }
end

---------------------------------------------------------------------------
-- Map helpers: data UiMap IDs are checked against the client, with a name fallback
---------------------------------------------------------------------------
local mapByName
local function BuildMapNameIndex()
  mapByName = {}
  for id = 1, 3000 do
    local info = C_Map.GetMapInfo(id)
    if info and info.name and info.mapType == Enum.UIMapType.Zone then
      mapByName[info.name:lower()] = mapByName[info.name:lower()] or id
    end
  end
end

local mapCache = {}
function DR.UiMapForArea(areaID)
  if not areaID or areaID <= 0 then return nil end
  if mapCache[areaID] ~= nil then return mapCache[areaID] or nil end
  local z = DR.Z[areaID]
  local result = false
  if z then
    local u = z[2]
    local info = u and u > 0 and C_Map.GetMapInfo(u)
    if info then
      result = u
    elseif z[1] and z[1] ~= "" then
      if not mapByName then BuildMapNameIndex() end
      result = mapByName[z[1]:lower()] or false
    end
  end
  mapCache[areaID] = result
  return result or nil
end

function DR.ZoneName(areaID)
  local z = DR.Z[areaID]
  return (z and z[1] ~= "" and z[1]) or ("Zone " .. tostring(areaID))
end

function DR.IsDungeon(areaID)
  local z = DR.Z[areaID]
  return z and z[3] == 1
end

-- Which zone a quest is "worked" in
function DR.WorkZone(q)
  local F = DR.F
  local z = q[F.ZONE]
  if z and z > 0 and DR.Z[z] then return z end
  if q[F.SZ] and q[F.SZ] > 0 then return q[F.SZ] end
  return 0
end

---------------------------------------------------------------------------
-- Player context (same shape is used for the partner)
---------------------------------------------------------------------------
DR.me = { completed = {}, active = {}, activeDone = {} }

local function ReadCompleted(ctx)
  wipe(ctx.completed)
  local ok, ids = pcall(C_QuestLog.GetAllCompletedQuestIDs)
  if ok and type(ids) == "table" and #ids > 0 then
    for _, id in ipairs(ids) do ctx.completed[id] = true end
  else
    for id in pairs(DR.Q) do
      if C_QuestLog.IsQuestFlaggedCompleted(id) then ctx.completed[id] = true end
    end
  end
end

local function ReadQuestLog(ctx)
  wipe(ctx.active); wipe(ctx.activeDone)
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(i)
    if info and not info.isHeader and info.questID and info.questID > 0 then
      ctx.active[info.questID] = true
      if C_QuestLog.IsComplete(info.questID) then ctx.activeDone[info.questID] = true end
    end
  end
end

function DR.RefreshMe(full)
  local me = DR.me
  me.name = UnitName("player")
  me.level = UnitLevel("player")
  me.faction = (UnitFactionGroup("player") == "Alliance") and "A" or "H"
  local _, _, raceID = UnitRace("player")
  me.raceID = raceID
  me.raceBit = RACE_BIT[raceID] or 0
  local _, _, classID = UnitClass("player")
  me.classID = classID
  me.classBit = classID and 2 ^ (classID - 1) or 0
  me.xp, me.xpMax = UnitXP("player"), UnitXPMax("player")
  me.mapID = C_Map.GetBestMapForUnit("player")
  if me.mapID then
    local pos = C_Map.GetPlayerMapPosition(me.mapID, "player")
    if pos then me.x, me.y = pos:GetXY() end
  end
  if full then ReadCompleted(me) end
  ReadQuestLog(me)
  me.updated = now()
end

function DR.CompletedHash(set)
  local n, sum = 0, 0
  for id in pairs(set) do
    if DR.Q[id] then n = n + 1; sum = (sum + id * 7) % 1000003 end
  end
  return n .. "-" .. sum
end

---------------------------------------------------------------------------
-- Learning: XP per zone, quest XP calibration, abandoned quests
---------------------------------------------------------------------------
local lastXP, lastMax, lastLevel
local lastGain = 0
local recentTurnIn = {}

local function OnXPUpdate()
  local xp, max, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  if lastXP then
    local gain
    if lvl > lastLevel then gain = (lastMax - lastXP) + xp else gain = xp - lastXP end
    if gain > 0 then
      local map = C_Map.GetBestMapForUnit("player")
      if map then
        local s = DuoRouteChar.zoneStats[map] or { xp = 0, secs = 0 }
        s.xp = s.xp + gain
        DuoRouteChar.zoneStats[map] = s
      end
      lastGain = GetTime()
    end
  end
  lastXP, lastMax, lastLevel = xp, max, lvl
end

-- Count time in a zone only while actively levelling (XP gained in the last 3 minutes)
local tickAcc = 0
local function OnTick(_, dt)
  tickAcc = tickAcc + dt
  if tickAcc < 5 then return end
  if GetTime() - lastGain < 180 and not UnitIsAFK("player") then
    local map = C_Map.GetBestMapForUnit("player")
    if map then
      local s = DuoRouteChar.zoneStats[map] or { xp = 0, secs = 0 }
      s.secs = s.secs + tickAcc
      DuoRouteChar.zoneStats[map] = s
    end
  end
  tickAcc = 0
end

function DR.Calibration()
  local c = DuoRouteChar and DuoRouteChar.calib
  if not c or c.n < 5 or c.est <= 0 then return 1 end
  local f = c.actual / c.est
  return math.max(0.5, math.min(2.0, f))
end

-- Learned XP/hour in a zone relative to your overall rate (1 = average)
function DR.ZoneRateFactor(uiMap)
  local stats = DuoRouteChar and DuoRouteChar.zoneStats
  if not stats or not uiMap then return 1, nil end
  local totXP, totSecs = 0, 0
  for _, s in pairs(stats) do totXP = totXP + s.xp; totSecs = totSecs + s.secs end
  local s = stats[uiMap]
  if not s or s.secs < 900 or totSecs < 1800 then return 1, nil end
  local rate = s.xp / s.secs
  local avg = totXP / totSecs
  if avg <= 0 then return 1, nil end
  return math.max(0.75, math.min(1.3, rate / avg)), rate * 3600
end

local function OnTurnIn(questID, xpReward)
  recentTurnIn[questID] = GetTime()
  local q = DR.Q[questID]
  local est = q and DR.BaseQuestXP(q, UnitLevel("player")) or 0
  local h = DuoRouteChar.history
  h[#h + 1] = { q = questID, t = now(), xp = xpReward or 0, est = est, lvl = UnitLevel("player"),
    map = C_Map.GetBestMapForUnit("player") }
  while #h > 1500 do table.remove(h, 1) end
  if q and est > 0 and xpReward and xpReward > 0 then
    local c = DuoRouteChar.calib
    -- exponential decay keeps the factor tracking recent levels
    c.actual = c.actual * 0.97 + xpReward
    c.est = c.est * 0.97 + est
    c.n = c.n + 1
  end
  DuoRouteChar.skipped[questID] = nil
  DR.me.completed[questID] = true
  if DR.Sync then DR.Sync.QuestDone(questID) end
end

local function OnQuestRemoved(questID)
  C_Timer.After(1, function()
    if recentTurnIn[questID] and GetTime() - recentTurnIn[questID] < 5 then return end
    if C_QuestLog.IsQuestFlaggedCompleted(questID) then return end
    DuoRouteChar.skipped[questID] = (DuoRouteChar.skipped[questID] or 0) + 1
    DR.Debug("noted abandoned quest", questID)
  end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("QUEST_REMOVED")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")

local pending
function DR.QueueRefresh(full)
  if pending then
    pending.full = pending.full or full
    return
  end
  pending = { full = full }
  C_Timer.After(1, function()
    local p = pending; pending = nil
    DR.RefreshMe(p.full)
    if DR.Sync then DR.Sync.LocalChanged() end
    if DR.UI then DR.UI.Refresh() end
    if DR.Guide then DR.Guide.OnStateChanged() end
  end)
end

ev:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "PLAYER_LOGIN" then
    InitSaved()
    lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    DR.RefreshMe(true)
    ev:SetScript("OnUpdate", OnTick)
    if DR.Sync then DR.Sync.Init() end
    DR.Msg("loaded. Type /duo to open your duo planner.")
  elseif not DuoRouteChar then
    return
  elseif event == "QUEST_TURNED_IN" then
    OnTurnIn(a1, a2)
    DR.QueueRefresh(false)
  elseif event == "QUEST_REMOVED" then
    OnQuestRemoved(a1)
    DR.QueueRefresh(false)
  elseif event == "PLAYER_XP_UPDATE" then
    OnXPUpdate()
  elseif event == "PLAYER_LEVEL_UP" then
    DR.QueueRefresh(false)
  else
    DR.QueueRefresh(false)
  end
end)
