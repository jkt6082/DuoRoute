-- DuoRoute: party sync of levels, completed quests and quest logs
local ADDON, DR = ...
local Sync = {}
DR.Sync = Sync

local PREFIX = "DuoRt1"
local SEP = "\t"
local queue, ticker = {}, nil

---------------------------------------------------------------------------
-- base36 id lists
---------------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
  local s = ""
  repeat
    local d = n % 36
    s = DIGITS:sub(d + 1, d + 1) .. s
    n = math.floor(n / 36)
  until n == 0
  return s
end

local function ids(str, out)
  for raw in str:gmatch("[^,]+") do
    local done = raw:sub(-1) == "*"
    local tok = done and raw:sub(1, -2) or raw
    local n = tonumber(tok, 36)
    if n then out[n] = done and 2 or true end
  end
  return out
end

-- split a list of ids into messages of at most ~240 characters
local function Chunks(list)
  local chunks, cur = {}, {}
  local len = 0
  for _, v in ipairs(list) do
    if len + #v + 1 > 230 then
      chunks[#chunks + 1] = table.concat(cur, ","); cur = {}; len = 0
    end
    cur[#cur + 1] = v; len = len + #v + 1
  end
  if #cur > 0 then chunks[#chunks + 1] = table.concat(cur, ",") end
  return chunks
end

---------------------------------------------------------------------------
-- sending (throttled)
---------------------------------------------------------------------------
local function Pump()
  local msg = table.remove(queue, 1)
  if not msg then
    if ticker then ticker:Cancel(); ticker = nil end
    return
  end
  if IsInGroup() then
    C_ChatInfo.SendAddonMessage(PREFIX, msg, IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY")
  end
end

local function Send(msg)
  queue[#queue + 1] = msg
  if not ticker then ticker = C_Timer.NewTicker(0.3, Pump) end
end

-- drop queued messages of one kind so a newer full list replaces an older one
local function Unqueue(kind)
  local prefix = kind .. SEP
  for i = #queue, 1, -1 do
    if queue[i]:sub(1, #prefix) == prefix then table.remove(queue, i) end
  end
end

function Sync.SendHello()
  local me = DR.me
  if not me.level or not IsInGroup() then return end
  Send(table.concat({ "H", DR.VERSION, me.level, me.raceID or 0, me.classID or 0, me.faction or "",
    me.xp or 0, me.xpMax or 1, me.mapID or 0, math.floor((me.x or 0) * 1000), math.floor((me.y or 0) * 1000),
    DR.CompletedHash(me.completed) }, SEP))
end

function Sync.SendActive()
  Unqueue("A")
  local list = {}
  for id in pairs(DR.me.active) do list[#list + 1] = b36(id) .. (DR.me.activeDone[id] and "*" or "") end
  local chunks = Chunks(list)
  if #chunks == 0 then chunks = { "" } end
  for i, c in ipairs(chunks) do Send(table.concat({ "A", i, #chunks, c }, SEP)) end
end

function Sync.SendCompleted()
  Unqueue("C")
  local list = {}
  for id in pairs(DR.me.completed) do
    if DR.Q[id] then list[#list + 1] = b36(id) end -- only quests the planner knows about
  end
  local chunks = Chunks(list)
  if #chunks == 0 then chunks = { "" } end
  for i, c in ipairs(chunks) do Send(table.concat({ "C", i, #chunks, c }, SEP)) end
end

function Sync.QuestDone(id) if IsInGroup() then Send("D" .. SEP .. b36(id)) end end

---------------------------------------------------------------------------
-- partner state
---------------------------------------------------------------------------
local partnerName
local incoming = {}   -- partial multi-part messages

local function PartnerRecord(name)
  local p = DuoRouteDB.partners[name]
  if not p then
    p = { name = name, completed = {}, active = {}, activeDone = {} }
    DuoRouteDB.partners[name] = p
  end
  p.completed = p.completed or {}; p.active = p.active or {}; p.activeDone = p.activeDone or {}
  return p
end

-- The partner in your group, or the last one you levelled with (shown as offline)
function Sync.Partner()
  local name = partnerName or DuoRouteDB.lastPartner
  if not name then return nil end
  local p = DuoRouteDB.partners[name]
  if not p or not p.level then return nil end
  p.offline = not (partnerName and UnitInParty(Ambiguate(name, "none")))
  return p
end

function Sync.PartnerName() return partnerName or DuoRouteDB.lastPartner end

local function Changed()
  if DR.UI then DR.UI.Refresh() end
  if DR.Guide then DR.Guide.OnStateChanged() end
end

local function OnMessage(msg, sender)
  local short = Ambiguate(sender, "none")
  if UnitIsUnit(short, "player") then return end
  if not UnitInParty(short) then return end
  local forced = DuoRouteDB.forcedPartner
  if forced and forced:lower() ~= Ambiguate(sender, "short"):lower() then return end
  if not partnerName then partnerName = sender; DuoRouteDB.lastPartner = sender end
  if sender ~= partnerName then return end

  local parts = { strsplit(SEP, msg) }
  local kind = parts[1]
  local p = PartnerRecord(sender)
  if kind == "H" then
    p.version = parts[2]
    p.level = tonumber(parts[3])
    p.raceID = tonumber(parts[4])
    p.raceBit = DR.RACE_BIT[p.raceID] or 0
    p.classID = tonumber(parts[5])
    p.classBit = p.classID and 2 ^ (p.classID - 1) or 0
    p.faction = parts[6]
    p.xp, p.xpMax = tonumber(parts[7]), tonumber(parts[8])
    p.mapID = tonumber(parts[9])
    p.x, p.y = (tonumber(parts[10]) or 0) / 1000, (tonumber(parts[11]) or 0) / 1000
    p.updated = time()
    if parts[12] ~= p.hash then Send("R") end -- their completed list changed
    Changed()
  elseif kind == "R" then
    Sync.SendCompleted()
    Sync.SendActive()
  elseif kind == "C" or kind == "A" then
    local i, n = tonumber(parts[2]), tonumber(parts[3])
    local key = kind
    if i == 1 then incoming[key] = {} end
    local acc = incoming[key]
    if not acc then return end
    ids(parts[4] or "", acc)
    if i == n then
      incoming[key] = nil
      if kind == "C" then
        p.completed = {}
        for id in pairs(acc) do p.completed[id] = true end
        -- keep turn-ins that arrived while this list was in flight
        for id, t in pairs(p.recentDone or {}) do
          if time() - t < 120 then p.completed[id] = true else p.recentDone[id] = nil end
        end
        p.hash = DR.CompletedHash(p.completed)
      else
        p.active, p.activeDone = {}, {}
        for id, v in pairs(acc) do
          p.active[id] = true
          if v == 2 then p.activeDone[id] = true end
        end
      end
      Changed()
    end
  elseif kind == "D" then
    local id = tonumber(parts[2], 36)
    if id then
      p.completed[id] = true; p.active[id] = nil; p.activeDone[id] = nil
      p.recentDone = p.recentDone or {}
      p.recentDone[id] = time()
      p.hash = DR.CompletedHash(p.completed)
      Changed()
    end
  end
end

---------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------
local lastActiveSend = 0
function Sync.LocalChanged()
  if not IsInGroup() then return end
  Sync.SendHello()
  if GetTime() - lastActiveSend > 2 then
    lastActiveSend = GetTime()
    Sync.SendActive()
  end
end

local function OnRoster()
  if not IsInGroup() then partnerName = nil; Changed(); return end
  if partnerName and not UnitInParty(Ambiguate(partnerName, "none")) then partnerName = nil end
  Sync.SendHello()
  Send("R")
end

function Sync.Init()
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:RegisterEvent("GROUP_ROSTER_UPDATE")
  f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "CHAT_MSG_ADDON" then
      if a1 == PREFIX then OnMessage(a2, a4) end
    else
      OnRoster()
    end
  end)
  if IsInGroup() then OnRoster() end
  -- heartbeat keeps the partner's level and position fresh
  C_Timer.NewTicker(30, function() if IsInGroup() then DR.RefreshMe(false); Sync.SendHello() end end)
end

function Sync.Force()
  incoming = {}
  if IsInGroup() then Sync.SendHello(); Sync.SendCompleted(); Sync.SendActive(); Send("R") end
end
