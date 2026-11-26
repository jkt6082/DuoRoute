import os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'test_addon.py')).read().split("print('\\nTop zones")[0])
A.eval('RunTimers')(400)
A.execute('''
local DR = DuoRoute
ME.mapID = 1446; ME.x, ME.y = 0.5, 0.5
local function check(name, tx, ty, facing, expect)
  FACING = facing
  DR.Arrow.SetTarget(1446, tx, ty, name)
  DR.Arrow.Update()
  print(string.format("%-34s rot %6.2f  expected %6.2f", name, LASTROT or 0/0, expect))
end
check("facing north, target east", 0.6, 0.5, 0, -math.pi/2)
check("facing north, target north", 0.5, 0.4, 0, 0)
check("facing north, target west", 0.4, 0.5, 0, -3*math.pi/2)
check("facing east, target east", 0.6, 0.5, 3*math.pi/2, -2*math.pi)
check("facing south, target north", 0.5, 0.4, math.pi, -math.pi)
-- off-route turn-in triggers a replan
local r = DR.Guide.Route(); local before = r
FireEvent("QUEST_TURNED_IN", 2937, 8450, 0)
RunTimers(400)
print("replanned after off-route turn-in:", DR.Guide.Route() ~= before)
''')
