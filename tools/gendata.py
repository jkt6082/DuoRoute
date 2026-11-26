import json, statistics, collections, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
d = json.load(open(os.path.join(ROOT, 'build', 'forever.json')))
Q, Z = d['q'], d['z']
# Unmapped zones without a UiMap are instance areas in Forever (Hall of Thanes etc.)
for a, z in Z.items():
    if not z['u'] and z['n'] not in ('Crafting', ''): z['d'] = 1
    if a == '25': z['n'] = 'Blackrock Mountain'; z['d'] = 1
    if '->' in z['n']:
        z['n'] = z['n'].split('->')[0].strip(); z['d'] = 1   # instance mapped onto an outdoor map
    if z['n'] in ('Alterac Valley', 'Warsong Gulch', 'Arathi Basin'): z['d'] = 1
# XP by quest level, from classic data, for quests with unknown XP
byl = collections.defaultdict(list)
for r in Q.values():
    if r['xp'] > 0 and 1 <= r['l'] <= 60: byl[r['l']].append(r['xp'])
LX = {}
for l in range(1, 61):
    vals = byl.get(l)
    v = int(statistics.median(vals)) if vals else 0
    LX[l] = max(v, LX.get(l-1, 0))
def s(x): return '"' + x.replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ') + '"'
def lst(v): return '{' + ','.join(str(i) for i in v) + '}' if v else 'nil'
out = ['-- Generated from QuestieDB (Forever flavor, GPL-3.0). Do not edit by hand.',
       'DuoRoute_Data = {}', 'local Q = {}', 'DuoRoute_Data.Q = Q']
SK = d['sk']
EVENT = set(SK[k] for k in ('SEASONAL','HALLOWS_END','LUNAR_FESTIVAL','MIDSUMMER','BREWFEST','CHILDRENS_WEEK',
  'LOVE_IS_IN_THE_AIR','WINTER_VEIL','HARVEST_FESTIVAL','DARKMOON_FAIRE','NOBLEGARDEN','PILGRIMS_BOUNTY',
  'DAY_OF_THE_DEAD','AHN_QIRAJ_WAR','INVASION','BATTLEGROUNDS','SPECIALTEMP','LEGENDARY','REPUTATION') if k in SK)
PROF = set(SK[k] for k in ('ALCHEMY','BLACKSMITHING','COOKING','ENGINEERING','FIRST_AID','FISHING','HERBALISM',
  'JEWELCRAFTING','LEATHERWORKING','TAILORING','INSCRIPTION','ARCHAEOLOGY') if k in SK)
n = 0
for qid in sorted(Q, key=int):
    r = Q[qid]
    if r['rep']: continue
    flags = (2 if r['sk'] else 0) | (4 if r.get('it') else 0) | (8 if r.get('rr') else 0)
    if r.get('so') in EVENT: flags |= 64
    if r.get('ou'): flags |= 128
    if r.get('pf') or r.get('so') in PROF: flags |= 2
    ff = r.get('ff') or ''
    if ff == 'A': flags |= 16
    elif ff == 'H': flags |= 32
    st = r.get('s') or [0, 0, 0]; fi = r.get('f') or [0, 0, 0]
    # name, lvl, req, races, classes, zone, preGroup, preSingle, excl, next, flags, xp,
    # startZone, sx, sy, starter, finZone, fx, fy, maxLvl, breadcrumbFor, parent
    fields = [s(r['n']), r['l'], r['r'], r['ra'], r['c'], r['z'], lst(r['pg']), lst(r['ps']), lst(r['ex']),
              r['nx'] or 0, flags, r['xp'], st[0], st[1], st[2], s(r.get('sn') or ''), fi[0], fi[1], fi[2],
              r.get('mx') or 0, r.get('bc') or 0, r.get('pq') or 0,
              ('{' + ','.join('{%d,%s,%s,%s,%d}' % (o[0], o[1], o[2], s(o[3]), o[4]) for o in r['ob']) + '}') if r.get('ob') else 'nil',
              s(r.get('fn') or '')]
    out.append('Q[%s]={%s}' % (qid, ','.join(str(f) for f in fields)))
    n += 1
out.append('DuoRoute_Data.Z = {')
for a in sorted(Z, key=int):
    z = Z[a]
    out.append('[%s]={%s,%d,%d},' % (a, s(z['n']), z['u'], z['d']))
out.append('}')
out.append('DuoRoute_Data.FM = {')
for f in d['fm']:
    out.append('{%d,%d,%s,%s,%s,%s},' % (f[0], f[1], f[2], f[3], s(f[4]), s(f[5])))
out.append('}')
# Boats and zeppelins: {fromArea, x, y, toArea, x, y, faction, "name"} (zeppelin towers from the zeppelin masters' spots)
TRANSPORTS = [
  (14, 50.8, 13.5, 85, 60.7, 58.9, 'H', 'zeppelin'),
  (14, 50.7, 12.9, 33, 31.4, 29.9, 'H', 'zeppelin'),
  (85, 61.8, 59.2, 33, 31.5, 29.4, 'H', 'zeppelin'),
  (17, 63.7, 38.6, 33, 25.9, 73.1, 'AH', 'boat'),
  (11, 4.6, 57.1, 15, 71.6, 56.4, 'A', 'boat'),
  (11, 4.9, 63.4, 148, 32.4, 43.8, 'A', 'boat'),
  (148, 33.2, 40.0, 141, 54.9, 96.8, 'A', 'boat'),
]
out.append('DuoRoute_Data.TR = {')
for t in TRANSPORTS:
    out.append('{%d,%s,%s,%d,%s,%s,%s,%s},' % (t[0], t[1], t[2], t[3], t[4], t[5], s(t[6]), s(t[7])))
out.append('}')
TAGS = json.load(open(os.path.join(ROOT, 'build', 'tags.json')))
out.append('DuoRoute_Data.TAG = {' + ','.join('[%s]=%d' % (k, v) for k, v in sorted(TAGS.items(), key=lambda x: int(x[0]))) + '}')
out.append('DuoRoute_Data.LX = {' + ','.join(str(LX[l]) for l in range(1, 61)) + '}')
DATA = os.path.join(ROOT, 'DuoRoute', 'Data.lua')
open(DATA, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
print(n, 'quests written', os.path.getsize(DATA), 'bytes')
print('LX', [LX[l] for l in (40,45,50,55,60)])
