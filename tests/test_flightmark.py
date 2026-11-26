import os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'test_addon.py')).read().split("print('\\nTop zones")[0])
A.eval('RunTimers')(400)
A.execute('''
local DR = DuoRoute
-- player stands at the Gadgetzan flight master; knows Gadgetzan + Camp Mojache
ME.mapID = DR.UiMapForArea(440); ME.x, ME.y = 0.516, 0.254
DuoRouteChar.fp = { [7824] = true, [8020] = true }
DuoRouteChar.fpScanned = true
DR.RefreshMe(false)
-- point the guide at a Feralas travel step
local r = DR.Guide.Route()
for i, st in ipairs(r.steps) do if st.kind == "travel" and st.area == 357 then r.cursor = i; break end end
print("current step:", DR.Guide.CurrentStep().text)
local legs = DR.Guide.Directions(DR.Guide.CurrentStep())
for _, l in ipairs(legs or {}) do print("  leg:", DR.Travel.LegText(l)) end
-- fake classic taxi frame with 3 nodes
TaxiFrame = CreateFrame("Frame"); TaxiFrame:Show()
local names = { "Gadgetzan, Tanaris", "Camp Mojache, Feralas", "Orgrimmar, Durotar" }
function NumTaxiNodes() return #names end
function TaxiNodeName(i) return names[i] end
for i = 1, 3 do _G["TaxiButton" .. i] = CreateFrame("Button"); _G["TaxiButton" .. i].name = names[i] end
TAXI_NODES = {}
FireEvent("TAXIMAP_OPENED")
RunTimers(20)
-- which button got the marker?
for _, f in ipairs(FRAMES) do
  local p = rawget(f, "parent"); if p and rawget(p, "name") and rawget(f, "shown") then print("marker on:", p.name) end
end
''')
