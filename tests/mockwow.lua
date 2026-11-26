-- Minimal WoW API mock for testing DuoRoute logic outside the game.
-- Globals expected from the test driver: ME = { name, level, raceID, classID, faction, completed = {ids}, log = {ids}, done = {ids}, mapID, x, y }
SENT = {}
local frames = {}
local timers = {}
FRAMES = frames
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
unpack = unpack or table.unpack
function strsplit(sep, s)
  local out = {}
  local pattern = "([^" .. sep .. "]*)"
  local i = 1
  while true do
    local a, b = s:find(sep, i, true)
    if not a then out[#out + 1] = s:sub(i); break end
    out[#out + 1] = s:sub(i, a - 1)
    i = b + 1
  end
  return unpack(out)
end
NOW = 1000000
function time() return NOW end
function GetTime() return NOW end
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end io.write(table.concat(t, " "), "\n") end
UISpecialFrames = {}
SlashCmdList = {}
Enum = { UIMapType = { Zone = 3, Continent = 2 } }

local function newObj()
  local o = { scripts = {}, events = {} }
  local mt = {}
  mt.__index = function(t, k)
    local f = function(self, ...)
      if k == "SetScript" then local name, fn = ...; self.scripts[name] = fn
      elseif k == "RegisterEvent" or k == "RegisterUnitEvent" then self.events[(...)] = true
      elseif k == "CreateFontString" or k == "CreateTexture" or k == "CreateAnimationGroup" or k == "CreateAnimation" then return newObj()
      elseif k == "IsShown" then return self.shown
      elseif k == "Show" then self.shown = true
      elseif k == "Hide" then self.shown = false
      elseif k == "GetWidth" then return 300
      elseif k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0
      elseif k == "SetText" then self.text = ...
      elseif k == "SetParent" then self.parent = ...
      elseif k == "GetFrameLevel" then return 1
      elseif k == "SetRotation" then self.rot = ...; LASTROT = ...
      end
    end
    return f
  end
  return setmetatable(o, mt)
end
function CreateFrame() local f = newObj(); frames[#frames + 1] = f; return f end
GameTooltip = newObj()
UIParent = newObj()

C_Timer = {
  After = function(d, fn) timers[#timers + 1] = fn end,
  NewTicker = function(d, fn) local t = { fn = fn, Cancel = function(self) self.dead = true end }; timers[#timers + 1] = t; return t end,
}
function RunTimers(n)
  for _ = 1, (n or 50) do
    local list = timers; timers = {}
    if #list == 0 then return end
    for _, t in ipairs(list) do
      if type(t) == "function" then t() elseif not t.dead then t.fn(); if not t.dead then timers[#timers + 1] = t end end
    end
  end
end

local function set(list) local s = {} for _, id in ipairs(list or {}) do s[id] = true end return s end
function UnitName(u) if u == "npc" then return NPCNAME end return ME.name end
function UnitLevel() return ME.level end
function UnitFactionGroup() return ME.faction end
function UnitRace() return "Race", "Race", ME.raceID end
function UnitClass() return "Class", "CLASS", ME.classID end
function UnitXP() return ME.xp or 1000 end
function UnitXPMax() return ME.xpMax or 100000 end
function UnitIsAFK() return false end
function UnitIsUnit(a, b) return a == ME.name end
function UnitInParty(n) return n == ME.partner end
function IsInGroup() return ME.partner ~= nil end
function Ambiguate(n) return (n:gsub("%-.*", "")) end
LE_PARTY_CATEGORY_INSTANCE = 2

C_Map = {
  GetBestMapForUnit = function() return ME.mapID end,
  GetPlayerMapPosition = function() return { GetXY = function() return ME.x, ME.y end } end,
  GetMapInfo = function(id)
    if id == 1414 or id == 1415 then return { name = "Continent" .. id, mapType = 2 } end
    if id and id > 0 and id < 2000 then
      local ek = { [1425]=1, [1458]=1, [1420]=1, [1422]=1, [1423]=1, [1427]=1, [1428]=1, [1434]=1, [1418]=1, [1419]=1, [1435]=1, [1436]=1, [1437]=1, [1416]=1, [1426]=1, [1421]=1 }
      return { name = "Map" .. id, mapType = 3, parentMapID = ek[id] and 1415 or 1414 }
    end
  end,
  CanSetUserWaypointOnMap = function() return true end,
  SetUserWaypoint = function(p) LASTWP = p end,
}
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
C_Map.GetWorldPosFromMapPos = function(uiMap, pos)
  local info = C_Map.GetMapInfo(uiMap)
  if not info then return nil end
  local cont = info.parentMapID == 1415 and 0 or 1
  local ox = (uiMap * 7919 % 9) * 3000
  local oy = (uiMap * 104729 % 9) * 3000
  return cont, CreateVector2D(ox + pos.x * 3500, oy + pos.y * 3500)
end
TAXI_NODES = {}
function GetTaxiMapID() return 1414 end
C_TaxiMap = { GetAllTaxiNodes = function() return TAXI_NODES end }
Enum.FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 }
C_Container = { GetItemCooldown = function() return 0, 0, 1 end }
function UnitOnTaxi() return false end
FACING = 0
function GetPlayerFacing() return FACING end
C_Map.GetMapWorldSize = function(id) return 3500, 2333 end
C_Map.GetMapPosFromWorldPos = function(cont, wpos, map)
  local ox = (map * 7919 % 9) * 3000
  local oy = (map * 104729 % 9) * 3000
  return map, CreateVector2D((wpos.x - ox) / 3500, (wpos.y - oy) / 3500)
end
function GetBindLocation() return "Gadgetzan" end
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
  SendAddonMessage = function(prefix, msg, chan) SENT[#SENT + 1] = { prefix, msg, chan } end }

C_QuestLog = {
  GetAllCompletedQuestIDs = function() return ME.completed end,
  IsQuestFlaggedCompleted = function(id) return set(ME.completed)[id] == true end,
  GetNumQuestLogEntries = function() return #(ME.log or {}) end,
  GetInfo = function(i) return { questID = ME.log[i], isHeader = false } end,
  IsComplete = function(id) return set(ME.done)[id] == true end,
  GetQuestObjectives = function(id) return {} end,
}

function FireEvent(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
