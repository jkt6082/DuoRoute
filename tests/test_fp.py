import os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'test_addon.py')).read().split("print('\\nTop zones")[0])
A.eval('RunTimers')(400)
A.execute('''
local DR = DuoRoute
local function count(r) local n = 0 for _, st in ipairs(r.steps) do if st.kind == "fp" then n = n + 1 end end return n end
local k = 0 for _ in pairs(DR.Travel.KnownSet(DR.me)) do k = k + 1 end
print("before scan: known", k, "fp steps", count(DR.Guide.Route()))
-- simulate a flight master map: Gadgetzan (Bulkrek) reachable, Tarren Mill (Zarise) unreachable
local function node(area, x, y, state)
  local cid, wx, wy = DR.Travel.World(area, x, y)
  -- turn world back into taxi-map coords for the mock (taxi map = 1414/1415 not modelled: use the zone map)
  return { position = CreateVector2D(x / 100, y / 100), state = state, _map = DR.UiMapForArea(area) }
end
local gz = node(440, 51.6, 25.4, 1)
GetTaxiMapID = function() return DR.UiMapForArea(440) end
TAXI_NODES = { gz }
NPCNAME = "Bulkrek Ragefist"
DuoRouteChar.fp = { [2389] = true }   -- pretend Zarise was wrongly marked known
FireEvent("TAXIMAP_OPENED")
RunTimers(400)
local known = {}
for id, v in pairs(DuoRouteChar.fp) do known[#known+1] = id .. "=" .. tostring(v) end
print("after scan:", table.concat(known, " "), "scanned", DR.Travel.Scanned())
print("fp steps after scan:", count(DR.Guide.Route()))
''')
