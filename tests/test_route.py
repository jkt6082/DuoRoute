import os
import time
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'test_addon.py')).read().split("print('\\nTop zones")[0])
for label, ns, L in (('DUO', nsA, A),):
    t=time.time()
    r = ns.BuildRoute()
    print(label, 'built in %.2fs' % (time.time()-t), 'steps', len(list(r.steps.keys())), 'end level', r.endLevel, 'hours %.1f' % (r.minutes/60))
    lv = r.levels
    print('  level timeline (hours):', {k: round(v/60,1) for k,v in sorted(lv.items())})
    steps = r.steps
    for i in range(1, 46):
        st = steps[i]
        if st is None: break
        print(f"  {i:3d}. {st.kind:7s} {ns.StepText(st)[:85]}  @{ns.ZoneName(st.area) if st.area else ''} {st.x or ''},{st.y or ''}")
# solo, lower level char
S, nsS = make('Solo', None, 8, 9, 46, completed_for(128, 41, 0.6), [], [], 1446, 0.51, 0.28)
t=time.time(); r = nsS.BuildRoute()
print('SOLO 46 built in %.2fs' % (time.time()-t), 'steps', len(list(r.steps.keys())), 'end', r.endLevel, 'hours %.1f' % (r.minutes/60))
zones=[]
for i in range(1, len(list(r.steps.keys()))+1):
    st=r.steps[i]
    if st.kind=='travel': zones.append(nsS.ZoneName(st.area))
print('  zone order:', zones)
