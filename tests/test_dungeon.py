import os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'test_addon.py')).read().split("print('\\nTop zones")[0])
# put a dungeon quest in the log: Uldaman "Find the Gems" (2201) style and an Uldaman reagent run
A.execute('''
local n = 0
for id, t in pairs(DuoRoute_Data.TAG) do
  local q = DuoRoute_Data.Q[id]
  if t == 81 and q and q[2] >= 40 and q[2] <= 50 and (q[4] == 0 or q[4] == 8589934770) and n < 3 then
    ME.log[#ME.log+1] = id; n = n + 1; print("log has dungeon quest", id, q[1])
  end
end
''')
A.eval('RunTimers')(400)
A.execute('''
local DR = DuoRoute
DR.RefreshMe(true); DR.Guide.Rebuild("t")
''')
A.eval('RunTimers')(400)
A.execute('''
local DR = DuoRoute
for k, r in pairs(DR.Guide.Routes()) do
  local bad = 0
  for _, st in ipairs(r.steps) do
    if st.id and DR.IsInstanceQuest(st.id, DR.Q[st.id]) then bad = bad + 1; if bad < 4 then print("  instance step:", st.kind, DR.Q[st.id][1]) end end
  end
  print(k, "steps", #r.steps, "instance-quest steps", bad, string.format("%.1fh", r.minutes/60))
end

local plan = DR.Plan()
for i = 1, 5 do local z = plan.dungeons[i]; if z then print("dungeon tab:", DR.ZoneName(z.area), #z.entries) end end
''')
