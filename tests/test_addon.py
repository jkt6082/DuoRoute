import lupa, json, random
random.seed(4)
import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, 'DuoRoute') + os.sep
data = json.load(open(os.path.join(ROOT, 'build', 'forever.json')))
Q = data['q']
def horde_ok(r, race_bit):
    ra = r['ra']
    if ra: return (ra // race_bit) % 2 == 1
    return r.get('ff') != 'A'
def completed_for(race_bit, maxlvl, frac):
    return [int(k) for k, r in Q.items() if horde_ok(r, race_bit) and r['c'] == 0 and r['l'] <= maxlvl and random.random() < frac]

def make(name, partner, raceID, classID, level, completed, log, done, mapID, x, y):
    L = lupa.LuaRuntime()
    L.execute(open(os.path.join(ROOT, 'tests', 'mockwow.lua')).read())
    me = L.eval('function(t) ME = t end')
    tbl = L.table_from({'name': name, 'partner': partner, 'level': level, 'raceID': raceID, 'classID': classID,
        'faction': 'Horde', 'completed': L.table_from(completed), 'log': L.table_from(log), 'done': L.table_from(done),
        'mapID': mapID, 'x': x, 'y': y, 'xp': 50000, 'xpMax': 125000})
    me(tbl)
    L.execute(open(ADDON + 'Data.lua', encoding='utf-8').read())
    ns = L.eval('{}')
    for f in ['Core.lua', 'Engine.lua', 'Sync.lua', 'Travel.lua', 'Route.lua', 'Guide.lua', 'Arrow.lua', 'UI.lua']:
        L.eval('function(src, name, ns) return load(src, "@"..name)("DuoRoute", ns) end')(open(ADDON + f, encoding='utf-8').read(), f, ns)
    L.eval('FireEvent')('PLAYER_LOGIN')
    L.eval('RunTimers')(3)
    return L, ns

# Joel: Troll (8) warlock (9) lvl 49 in Tanaris (uiMap 1446); partner Tauren (6) paladin (2) lvl 48
cA = completed_for(128, 44, 0.55)
cB = [q for q in cA if random.random() < 0.85] + completed_for(32, 44, 0.15)
logA = [7842, 2864, 3520]   # Another Message to the Wildhammer + some
A, nsA = make('Joel', 'Puget', 8, 9, 49, cA, logA, [7842], 1446, 0.51, 0.27)
B, nsB = make('Puget', 'Joel', 6, 2, 48, cB, [7842], [], 1446, 0.52, 0.28)

def pump():
    moved = True; rounds = 0
    while moved and rounds < 6:
        moved = False; rounds += 1
        for src, dst, name in ((A, B, 'Joel-Realm'), (B, A, 'Puget-Realm')):
            src.eval('RunTimers')(60)
            sent = src.eval('SENT')
            msgs = [sent[i] for i in range(1, len(sent) + 1)]
            src.execute('SENT = {}')
            for m in msgs:
                dst.eval('FireEvent')('CHAT_MSG_ADDON', m[1], m[2], m[3], name)
                moved = True
    return rounds

for L in (A, B): L.eval('function() FireEvent("GROUP_ROSTER_UPDATE") end')()
r = pump()
print('sync rounds', r)
p = nsA.Sync.Partner()
print('A sees partner', p and p.name, p and p.level, 'completed', p and len(list(p.completed.keys())), 'of', len(cB), 'active', p and list(p.active.keys()))

plan = nsA.Plan()
print('\nTop zones for the duo:')
zones = plan.zones
for i in range(1, 9):
    z = zones[i]
    if z is None: break
    print(f"{i}. {nsA.ZoneName(z.area):28s} score {z.score:9.0f}  ~{z.levels:.2f} lvls  both {z.both:3d}  inlog {z.inlog}  pickups {z.pickups}  share {z.share}")
print('\nDungeons:')
for i in range(1, 6):
    z = plan.dungeons[i]
    if z is None: break
    print(f"  {nsA.ZoneName(z.area):24s} quests {len(list(z.entries.keys()))} both {z.both} xp {z.value:.0f}")
z = zones[1]
ents = nsA.SortEntries(z.entries)
print('\nQuests in', nsA.ZoneName(z.area))
for i in range(1, 16):
    e = ents[i]
    if e is None: break
    q = e.q
    print(f"  [{q[2]}] {q[1][:38]:38s} {e.tag:8s} s1={e.s1:6s} s2={str(e.s2):6s} xp={e.xp} starter={q[16]} share={e.share}")
nx = nsA.NextStep(plan)
print('\nNext step:', nx and (nx.verb, nx.e.q[1], nx.x, nx.y))
# UI build + refresh shouldn't error
A.eval('function() DuoRoute.UI.Toggle() end')()
print('UI ok, status:', A.eval('DuoRoute') and 'built')
# Turn-in learning
A.eval('function() ME.completed[#ME.completed+1]=7842; FireEvent("QUEST_TURNED_IN", 7842, 5800, 0) end')()
pump()
print('B sees 7842 done for partner:', nsB.Sync.Partner().completed[7842])
print('calib n', A.eval('DuoRouteChar.calib.n'))
print('\nOrgrimmar entries:')
for z in [plan.zones[i] for i in range(1, 9)]:
    if nsA.ZoneName(z.area) in ('Orgrimmar', 'Undercity'):
        ents = nsA.SortEntries(z.entries)
        for i in range(1, 25):
            e = ents[i]
            if e is None: break
            q = e.q
            print(f"  {nsA.ZoneName(z.area)[:4]} [{q[2]}/{q[3]}] {q[1][:40]:40s} xp={e.xp} starter={q[16]} id={e.id} flags={q[11]} pres={q[8] and list(q[8].values())}")
