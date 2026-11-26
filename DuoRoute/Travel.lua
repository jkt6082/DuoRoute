-- DuoRoute: fastest way to get somewhere, using your flight paths, boats, zeppelins and hearthstone
local ADDON, DR = ...
local Travel = {}
DR.Travel = Travel

local simCache = {}
local FM = DR.D.FM or {}

-- Town each flight master stands in (new Forever ones are learned from the flight map's own names)
local TOWN = {
  [2861] = "Kargath", [8609] = "Nethergarde Keep", [6026] = "Stonard", [2409] = "Darkshire",
  [1571] = "Menethil Harbor", [4321] = "Theramore", [11899] = "Brackenwall Village", [8610] = "Valormok",
  [12577] = "Talrendis Point", [3615] = "The Crossroads", [10378] = "Camp Taurajo", [16227] = "Ratchet",
  [12596] = "Chillwind Camp", [1387] = "Grom'gol", [2858] = "Booty Bay", [2859] = "Booty Bay",
  [1572] = "Thelsamar", [523] = "Sentinel Hill", [931] = "Lakeshire", [2835] = "Refuge Pointe",
  [2851] = "Hammerfall", [2299] = "Morgan's Vigil", [13177] = "Flame Crest", [4314] = "Revantusk Village",
  [8018] = "Aerie Peak", [2941] = "Thorium Point", [3305] = "Thorium Point", [2226] = "The Sepulcher",
  [12617] = "Light's Hope Chapel", [12636] = "Light's Hope Chapel", [3838] = "Rut'theran Village",
  [3841] = "Auberdine", [2389] = "Tarren Mill", [2432] = "Southshore", [4267] = "Astranaar",
  [11901] = "Zoram'gar Outpost", [12616] = "Splintertree Post", [4319] = "Thalanaar",
  [8019] = "Feathermoon Stronghold", [8020] = "Camp Mojache", [11900] = "Bloodvenom Post",
  [12578] = "Talonbranch Glade", [4317] = "Freewind Post", [6706] = "Nijel's Point",
  [6726] = "Shadowprey Village", [4312] = "Sun Rock Retreat", [4407] = "Stonetalon Peak",
  [7823] = "Gadgetzan", [7824] = "Gadgetzan", [10583] = "Marshal's Refuge", [10897] = "Nighthaven",
  [12740] = "Nighthaven", [11138] = "Everlook", [11139] = "Everlook", [15177] = "Cenarion Hold",
  [15178] = "Cenarion Hold", [4551] = "Undercity", [352] = "Stormwind", [1573] = "Ironforge",
  [3310] = "Orgrimmar", [2995] = "Thunder Bluff",
}
-- druid-only flight masters in Moonglade: never route through them
local DRUID_ONLY = { [11798] = true, [11800] = true }

function Travel.Town(f)
  local learned = DuoRouteDB and DuoRouteDB.fpNode and DuoRouteDB.fpNode[f[1]]
  if learned and learned.name then return (learned.name:match("^([^,]+)")) end
  return TOWN[f[1]] or (DR.ZoneName(f[2]) .. " flight point")
end

-- "Camp Mojache, Feralas"
function Travel.Place(f)
  local town, zone = Travel.Town(f), DR.ZoneName(f[2])
  if town == zone or town:find(zone, 1, true) then return town end
  return town .. ", " .. zone
end   -- { npcID, area, x, y, faction, name }
local TR = DR.D.TR or {}   -- { fromArea, x, y, toArea, x, y, faction, kind }

local HEARTHSTONE = 6948
local HEARTH_SPELL = 8690
local FLY_SPEED = 32      -- yards/second, taxi
local FLY_DETOUR = 1.25   -- taxi routes aren't straight lines
local TRANSPORT_MIN = 4.5 -- average wait plus crossing
local TERRAIN = 1.3       -- roads and hills make ground travel longer than a straight line

---------------------------------------------------------------------------
-- World coordinates (yards) so distances work across zones
---------------------------------------------------------------------------
local worldCache = {}
function Travel.World(area, x, y)
  if not area or not x then return nil end
  local key = area .. ":" .. math.floor(x * 10) .. ":" .. math.floor(y * 10)
  local c = worldCache[key]
  if c ~= nil then
    if c then return c[1], c[2], c[3] end
    return nil
  end
  local uiMap = DR.UiMapForArea(area)
  local cont, wx, wy
  if uiMap and C_Map.GetWorldPosFromMapPos then
    local ok, cid, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMap, CreateVector2D(x / 100, y / 100))
    if ok and cid and pos then cont = cid; wx, wy = pos:GetXY() end
  end
  worldCache[key] = cont and { cont, wx, wy } or false
  return cont, wx, wy
end

function Travel.PlayerWorld()
  local me = DR.me
  if not me.mapID or not me.x then return nil end
  local ok, cid, pos = pcall(C_Map.GetWorldPosFromMapPos, me.mapID, CreateVector2D(me.x, me.y))
  if ok and cid and pos then
    local wx, wy = pos:GetXY()
    return cid, wx, wy
  end
end

local function FactionOK(f, faction)
  return f == "AH" or f == "" or (faction and f:find(faction, 1, true) ~= nil)
end

function Travel.ZoneFlightMaster(area, faction)
  for _, f in ipairs(FM) do
    if f[2] == area and FactionOK(f[5], faction) and not DRUID_ONLY[f[1]] then return f end
  end
end

---------------------------------------------------------------------------
-- Known flight paths
---------------------------------------------------------------------------
-- Only flight paths the game has confirmed (from a flight master's map) count.
-- Explicit false means "you told us / the map showed you don't have it".
function Travel.KnownSet(ctx)
  local known = {}
  local c = DuoRouteChar
  for id, v in pairs((c and c.fp) or {}) do if v == true then known[id] = true end end
  return known
end

function Travel.Scanned() return DuoRouteChar and DuoRouteChar.fpScanned end

function Travel.Forget(id)
  DuoRouteChar.fp = DuoRouteChar.fp or {}
  DuoRouteChar.fp[id] = false
  simCache = {}
end

local function LearnFromTaxiMap()
  local c = DuoRouteChar
  c.fp = c.fp or {}
  -- the flight master you're talking to
  local npc = UnitName("npc")
  for _, f in ipairs(FM) do
    if npc and f[6] == npc then c.fp[f[1]] = true end
  end
  -- every node the map says you can reach
  local mapID = GetTaxiMapID and GetTaxiMapID()
  local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
  if not ok or type(nodes) ~= "table" then return end
  local unreachable = Enum.FlightPathState and Enum.FlightPathState.Unreachable
  -- which continent is this map? clear what we thought we knew there, then fill from the map
  local mapCont
  for _, node in ipairs(nodes) do
    if node.position then
      local okc, cid = pcall(C_Map.GetWorldPosFromMapPos, mapID, node.position)
      if okc and cid then mapCont = cid; break end
    end
  end
  if mapCont then
    for _, f in ipairs(FM) do
      local fc = Travel.World(f[2], f[3], f[4])
      if fc == mapCont and c.fp[f[1]] == true then c.fp[f[1]] = nil end
    end
  end
  if npc then for _, f in ipairs(FM) do if f[6] == npc then c.fp[f[1]] = true end end end
  for _, node in ipairs(nodes) do
    if node.position then
      local ok2, cid, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, node.position)
      if ok2 and cid and pos then
        local nx, ny = pos:GetXY()
        local best, bestD
        for _, f in ipairs(FM) do
          local fc, fx, fy = Travel.World(f[2], f[3], f[4])
          if fc == cid then
            local d = (fx - nx) ^ 2 + (fy - ny) ^ 2
            if not bestD or d < bestD then best, bestD = f, d end
          end
        end
        if best and bestD < 250 * 250 then
          if node.state ~= unreachable then c.fp[best[1]] = true end
          DuoRouteDB.fpNode = DuoRouteDB.fpNode or {}
          DuoRouteDB.fpNode[best[1]] = { id = node.nodeID, name = node.name }
        end
      end
    end
  end
  c.fpScanned = true
  DR.Debug("flight paths learned")
end

---------------------------------------------------------------------------
-- Hearthstone
---------------------------------------------------------------------------
local function RecordHearth()
  local me = DR.me
  DR.RefreshMe(false)
  if me.mapID and me.x then
    DuoRouteChar.hearth = { uiMap = me.mapID, x = me.x * 100, y = me.y * 100, name = GetBindLocation and GetBindLocation() }
  end
end

function Travel.HearthReady()
  if not DuoRouteChar or not DuoRouteChar.hearth then return false end
  local getCD = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  if not getCD then return false end
  local ok, start, dur = pcall(getCD, HEARTHSTONE)
  if not ok then return false end
  return (start or 0) == 0 or (start + dur - GetTime()) < 30
end

local function HearthNode()
  local h = DuoRouteChar and DuoRouteChar.hearth
  if not h then return nil end
  local ok, cid, pos = pcall(C_Map.GetWorldPosFromMapPos, h.uiMap, CreateVector2D(h.x / 100, h.y / 100))
  if not ok or not cid then return nil end
  local wx, wy = pos:GetXY()
  local area
  for a in pairs(DR.Z) do if DR.UiMapForArea(a) == h.uiMap and not DR.IsDungeon(a) then area = a; break end end
  return { cont = cid, x = wx, y = wy, area = area, zx = h.x, zy = h.y, name = h.name }
end

---------------------------------------------------------------------------
-- Fastest path (Dijkstra over a small graph)
---------------------------------------------------------------------------
local function GroundSpeed(level) return (level or 1) >= 40 and 11.2 or 7 end

local function Dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- opts: { known = set of flight master ids, level, faction, hearth = bool }
function Travel.Path(fromNode, toNode, opts)
  if not fromNode or not toNode then return nil end
  local nodes = { fromNode, toNode }
  local edges = {}   -- [i] = { {j, minutes, kind, label}, ... }
  local function add(n) nodes[#nodes + 1] = n; return #nodes end
  local fpIndex = {}
  for _, f in ipairs(FM) do
    if opts.known[f[1]] and not DRUID_ONLY[f[1]] then
      local c, x, y = Travel.World(f[2], f[3], f[4])
      if c then fpIndex[#fpIndex + 1] = add({ cont = c, x = x, y = y, area = f[2], zx = f[3], zy = f[4], fm = f }) end
    end
  end
  local trPairs = {}
  for _, t in ipairs(TR) do
    if FactionOK(t[7], opts.faction) then
      local c1, x1, y1 = Travel.World(t[1], t[2], t[3])
      local c2, x2, y2 = Travel.World(t[4], t[5], t[6])
      if c1 and c2 then
        local a = add({ cont = c1, x = x1, y = y1, area = t[1], zx = t[2], zy = t[3], dock = t })
        local b = add({ cont = c2, x = x2, y = y2, area = t[4], zx = t[5], zy = t[6], dock = t })
        trPairs[#trPairs + 1] = { a, b, t }
      end
    end
  end
  local hearthIdx
  if opts.hearth then
    local h = HearthNode()
    if h then hearthIdx = add(h) end
  end

  local n = #nodes
  for i = 1, n do edges[i] = {} end
  local ground = GroundSpeed(opts.level)
  for i = 1, n do
    for j = 1, n do
      if i ~= j and nodes[i].cont == nodes[j].cont and j ~= 1 then
        local m = Dist(nodes[i], nodes[j]) * TERRAIN / ground / 60
        edges[i][#edges[i] + 1] = { j, m, "walk" }
      end
    end
  end
  for a = 1, #fpIndex do
    for b = 1, #fpIndex do
      local i, j = fpIndex[a], fpIndex[b]
      if i ~= j and nodes[i].cont == nodes[j].cont then
        edges[i][#edges[i] + 1] = { j, Dist(nodes[i], nodes[j]) * FLY_DETOUR / FLY_SPEED / 60 + 0.4, "fly" }
      end
    end
  end
  for _, p in ipairs(trPairs) do
    edges[p[1]][#edges[p[1]] + 1] = { p[2], TRANSPORT_MIN, p[3][8] }
    edges[p[2]][#edges[p[2]] + 1] = { p[1], TRANSPORT_MIN, p[3][8] }
  end
  if hearthIdx then edges[1][#edges[1] + 1] = { hearthIdx, 0.4, "hearth" } end

  -- Dijkstra
  local dist, prev, via, done = {}, {}, {}, {}
  for i = 1, n do dist[i] = math.huge end
  dist[1] = 0
  for _ = 1, n do
    local u, best = nil, math.huge
    for i = 1, n do if not done[i] and dist[i] < best then u, best = i, dist[i] end end
    if not u or u == 2 then break end
    done[u] = true
    for _, e in ipairs(edges[u]) do
      local v, w = e[1], e[2]
      if dist[u] + w < dist[v] then dist[v] = dist[u] + w; prev[v] = u; via[v] = e[3] end
    end
  end
  if dist[2] == math.huge then return nil end

  -- walk back into legs, merging consecutive legs of the same kind
  local chain = {}
  local v = 2
  while v ~= 1 do table.insert(chain, 1, { node = nodes[v], kind = via[v], from = nodes[prev[v]] }); v = prev[v] end
  local legs = {}
  for _, c in ipairs(chain) do
    local last = legs[#legs]
    if last and last.kind == c.kind and c.kind == "walk" then
      last.to = c.node
    else
      legs[#legs + 1] = { kind = c.kind, from = c.from, to = c.node }
    end
  end
  -- drop walking legs of a few yards (you're already standing there)
  for i = #legs, 1, -1 do
    local l = legs[i]
    if l.kind == "walk" and #legs > 1 and Dist(l.from, l.to) < 40 then table.remove(legs, i) end
  end
  for _, l in ipairs(legs) do
    if l.kind == "walk" then l.minutes = Dist(l.from, l.to) * TERRAIN / ground / 60
    elseif l.kind == "fly" then l.minutes = Dist(l.from, l.to) * FLY_DETOUR / FLY_SPEED / 60 + 0.4
    elseif l.kind == "hearth" then l.minutes = 0.4
    else l.minutes = TRANSPORT_MIN end
  end
  return legs, dist[2]
end

---------------------------------------------------------------------------
-- Text for a leg
---------------------------------------------------------------------------
local function Where(node)
  if node.fm then return "the flight master in " .. Travel.Place(node.fm) end
  if node.dock then
    local t = node.dock
    local other = (node.area == t[1]) and t[4] or t[1]
    return string.format("the %s to %s (%s)", t[8], DR.ZoneName(other), DR.ZoneName(node.area))
  end
  return nil
end

function Travel.LegText(leg, goalText)
  local dest = leg.to
  if leg.kind == "walk" then
    local w = Where(dest)
    if w then return (DR.me.level or 1) >= 40 and ("Ride to " .. w) or ("Run to " .. w) end
    return goalText or ("Head to " .. DR.ZoneName(dest.area))
  elseif leg.kind == "fly" then
    return "Fly to " .. Travel.Place(dest.fm)
  elseif leg.kind == "hearth" then
    return "Use your Hearthstone" .. (dest.name and (" to " .. dest.name) or "")
  else
    return string.format("Take the %s to %s", leg.kind, DR.ZoneName(dest.area))
  end
end

---------------------------------------------------------------------------
-- Helpers for the route simulator and the guide
---------------------------------------------------------------------------
function Travel.Node(area, x, y)
  local c, wx, wy = Travel.World(area, x, y)
  if not c then return nil end
  return { cont = c, x = wx, y = wy, area = area, zx = x, zy = y }
end

-- Where to aim for in a zone: its flight master if you're allowed to use it, else the middle
function Travel.Anchor(area, faction)
  local f = Travel.ZoneFlightMaster(area, faction)
  if f then return f[3], f[4] end
  return 50, 50
end

-- Minutes between two spots for the simulator (cached per known-set size)
function Travel.SimMinutes(fromArea, fx, fy, toArea, tx, ty, known, knownCount, level, faction)
  if not fromArea then return 8 end
  local key = table.concat({ fromArea, math.floor((fx or 50) / 10), math.floor((fy or 50) / 10), toArea, knownCount, level >= 40 and 1 or 0 }, ":")
  local c = simCache[key]
  if c then return c end
  local a = Travel.Node(fromArea, fx or 50, fy or 50)
  local b = Travel.Node(toArea, tx or 50, ty or 50)
  local m
  if a and b then
    local _, total = Travel.Path(a, b, { known = known, level = level, faction = faction })
    m = total
  end
  m = m or 8
  simCache[key] = m
  return m
end

function Travel.ResetCache() simCache = {} end

-- Directions from where you stand to a spot: list of legs, or nil when you're already close
function Travel.Directions(area, x, y)
  local cid, wx, wy = Travel.PlayerWorld()
  if not cid then return nil end
  local goal = Travel.Node(area, x or 50, y or 50)
  if not goal then return nil end
  local me = DR.me
  local legs = Travel.Path({ cont = cid, x = wx, y = wy }, goal,
    { known = Travel.KnownSet(me), level = me.level, faction = me.faction, hearth = Travel.HearthReady() })
  return legs
end

---------------------------------------------------------------------------
-- Flight map: mark the flight point to pick
---------------------------------------------------------------------------
local PATH = "Interface\\AddOns\\" .. ADDON .. "\\"
local marker

local function Marker()
  if marker then return marker end
  marker = CreateFrame("Frame", nil, UIParent)
  marker:SetSize(44, 44)
  local ring = marker:CreateTexture(nil, "OVERLAY")
  ring:SetAllPoints(); ring:SetTexture(PATH .. "ring.tga")
  local arrow = marker:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(30, 30); arrow:SetPoint("BOTTOM", marker, "TOP", 0, -6)
  arrow:SetTexture(PATH .. "arrow.tga"); arrow:SetRotation(math.pi)
  local text = marker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  text:SetPoint("BOTTOM", arrow, "TOP", 0, 0)
  marker.text = text
  local pulse = marker:CreateAnimationGroup()
  pulse:SetLooping("BOUNCE")
  local a = pulse:CreateAnimation("Alpha")
  a:SetFromAlpha(1); a:SetToAlpha(0.45); a:SetDuration(0.5)
  marker.pulse = pulse
  marker:Hide()
  return marker
end

local function HideMarker()
  if marker then marker:Hide(); marker.pulse:Stop(); marker:SetParent(UIParent) end
end

-- Find the button/pin for a flight master's node on whichever flight map is open
local function FindNode(dest)
  local want = DuoRouteDB.fpNode and DuoRouteDB.fpNode[dest[1]]
  local town = Travel.Town(dest)
  local function match(id, name)
    if want and want.id and id == want.id then return true end
    if want and want.name and name == want.name then return true end
    return name and town and name:find(town, 1, true) ~= nil
  end
  if FlightMapFrame and FlightMapFrame:IsShown() and FlightMapFrame.EnumeratePinsByTemplate then
    for pin in FlightMapFrame:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
      local d = pin.taxiNodeData
      if d and match(d.nodeID, d.name) then return pin end
    end
  end
  if TaxiFrame and TaxiFrame:IsShown() and NumTaxiNodes then
    for i = 1, NumTaxiNodes() do
      if match(nil, TaxiNodeName(i)) then return _G["TaxiButton" .. i] end
    end
  end
end

function Travel.MarkFlight()
  HideMarker()
  local st = DR.Guide and DR.Guide.CurrentStep and DR.Guide.CurrentStep()
  local legs = st and DR.Guide.Directions(st)
  if not legs then return end
  local dest
  for _, l in ipairs(legs) do
    if l.kind == "fly" then dest = l.to.fm; break end
    if l.kind ~= "walk" then break end
  end
  if not dest then return end
  DR.Msg("Fly to |cff66ff66" .. Travel.Place(dest) .. "|r")
  local tries = 0
  local function place()
    tries = tries + 1
    local node = FindNode(dest)
    if node then
      local m = Marker()
      m:SetParent(node)
      m:SetFrameLevel(node:GetFrameLevel() + 10)
      m:ClearAllPoints(); m:SetPoint("CENTER", node, "CENTER")
      m.text:SetText(Travel.Town(dest))
      m:Show(); m.pulse:Play()
    elseif tries < 10 then
      C_Timer.After(0.15, place) -- the map's buttons appear a moment after it opens
    end
  end
  place()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("TAXIMAP_OPENED")
ev:RegisterEvent("TAXIMAP_CLOSED")
ev:RegisterEvent("HEARTHSTONE_BOUND")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:SetScript("OnEvent", function(_, event, _, _, spellID)
  if not DuoRouteChar then return end
  if event == "TAXIMAP_OPENED" then
    local before = {}
    for id, v in pairs(DuoRouteChar.fp or {}) do if v == true then before[id] = true end end
    LearnFromTaxiMap()
    Travel.ResetCache()
    -- replan only if what we know actually changed
    local changed = false
    for id, v in pairs(DuoRouteChar.fp or {}) do if (v == true) ~= (before[id] == true) then changed = true end end
    for id in pairs(before) do if DuoRouteChar.fp[id] ~= true then changed = true end end
    C_Timer.After(0.1, Travel.MarkFlight)
    if changed then
      local n = 0
      for _, v in pairs(DuoRouteChar.fp) do if v == true then n = n + 1 end end
      DR.Msg("Learned your flight paths (" .. n .. " known). Updating your route.")
      if DR.Guide then DR.Guide.Rebuild("flight paths") end
    elseif DR.Guide then DR.Guide.Refresh() end
  elseif event == "TAXIMAP_CLOSED" then
    HideMarker()
  elseif event == "HEARTHSTONE_BOUND" then
    RecordHearth()
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" and spellID == HEARTH_SPELL then
    C_Timer.After(12, RecordHearth) -- you arrive at your inn: that's where the hearth goes
  end
end)
