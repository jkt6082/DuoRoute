import os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'test_addon.py')).read().split("print('\\nTop zones")[0])
A.eval('RunTimers')(400)
A.execute('''
local DR = DuoRoute
local R = DR.Guide.Routes()
print("duo", #R.duo.steps, string.format("%.1fh", R.duo.minutes/60), "solo", #R.solo.steps, string.format("%.1fh", R.solo.minutes/60))
local n = 0
for i, st in ipairs(R.duo.steps) do
  if st.kind == "fp" or st.kind == "travel" then
    n = n + 1
    if n <= 12 then print(i, st.kind, st.text) end
  end
end
-- simulate visiting a flight master (Gadgetzan) and learning paths
NPCNAME = "Bulkrek Ragefist"
FireEvent("TAXIMAP_OPENED")
local c = 0 for _ in pairs(DuoRouteChar.fp) do c = c + 1 end
print("learned fps", c, "scanned", DuoRouteChar.fpScanned)
-- teach a few known horde FPs
for _, f in ipairs(DR.D.FM) do if f[5]:find("H") and (f[2]==440 or f[2]==357 or f[2]==47 or f[2]==14 or f[2]==85) then DuoRouteChar.fp[f[1]] = true end end
DR.Travel.ResetCache()
-- directions from Tanaris (player) to the Hinterlands quest hub
local legs, total = DR.Travel.Directions(47, 79.4, 79.1)
print("legs to Hinterlands:", legs and #legs, total and string.format("%.1f min", total))
for _, l in ipairs(legs or {}) do print("  ", l.kind, DR.Travel.LegText(l), string.format("%.1f", l.minutes)) end
-- hearth
FireEvent("HEARTHSTONE_BOUND")
print("hearth", DuoRouteChar.hearth and DuoRouteChar.hearth.uiMap, DR.Travel.HearthReady())
-- guide view on a travel step
for i, st in ipairs(R.duo.steps) do if st.kind == "travel" and DR.UiMapForArea(st.area) ~= ME.mapID then R.duo.cursor = i; break end end
DR.Guide.Toggle(true); DR.Guide.Refresh()
print("waypoint ->", LASTWP and LASTWP.m, LASTWP and LASTWP.x)
''')
