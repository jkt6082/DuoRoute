exec(open('test_addon.py').read().split("print('\\nTop zones")[0])
A.eval('function() DuoRoute.UI.Toggle() end')()
click = A.eval('''function(label)
  for _, f in ipairs(FRAMES) do if f.text == label and f.scripts.OnClick then f.scripts.OnClick(f, "LeftButton"); return true end end
  return false end''')
# simulate some XP learning
A.execute('''
for i=1,40 do NOW = NOW + 60; ME.xp = (ME.xp or 0) + 900; FireEvent("PLAYER_XP_UPDATE") 
  for _, f in ipairs(FRAMES) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 6) end end end
for i=1,6 do FireEvent("QUEST_TURNED_IN", 2864+i, 4200, 0) end
''')
for label in ['Dungeons', "What it's learned", 'Zones']:
    print(label, click(label))
    A.eval('RunTimers')(3)
learned = A.eval('''function() for _, f in ipairs(FRAMES) do end
  for _, f in ipairs(FRAMES) do end return true end''')()
# find learned text
txt = A.eval('''function() local out={} for _, f in ipairs(FRAMES) do end return 1 end''')()
# row click -> waypoint
A.execute('''
for _, f in ipairs(FRAMES) do if f.e and f.scripts.OnClick then f.scripts.OnClick(f, "LeftButton"); break end end
''')
wp = A.eval('LASTWP')
print('waypoint', wp and (wp.m, wp.x, wp.y))
A.eval('function() SlashCmdList.DUOROUTE("unhide"); SlashCmdList.DUOROUTE("bogus"); SlashCmdList.DUOROUTE("partner Puget") end')()
print('calib', A.eval('DuoRoute.Calibration()'), 'zoneStats', A.eval('(function() local n=0 for k,v in pairs(DuoRouteChar.zoneStats) do n=n+1; print("zone",k,v.xp,v.secs) end return n end)()'))
# solo runtime
S, nsS = make('Solo', None, 8, 9, 52, cA, [], [], 1449, 0.4, 0.4)
pl = nsS.Plan()
print('solo top:', [nsS.ZoneName(pl.zones[i].area) for i in range(1, 6)])
S.eval('function() DuoRoute.UI.Toggle() end')()
print('solo UI ok')
