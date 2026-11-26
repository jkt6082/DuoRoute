-- DuoRoute: quest availability and duo zone planning
local ADDON, DR = ...
local F, FLAG = DR.F, DR.FLAG
local HasBit = DR.HasBit

---------------------------------------------------------------------------
-- XP estimates (classic quest XP falloff, calibrated by your real turn-ins)
---------------------------------------------------------------------------
local FALLOFF = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }

local function QuestLevel(q, level)
  if q[F.LVL] > 0 then return q[F.LVL] end
  if q[F.LVL] == -1 then return level or q[F.REQ] end -- scales to the player
  return q[F.REQ]
end
DR.QuestLevel = QuestLevel

function DR.BaseQuestXP(q, level)
  local qlvl = QuestLevel(q, level)
  local base = q[F.XP]
  if not base or base <= 0 then base = DR.D.LX[math.max(1, math.min(60, qlvl))] or 0 end
  local diff = (level or 1) - qlvl
  local mult = 1
  if diff >= 10 then mult = 0.1 elseif diff > 5 then mult = FALLOFF[diff] end
  return base * mult
end

function DR.QuestXP(q, level)
  return DR.BaseQuestXP(q, level) * DR.Calibration()
end

---------------------------------------------------------------------------
-- Quest tags: Dungeon / Raid / Elite (group). Corrections first, then the game's own answer.
---------------------------------------------------------------------------
DR.TAG = { ELITE = 1, RAID = 62, DUNGEON = 81, HEROIC = 85, RAID10 = 88, RAID25 = 89 }
local INSTANCE_TAGS = { [62] = true, [81] = true, [85] = true, [88] = true, [89] = true }
local tagCache = {}

function DR.QuestTag(id)
  local c = tagCache[id]
  if c ~= nil then return c or nil end
  local t = DR.D.TAG and DR.D.TAG[id]
  if t then tagCache[id] = t; return t end
  if C_QuestLog.GetQuestTagInfo then
    local ok, info = pcall(C_QuestLog.GetQuestTagInfo, id)
    if ok and type(info) == "table" and info.tagID then
      tagCache[id] = info.tagID
      return info.tagID
    end
  end
  return nil
end

-- Does doing this quest mean going into a dungeon or raid?
local instanceCache = {}
function DR.IsInstanceQuest(id, q)
  if not q then return false end
  local c = instanceCache[id]
  if c ~= nil then return c end
  local r = false
  if INSTANCE_TAGS[DR.QuestTag(id) or 0] then r = true end
  if not r and DR.IsDungeon(DR.WorkZone(q)) then r = true end
  local obj = q[F.OBJ]
  if not r and obj then
    for i = 1, #obj do
      local a = obj[i][1]
      if DR.IsDungeon(a) or not DR.Z[a] then r = true; break end
    end
  end
  instanceCache[id] = r
  return r
end

-- The dungeon a quest belongs to (for grouping in the Dungeons tab)
function DR.InstanceArea(id, q)
  local obj = q[F.OBJ]
  if obj then for i = 1, #obj do if DR.IsDungeon(obj[i][1]) then return obj[i][1] end end end
  return DR.WorkZone(q)
end

---------------------------------------------------------------------------
-- Status of one quest for one player context
--   "done" | "active" | "avail" | "soon" (needs <=2 more levels) | "locked" | "na"
---------------------------------------------------------------------------
local function AnyIn(list, set)
  if not list then return false end
  for i = 1, #list do if set[list[i]] then return true end end
  return false
end

local function AllIn(list, set)
  if not list then return true end
  for i = 1, #list do if not set[list[i]] then return false end end
  return true
end

function DR.Status(id, q, ctx)
  if not ctx or not ctx.level then return "na" end
  local done, active = ctx.completed, ctx.active
  if done[id] then return "done" end
  if active[id] then return "active" end
  local flags = q[F.FLAGS]
  if HasBit(flags, FLAG.SKILL) or HasBit(flags, FLAG.ITEM) or HasBit(flags, FLAG.REPREQ)
    or HasBit(flags, FLAG.EVENT) then return "na" end

  -- faction / race / class
  local races = q[F.RACES]
  if races and races > 0 then
    if not HasBit(races, ctx.raceBit) then return "na" end
  else
    if ctx.faction == "A" and HasBit(flags, FLAG.HORDE_ONLY) then return "na" end
    if ctx.faction == "H" and HasBit(flags, FLAG.ALLIANCE_ONLY) then return "na" end
  end
  local classes = q[F.CLASSES]
  if classes and classes > 0 and not HasBit(classes, ctx.classBit) then return "na" end

  -- closed by other quests in the chain
  if AnyIn(q[F.EXCL], done) or AnyIn(q[F.EXCL], active) then return "na" end
  local nx = q[F.NEXT]
  if nx and nx > 0 and (done[nx] or active[nx]) then return "na" end
  local bc = q[F.BC]
  if bc and bc > 0 and (done[bc] or active[bc]) then return "na" end
  local mx = q[F.MAX]
  if mx and mx > 0 and ctx.level > mx then return "na" end

  -- prerequisites
  if not AllIn(q[F.PREG], done) then return "locked" end
  local ps = q[F.PRES]
  if ps and #ps > 0 and not AnyIn(ps, done) then return "locked" end
  local parent = q[F.PARENT]
  if parent and parent > 0 and not active[parent] then return "locked" end

  local req = q[F.REQ]
  if req > ctx.level then
    if req <= ctx.level + 2 then return "soon" end
    return "na"
  end
  return "avail"
end

local function GreyLevel(level)
  if level <= 5 then return 0 end
  if level < 40 then return level - math.floor(level / 10) - 5 end
  return level - math.floor(level / 5) - 1
end
DR.GreyLevel = GreyLevel

---------------------------------------------------------------------------
-- Duo plan
---------------------------------------------------------------------------
local USEFUL = { avail = true, active = true }

-- Value of one quest for the duo, plus tags describing who can do it
local function Evaluate(id, q, me, partner)
  local s1 = DR.Status(id, q, me)
  local s2 = partner and DR.Status(id, q, partner) or nil
  local mine, theirs = USEFUL[s1], s2 and USEFUL[s2]
  if not mine and not theirs then return nil end

  local qlvl = QuestLevel(q, me.level)
  -- grey quests are noise unless one of you already has them
  local low = math.min(me.level, partner and partner.level or me.level)
  if qlvl <= GreyLevel(low) and s1 ~= "active" and s2 ~= "active" then return nil end
  local xp1 = mine and DR.QuestXP(q, me.level) or 0
  local xp2 = theirs and DR.QuestXP(q, partner.level) or 0
  local value
  if partner then
    if mine and theirs then value = (xp1 + xp2) / 2
    else value = 0.35 * math.max(xp1, xp2) end      -- one of you only: still worth helping
  else
    value = xp1
  end
  if s1 == "active" or s2 == "active" then value = value * 1.25 end

  -- difficulty: red quests are slower even as a duo
  local top = math.max(me.level, partner and partner.level or 0)
  local over = qlvl - top
  if over >= 5 then value = value * 0.45 elseif over >= 4 then value = value * 0.7 end

  local skipped = DuoRouteChar.skipped[id]
  if skipped then value = value * 0.25 end
  if DuoRouteChar.ignored[id] then return nil end

  local e = { id = id, q = q, s1 = s1, s2 = s2, value = value, xp = math.floor(xp1 + 0.5) }
  if partner then
    if mine and theirs then e.tag = "both"
    elseif mine then e.tag = "you" else e.tag = "partner" end
    if s1 == "active" and s2 == "avail" then e.share = "give" end
    if s2 == "active" and s1 == "avail" then e.share = "ask" end
  else
    e.tag = "you"
  end
  e.complete = (s1 == "active" and me.activeDone[id]) or false
  return e
end

-- Build zone recommendations for you and your partner
function DR.Plan()
  local me = DR.me
  local partner = DR.Sync and DR.Sync.Partner() or nil
  local zones, dungeons = {}, {}
  local soon = 0
  for id, q in pairs(DR.Q) do
    local e = Evaluate(id, q, me, partner)
    if e then
      local wz = DR.WorkZone(q)
      local inst = DR.IsInstanceQuest(id, q)
      if inst then wz = DR.InstanceArea(id, q) end
      local bucket = inst and dungeons or zones
      local z = bucket[wz]
      if not z then
        z = { area = wz, entries = {}, value = 0, pickups = 0, inlog = 0, both = 0, share = 0 }
        bucket[wz] = z
      end
      z.entries[#z.entries + 1] = e
      z.value = z.value + e.value
      if e.s1 == "active" or e.s2 == "active" then z.inlog = z.inlog + 1 else z.pickups = z.pickups + 1 end
      if e.tag == "both" then z.both = z.both + 1 end
      if e.share then z.share = z.share + 1 end
    end
  end

  local currentMap = me.mapID
  local list = {}
  for area, z in pairs(zones) do
    if area > 0 then
      local uiMap = DR.UiMapForArea(area)
      local factor, rate = DR.ZoneRateFactor(uiMap)
      z.rate = rate
      z.score = z.value * factor
      if uiMap and currentMap and uiMap == currentMap then z.score = z.score * 1.15; z.here = true end
      list[#list + 1] = z
    end
  end
  table.sort(list, function(a, b) return a.score > b.score end)

  local dlist = {}
  for area, z in pairs(dungeons) do z.score = z.value; dlist[#dlist + 1] = z end
  table.sort(dlist, function(a, b) return a.score > b.score end)

  local xpMax = me.xpMax or 1
  if partner and partner.xpMax then xpMax = (xpMax + partner.xpMax) / 2 end
  for _, z in ipairs(list) do z.levels = z.value / math.max(1, xpMax) end
  return { zones = list, dungeons = dlist, partner = partner }
end

-- Sort a zone's quests: ready to turn in, in log, then pickups grouped by quest giver
function DR.SortEntries(entries)
  local function rank(e)
    if e.complete then return 0 end
    if e.s1 == "active" or e.s2 == "active" then return 1 end
    if e.share then return 2 end
    return 3
  end
  table.sort(entries, function(a, b)
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then return ra < rb end
    local na, nb = a.q[F.STARTER] or "", b.q[F.STARTER] or ""
    if na ~= nb then return na < nb end
    return a.value > b.value
  end)
  return entries
end

---------------------------------------------------------------------------
-- Next step: nearest turn-in or pickup on your current map
---------------------------------------------------------------------------
function DR.NextStep(plan)
  local me = DR.me
  if not me.mapID or not me.x then return nil end
  local best, bestD
  for _, z in ipairs(plan.zones) do
    for _, e in ipairs(z.entries) do
      local area, x, y, verb
      if e.complete then
        area, x, y, verb = e.q[F.FZ], e.q[F.FX], e.q[F.FY], "Turn in"
      elseif e.s1 == "avail" and (e.tag == "both" or not plan.partner) then
        area, x, y, verb = e.q[F.SZ], e.q[F.SX], e.q[F.SY], "Pick up"
      end
      if area and area > 0 and DR.UiMapForArea(area) == me.mapID then
        local dx, dy = x / 100 - me.x, y / 100 - me.y
        local d = dx * dx + dy * dy
        if e.complete then d = d * 0.5 end -- prefer turn-ins
        if not bestD or d < bestD then best, bestD = { e = e, verb = verb, area = area, x = x, y = y }, d end
      end
    end
  end
  return best
end

---------------------------------------------------------------------------
-- Waypoints (Blizzard pin, plus TomTom if installed)
---------------------------------------------------------------------------
function DR.SetWaypoint(area, x, y, title, silent)
  local uiMap = DR.UiMapForArea(area)
  if not uiMap or not x or x <= 0 then
    DR.Msg("No map location for", title or "that quest")
    return
  end
  if DR.Arrow then DR.Arrow.SetTarget(uiMap, x / 100, y / 100, title) end
  if TomTom and TomTom.AddWaypoint then
    TomTom:AddWaypoint(uiMap, x / 100, y / 100, { title = title, persistent = false })
  end
  if C_Map.CanSetUserWaypointOnMap(uiMap) then
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMap, x / 100, y / 100))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
  end
  if not silent then DR.Msg(string.format("Waypoint: %s (%s %.1f, %.1f)", title or "", DR.ZoneName(area), x, y)) end
end
