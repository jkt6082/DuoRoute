import os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'test_addon.py')).read().split("print('\\nTop zones")[0])
A.eval('RunTimers')(400)
A.execute('''
local DR = DuoRoute
local R = DR.Guide.Routes()
print("solo", R.solo and #R.solo.steps, R.solo and string.format("%.1fh", R.solo.minutes/60), "duo", R.duo and #R.duo.steps, R.duo and string.format("%.1fh", R.duo.minutes/60))
print("shown is duo:", DR.Guide.Route() == R.duo)
print("estimate:", DR.Guide.EstimateText())
local yo = 0 for _, st in ipairs(R.duo.steps) do if st.youOnly then yo = yo + 1 end end
print("you-only accepts in duo route:", yo)
DR.Guide.SetMode("solo"); print("after toggle shown is solo:", DR.Guide.Route() == R.solo)
-- add measured pace data
DuoRouteChar.zoneStats[1446] = { xp = 60000, secs = 3600 }
print("with pace:", DR.Guide.EstimateText())
DR.UI.Toggle()
for _, f in ipairs(FRAMES) do if f.text and tostring(f.text):find("To 60") then print("planner title:", f.text) end end
-- tooltip lines
for _, f in ipairs(FRAMES) do if f.scripts.OnEnter and f.scripts.OnLeave then end end
''')
