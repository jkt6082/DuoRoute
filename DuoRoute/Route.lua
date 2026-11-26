-- DuoRoute: step-by-step route to level 60, simulated from your real progress
local ADDON, DR = ...
local F, FLAG = DR.F, DR.FLAG
local HasBit = DR.HasBit

-- XP needed to go from level n to n+1 (Classic curve, which Forever keeps)
local XP_TO_LEVEL = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900,
  14400, 16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300,
  47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300,
  111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900,
  195000, 202300, 209800 }
DR.XP_TO_LEVEL = XP_TO_LEVEL

local MAX_STEPS = 1500
local ZONE_TRAVEL_MIN = 8
local CONTINENT_TRAVEL_MIN = 22
local LOG_LIMIT = 20

-- continent of an area, from the client's map tree
local continentCache = {}
function DR.ContinentOf(area)
  if continentCache[area] ~= nil then return continentCache[area] or nil end
  local u = DR.UiMapForArea(area)
  local result = false
  local guard = 0
  while u and guard < 8 do
    local info = C_Map.GetMapInfo(u)
    if not info then break end
    if info.mapType == Enum.UIMapType.Continent then result = u; break end
    u = info.parentMapID
    guard = guard + 1
  end
  continentCache[area] = result
  return result or nil
end

local function TravelMinutes(from, to)
  if from == to then return 0 end
  if not from then return ZONE_TRAVEL_MIN end
  local a, b = DR.ContinentOf(from), DR.ContinentOf(to)
  if a and b and a ~= b then return CONTINENT_TRAVEL_MIN end
  return ZONE_TRAVEL_MIN
end

---------------------------------------------------------------------------
-- Index: which quests involve each area (pickup, objectives, turn-in)
---------------------------------------------------------------------------
local byArea
local function BuildIndex()
  byArea = {}
  local function add(area, id)
    if not area or area <= 0 then return end
    local l = byArea[area]
    if not l then l = {}; byArea[area] = l end
    if l[#l] ~= id then l[#l + 1] = id end
  end
  for id, q in pairs(DR.Q) do
    add(q[F.SZ], id)
    add(q[F.FZ], id)
    add(DR.WorkZone(q), id)
    local obj = q[F.OBJ]
    if obj then for i = 1, #obj do add(obj[i][1], id) end end
  end
end

---------------------------------------------------------------------------
-- Time model (minutes)
---------------------------------------------------------------------------
local function MoveMinutes(level, d)
  -- one full map width is roughly 3,500 yards; mounted from 40
  return d * (level >= 40 and 5.2 or 8.3)
end

-- Kill credit is shared in a group; item drops are not, but two players kill twice as fast.
-- Solo times include eating/drinking downtime, which a duo (especially with a healer) mostly avoids.
local function ObjectiveMinutes(o, duo)
  local label, n = o[4], o[5]
  local known = n and n > 0
  local m
  if label:find("^Kill") then
    m = known and n * (duo and 0.28 or 0.5) or (duo and 2.5 or 4.5)
  elseif label:find("^Collect") then
    m = known and n * (duo and 0.55 or 0.65) or (duo and 3.5 or 4.5)
  else
    m = 1
  end
  return math.max(1, m)
end

local function MobXP(level) return level * 5 + 45 end

local function Dist(ax, ay, bx, by)
  local dx, dy = (ax - bx) / 100, (ay - by) / 100
  return math.sqrt(dx * dx + dy * dy)
end

---------------------------------------------------------------------------
-- Simulation state
---------------------------------------------------------------------------
local function Copy(t) local o = {} for k, v in pairs(t or {}) do o[k] = v end return o end

local function NewSim(me, partner)
  local s = {
    level = me.level, xp = me.xp or 0, minutes = 0,
    ctx = { level = me.level, faction = me.faction, raceBit = me.raceBit, classBit = me.classBit,
      completed = Copy(me.completed), active = Copy(me.active), activeDone = Copy(me.activeDone) },
    objDone = {}, workDone = {},
  }
  local n = 0
  for _ in pairs(s.ctx.active) do n = n + 1 end
  s.logCount = n
  s.known = DR.Travel.KnownSet(s.ctx)
  s.knownCount = 0
  for _ in pairs(s.known) do s.knownCount = s.knownCount + 1 end
  if partner then
    s.partner = { level = partner.level, faction = partner.faction, raceBit = partner.raceBit, classBit = partner.classBit,
      completed = Copy(partner.completed), active = Copy(partner.active), activeDone = Copy(partner.activeDone) }
  end
  return s
end

local function GainXP(s, amount, steps)
  s.xp = s.xp + amount
  while s.level < 60 and s.xp >= XP_TO_LEVEL[s.level] do
    s.xp = s.xp - XP_TO_LEVEL[s.level]
    s.level = s.level + 1
    s.ctx.level = s.level
    if s.partner then s.partner.level = math.max(s.partner.level, s.level) end
    if s.level % 2 == 0 and s.level < 60 then
      steps[#steps + 1] = { kind = "train", level = s.level, t = s.minutes, text = "Level " .. s.level .. ": visit your class trainer for new spells" }
    end
    steps[#steps + 1] = { kind = "level", level = s.level, minutes = s.minutes }
  end
end

-- Is a quest worth putting in the route right now?
local function Worth(s, id, q)
  local st = DR.Status(id, q, s.ctx)
  if st ~= "avail" and st ~= "active" then return false end
  -- never route into dungeons or raids; elite (group) quests only as a duo.
  -- A dungeon quest already in your log is only turned in once it's done.
  local blocked = DR.IsInstanceQuest(id, q) or (DR.QuestTag(id) == DR.TAG.ELITE and not s.partner)
  if blocked then
    if st == "active" and s.ctx.activeDone[id] then return true, st end
    return false
  end
  if st == "avail" then
    if DuoRouteChar.ignored[id] or DuoRouteChar.skipped[id] then return false end
    local qlvl = DR.QuestLevel(q, s.level)
    if qlvl <= DR.GreyLevel(s.level) or qlvl > s.level + 4 then return false end
    if not q[F.SZ] or q[F.SZ] <= 0 or not q[F.FZ] or q[F.FZ] <= 0 then return false end
    if s.partner then
      local p = DR.Status(id, q, s.partner)
      if p ~= "avail" and p ~= "active" and DR.QuestXP(q, s.level) < 0.3 * (DR.D.LX[s.level] or 1) then
        return false -- partner can't help and it's not worth a solo detour
      end
    end
  end
  return true, st
end

local function QuestMinutes(s, q)
  local m = 0.6
  if HasBit(q[F.FLAGS], FLAG.UNLOCATED) then m = m + 8 end
  local obj = q[F.OBJ]
  if obj then for i = 1, #obj do m = m + ObjectiveMinutes(obj[i], s.partner ~= nil) + 2 end end
  return m
end

local function QuestValue(s, id, q)
  local v = DR.QuestXP(q, s.level)
  if DR.QuestTag(id) == DR.TAG.ELITE then v = v * 0.7 end -- doable as a duo, but slower and riskier
  if HasBit(q[F.FLAGS], FLAG.UNLOCATED) then v = v * 0.75 end -- less certain, so slightly less attractive
  if s.partner then
    local p = DR.Status(id, q, s.partner)
    if p == "avail" or p == "active" then v = v * 1.15 end
  end
  return v
end

---------------------------------------------------------------------------
-- Zone choice: best XP per minute, with enough content to be worth the trip
---------------------------------------------------------------------------
local function NextActionArea(s, id, q, st)
  if st == "avail" then return q[F.SZ] end
  if s.ctx.activeDone[id] then return q[F.FZ] end
  local obj = q[F.OBJ]
  if obj then
    local done = s.objDone[id] or {}
    for i = 1, #obj do if not done[i] then return obj[i][1] end end
  end
  if HasBit(q[F.FLAGS], FLAG.UNLOCATED) and not (s.workDone[id]) then return DR.WorkZone(q) end
  return q[F.FZ]
end

local function ZoneTravel(s, here, pos, area)
  if area == here then return 0 end
  local ax, ay = DR.Travel.Anchor(area, s.ctx.faction)
  return DR.Travel.SimMinutes(here, pos and pos.x, pos and pos.y, area, ax, ay, s.known, s.knownCount, s.level, s.ctx.faction)
end

local function ChooseZone(s, here, exclude, pos)
  local zones = {}
  local logFull = s.logCount >= LOG_LIMIT
  for id, q in pairs(DR.Q) do
    local ok, st = Worth(s, id, q)
    if ok and st == "avail" and logFull then ok = false end
    if ok then
      local area = NextActionArea(s, id, q, st)
      if area and area > 0 and not DR.IsDungeon(area) and not exclude[area] then
        local z = zones[area]
        if not z then z = { value = 0, minutes = 0, n = 0 }; zones[area] = z end
        z.value = z.value + QuestValue(s, id, q)
        z.minutes = z.minutes + QuestMinutes(s, q)
        z.n = z.n + 1
      end
    end
  end
  local best, bestScore
  local need = XP_TO_LEVEL[math.min(59, s.level)] or 1
  for area, z in pairs(zones) do
    local minutes = z.minutes + ZoneTravel(s, here, pos, area)
    local rate = z.value / math.max(1, minutes)
    local factor = DR.ZoneRateFactor(DR.UiMapForArea(area))
    -- avoid hopping to zones with only a quest or two
    local score = rate * factor * math.min(1, z.value / (0.35 * need) + 0.15)
    if not bestScore or score > bestScore then best, bestScore = area, score end
  end
  return best
end

---------------------------------------------------------------------------
-- Work through one zone: nearest-first ordering of pickups, objectives, turn-ins
---------------------------------------------------------------------------
local function Actions(s, area)
  local list = {}
  for _, id in ipairs(byArea[area] or {}) do
    local q = DR.Q[id]
    local ok, st = Worth(s, id, q)
    if ok then
      if st == "avail" then
        if q[F.SZ] == area and s.logCount < LOG_LIMIT then
          list[#list + 1] = { kind = "accept", id = id, x = q[F.SX], y = q[F.SY] }
        end
      elseif s.ctx.activeDone[id] then
        if q[F.FZ] == area then list[#list + 1] = { kind = "turnin", id = id, x = q[F.FX], y = q[F.FY] } end
      else
        local obj = q[F.OBJ]
        local done = s.objDone[id] or {}
        local anyLeft = false
        if obj then
          for i = 1, #obj do
            if not done[i] then
              anyLeft = true
              if obj[i][1] == area then list[#list + 1] = { kind = "obj", id = id, idx = i, x = obj[i][2], y = obj[i][3] } end
            end
          end
        end
        if not anyLeft and HasBit(q[F.FLAGS], FLAG.UNLOCATED) and not s.workDone[id] then
          anyLeft = true
          if DR.WorkZone(q) == area then
            local x, y = nil, nil
            if q[F.SZ] == area then x, y = q[F.SX], q[F.SY] end
            list[#list + 1] = { kind = "work", id = id, x = x, y = y }
          end
        end
        if not anyLeft and q[F.FZ] == area then
          list[#list + 1] = { kind = "turnin", id = id, x = q[F.FX], y = q[F.FY] }
        end
      end
    end
  end
  return list
end

local function Execute(s, a, steps, area)
  local q = DR.Q[a.id]
  local step = { kind = a.kind, id = a.id, idx = a.idx, area = area, x = a.x, y = a.y, t = s.minutes }
  if a.kind == "accept" then
    s.ctx.active[a.id] = true
    s.logCount = s.logCount + 1
    if s.partner and DR.Status(a.id, q, s.partner) == "avail" then s.partner.active[a.id] = true end
    local obj = q[F.OBJ]
    if (not obj or #obj == 0) and not HasBit(q[F.FLAGS], FLAG.UNLOCATED) then
      s.ctx.activeDone[a.id] = true  -- deliveries / talk-to quests
    end
    s.minutes = s.minutes + 0.3
    step.text = "Accept " .. q[F.NAME]
    step.who = q[F.STARTER]
    if s.partner then
      local p = DR.Status(a.id, q, s.partner)
      if p ~= "avail" and p ~= "active" then step.youOnly = true end
    end
  elseif a.kind == "obj" then
    local o = q[F.OBJ][a.idx]
    s.objDone[a.id] = s.objDone[a.id] or {}
    s.objDone[a.id][a.idx] = true
    local mins = ObjectiveMinutes(o, s.partner ~= nil)
    s.minutes = s.minutes + mins
    local kills = (o[4]:find("^Kill") and ((o[5] and o[5] > 0) and o[5] or 8)) or (o[4]:find("^Collect") and 6) or 0
    if kills > 0 then GainXP(s, kills * MobXP(s.level) * (s.partner and 0.6 or 1), steps) end
    local all = true
    for i = 1, #q[F.OBJ] do if not s.objDone[a.id][i] then all = false end end
    if all then s.ctx.activeDone[a.id] = true end
    step.text = o[4] .. ((o[5] and o[5] > 0) and (" x" .. o[5]) or "")
    step.quest = q[F.NAME]
  elseif a.kind == "work" then
    s.workDone[a.id] = true
    s.minutes = s.minutes + (s.partner and 6 or 8)
    GainXP(s, 6 * MobXP(s.level) * (s.partner and 0.6 or 1), steps)
    local obj = q[F.OBJ]
    local all = true
    if obj then for i = 1, #obj do if not (s.objDone[a.id] or {})[i] then all = false end end end
    if all then s.ctx.activeDone[a.id] = true end
    step.text = "Finish the remaining objectives"
    step.quest = q[F.NAME]
  elseif a.kind == "turnin" then
    s.ctx.active[a.id] = nil; s.ctx.activeDone[a.id] = nil
    s.logCount = math.max(0, s.logCount - 1)
    s.ctx.completed[a.id] = true
    if s.partner then s.partner.active[a.id] = nil; s.partner.completed[a.id] = true end
    s.minutes = s.minutes + 0.3
    step.text = "Turn in " .. q[F.NAME]
    step.who = q[F.FINISHER] ~= "" and q[F.FINISHER] or q[F.STARTER]
    steps[#steps + 1] = step
    GainXP(s, DR.QuestXP(q, s.level), steps)
    return
  end
  steps[#steps + 1] = step
end

local function RunZone(s, area, steps, pos)
  local guard = 0
  while #steps < MAX_STEPS and s.level < 60 and guard < 400 do
    guard = guard + 1
    local list = Actions(s, area)
    if #list == 0 then return end
    -- nearest action; turn-ins and pickups at your current spot first
    local best, bestD
    for _, a in ipairs(list) do
      local d = (pos.x and a.x) and Dist(pos.x, pos.y, a.x, a.y) or 0.15
      if a.kind ~= "obj" then d = d * 0.8 end
      if not bestD or d < bestD then best, bestD = a, d end
    end
    s.minutes = s.minutes + MoveMinutes(s.level, bestD or 0)
    if best.x then pos.x, pos.y = best.x, best.y end
    Execute(s, best, steps, area)
  end
end

---------------------------------------------------------------------------
-- Build the whole route
---------------------------------------------------------------------------
function DR.BuildRoute(forceSolo)
  if not byArea then BuildIndex() end
  local me = DR.me
  local partner = (not forceSolo) and DR.Sync and DR.Sync.Partner() or nil
  if partner and partner.offline then partner = nil end
  local s = NewSim(me, partner)
  local steps = {}
  local here
  if me.mapID then
    for area, z in pairs(DR.Z) do
      if DR.UiMapForArea(area) == me.mapID and not DR.IsDungeon(area) then here = area; break end
    end
  end
  local pos = { x = me.x and me.x * 100, y = me.y and me.y * 100 }
  local zonesVisited = 0
  local exclude = {}
  while s.level < 60 and #steps < MAX_STEPS and zonesVisited < 120 do
    local co, isMain = coroutine.running()
    if co and not isMain then coroutine.yield() end -- spread the work over frames
    local area = ChooseZone(s, here, exclude, pos)
    if not area then break end
    local travel
    if area ~= here then
      travel = { kind = "travel", area = area, text = "Travel to " .. DR.ZoneName(area), t = s.minutes }
      steps[#steps + 1] = travel
    end
    local travelMin = travel and ZoneTravel(s, here, pos, area) or 0
    local before = #steps
    local fpStep
    local arrivePos = area == here and pos or {}
    if travel then
      -- pick up the flight path when you arrive somewhere new
      local f = DR.Travel.ZoneFlightMaster(area, s.ctx.faction)
      if f and not s.known[f[1]] and DR.Travel.Scanned() then
        fpStep = { kind = "fp", id = f[1], area = area, x = f[3], y = f[4], t = s.minutes + travelMin,
          text = "Get the flight path at " .. DR.Travel.Place(f), who = f[6] }
        steps[#steps + 1] = fpStep
        before = #steps
        arrivePos = { x = f[3], y = f[4] }
      end
    end
    RunZone(s, area, steps, arrivePos)
    zonesVisited = zonesVisited + 1
    if #steps == before then
      -- nothing doable there after all: undo the trip and don't pick it again this round
      if fpStep then steps[#steps] = nil end
      if travel then steps[#steps] = nil end
      exclude[area] = true
    else
      if fpStep then s.known[fpStep.id] = true; s.knownCount = s.knownCount + 1; s.minutes = s.minutes + 0.5 end
      if travel then s.minutes = s.minutes + travelMin; s.travelMinutes = (s.travelMinutes or 0) + travelMin; pos = {} end
      here = area
      exclude = {}
      local last = steps[#steps]
      if last and last.x then pos = { x = last.x, y = last.y } end
    end
  end
  -- drop level markers that aren't needed for display, keep their timing
  local final, levels = {}, {}
  for _, st in ipairs(steps) do
    if st.kind == "level" then levels[st.level] = st.minutes else final[#final + 1] = st end
  end
  return { steps = final, levels = levels, endLevel = s.level, endXP = s.xp, minutes = s.minutes,
    duo = partner ~= nil, built = time(), travelMinutes = s.travelMinutes or 0 }
end

---------------------------------------------------------------------------
-- Estimates to 60
---------------------------------------------------------------------------
function DR.XPTo60(level, xp)
  if not level or level >= 60 then return 0 end
  local total = -(xp or 0)
  for l = level, 59 do total = total + XP_TO_LEVEL[l] end
  return math.max(0, total)
end

-- Your measured overall XP/hour while actively levelling (nil until there's enough data)
function DR.MeasuredRate()
  local stats = DuoRouteChar and DuoRouteChar.zoneStats
  if not stats then return nil end
  local xp, secs = 0, 0
  for _, s in pairs(stats) do xp = xp + s.xp; secs = secs + s.secs end
  if secs < 1800 then return nil end
  return xp / secs * 3600
end

-- Hours left on a route, plus hours at your measured pace if known
function DR.RouteNow(route)
  local st = route.steps[route.cursor or 1]
  return st and st.t or route.minutes
end

function DR.RouteHours(route)
  if not route then return nil end
  return math.max(0, route.minutes - DR.RouteNow(route)) / 60
end

function DR.PaceHours()
  local rate = DR.MeasuredRate()
  if not rate or rate <= 0 then return nil end
  return DR.XPTo60(DR.me.level, DR.me.xp) / rate
end

---------------------------------------------------------------------------
-- Live tracking against the real game
---------------------------------------------------------------------------
local trained = {}

local function ObjectiveFinished(id, idx, label)
  local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
  if not ok or type(objs) ~= "table" then return false end
  local name = label:gsub("^Kill ", ""):gsub("^Collect ", ""):gsub("^Use ", ""):lower()
  for _, o in ipairs(objs) do
    if o.text and o.text:lower():find(name, 1, true) then return o.finished end
  end
  local o = objs[idx]
  return o and o.finished or false
end

function DR.StepDone(st)
  local me = DR.me
  if st.skipped then return true end
  if st.kind == "accept" then
    return me.active[st.id] or me.completed[st.id] or false
  elseif st.kind == "obj" then
    if me.completed[st.id] or me.activeDone[st.id] then return true end
    if not me.active[st.id] then return false end
    local o = DR.Q[st.id][F.OBJ][st.idx]
    return ObjectiveFinished(st.id, st.idx, o[4])
  elseif st.kind == "work" then
    return me.completed[st.id] or me.activeDone[st.id] or false
  elseif st.kind == "turnin" then
    return me.completed[st.id] or false
  elseif st.kind == "travel" then
    local u = DR.UiMapForArea(st.area)
    return u ~= nil and u == me.mapID
  elseif st.kind == "fp" then
    return (DuoRouteChar.fp and DuoRouteChar.fp[st.id]) or false
  elseif st.kind == "train" then
    return trained[st.level] or (me.level or 0) > st.level + 1
  end
  return false
end

function DR.MarkTrained() trained[DR.me.level or 0] = true; trained[(DR.me.level or 0) - 1] = true end

-- Advance the cursor; never goes backwards, and a later finished step implies earlier ones
function DR.AdvanceRoute(route)
  if not route then return end
  route.cursor = route.cursor or 1
  local steps = route.steps
  local i = route.cursor
  while i <= #steps and DR.StepDone(steps[i]) do i = i + 1 end
  -- look a few steps ahead: if something later is already done, jump past it
  for j = i + 1, math.min(#steps, i + 6) do
    local st = steps[j]
    if st.kind ~= "travel" and st.kind ~= "train" and DR.StepDone(st) and (st.kind == "turnin" or st.kind == "accept") then
      local allPrev = true
      for k = i, j - 1 do if steps[k].kind == "obj" and steps[k].id ~= st.id then allPrev = false end end
      if allPrev then i = j + 1 end
    end
  end
  route.cursor = i
  return steps[i]
end

function DR.StepText(st)
  if not st then return "" end
  if st.kind == "obj" or st.kind == "work" then
    return string.format("%s  |cffaaaaaa(%s)|r", st.text, st.quest or "")
  elseif (st.kind == "accept" or st.kind == "turnin") and st.who and st.who ~= "" then
    return string.format("%s  |cffaaaaaa%s %s|r%s", st.text, st.kind == "accept" and "from" or "at", st.who,
      st.youOnly and "  |cffffd100(you only)|r" or "")
  end
  return st.text or ""
end
