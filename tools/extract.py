"""Build DuoRoute's quest data from QuestieDB's Forever sources, reading files as data only."""
import re, json, sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from luaparse import parse_table_after, as_list

R = os.path.join(ROOT, 'vendor', 'QuestieDB') + os.sep
read = lambda p: open(os.path.join(R, p), encoding='utf-8').read()
os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)

# ---------- enums ----------
zoneIDs = parse_table_after(read('src/corrections/enum/zones.lua'), r'constants\.zoneIDs\s*=\s*')
qsrc = read('src/corrections/enum/quests.lua')
sortKeys = parse_table_after(qsrc, r'constants\.sortKeys\s*=\s*')
specialFlags = parse_table_after(qsrc, r'constants\.specialFlags\s*=\s*')
questFlags = parse_table_after(qsrc, r'constants\.questFlags\s*=\s*')
factionIDs = parse_table_after(read('src/corrections/enum/factions.lua'), r'constants\.factionIDs\s*=\s*')
psrc = read('src/corrections/enum/professions.lua')
profKeys = parse_table_after(psrc, r'constants\.professionKeys\s*=\s*')
rankNames = parse_table_after(psrc, r'constants\.rankNames\s*=\s*')
specKeys = parse_table_after(psrc, r'constants\.specializationKeys\s*=\s*')
SKY_A, SKY_H = 2 ** 32, 2 ** 33
raceKeys = {'NONE': 0, 'HUMAN': 1, 'ORC': 2, 'DWARF': 4, 'NIGHT_ELF': 8, 'UNDEAD': 16, 'TAUREN': 32,
            'GNOME': 64, 'TROLL': 128, 'GOBLIN': 256, 'SKYBORNE_ALLIANCE': SKY_A, 'SKYBORNE_HORDE': SKY_H,
            'ALL_ALLIANCE': 1 + 4 + 8 + 64 + SKY_A, 'ALL_HORDE': 2 + 16 + 32 + 128 + SKY_H}
classKeys = {'NONE': 0, 'WARRIOR': 1, 'PALADIN': 2, 'HUNTER': 4, 'ROGUE': 8, 'PRIEST': 16, 'DEATH_KNIGHT': 32,
             'SHAMAN': 64, 'MAGE': 128, 'WARLOCK': 256, 'MONK': 512, 'DRUID': 1024, 'ALL_CLASSES': 1503}


def keys_of(path, field):
    k = parse_table_after(read(path), r'QuestieDB\.%s\s*=\s*' % field)
    out = {}
    for name, idx in k.items():
        out[name] = idx
        out[name + '_add'] = idx + 1000
        out[name + '_remove'] = idx - 1000
    return k, out


QK, questKeys = keys_of('data/Forever/foreverQuestDB.lua', 'questKeys')
NK, npcKeys = keys_of('data/Forever/foreverNpcDB.lua', 'npcKeys')
OK, objectKeys = keys_of('data/Forever/foreverObjectDB.lua', 'objectKeys')
IK, itemKeys = keys_of('data/Forever/foreverItemDB.lua', 'itemKeys')
print('quest keys', sorted(QK.items(), key=lambda x: x[1])[-8:])

ENV = {
    'questKeys': questKeys, 'npcKeys': npcKeys, 'objectKeys': objectKeys, 'itemKeys': itemKeys, 'zoneIDs': zoneIDs,
    'raceIDs': raceKeys, 'raceKeys': raceKeys, 'classIDs': classKeys, 'classKeys': classKeys,
    'sortKeys': sortKeys, 'specialFlags': specialFlags, 'questFlags': questFlags, 'factionIDs': factionIDs,
    'profKeys': profKeys, 'specKeys': specKeys, 'rankKeys': rankNames,
}
ENV['QuestieDB'] = {'itemKeys': itemKeys, 'questKeys': questKeys, 'npcKeys': npcKeys, 'objectKeys': objectKeys, 'raceKeys': raceKeys,
                    'classKeys': classKeys, 'sortKeys': sortKeys, 'specialFlags': specialFlags,
                    'questFlags': questFlags, 'factionIDs': factionIDs}
ENV['ZoneDB'] = {'zoneIDs': zoneIDs}


def load_data(path, field):
    src = read(path)
    m = re.search(r'QuestieDB\.%s\s*=\s*\[(=*)\[' % field, src)
    eq = m.group(1)
    end = src.index(']' + eq + ']', m.end())
    body = src[m.end():end]
    return parse_table_after(body, r'return\s*')


quests = load_data('data/Forever/foreverQuestDB.lua', 'questData')
npcs = load_data('data/Forever/foreverNpcDB.lua', 'npcData')
objs = load_data('data/Forever/foreverObjectDB.lua', 'objectData')
items = load_data('data/Forever/foreverItemDB.lua', 'itemData')
print('base', len(quests), len(npcs), len(objs))


def apply(db, fixes):
    n = 0
    for id_, fix in fixes.items():
        if not isinstance(id_, int) or not isinstance(fix, dict):
            continue
        row = db.setdefault(id_, {})
        for key, val in fix.items():
            if not isinstance(key, int):
                continue
            if key > 500:  # _add
                k = key - 1000
                if not isinstance(val, dict):
                    continue
                cur = row.get(k)
                if not isinstance(cur, dict):
                    cur = {}
                vals = list(val.values())
                if any(isinstance(v, dict) for v in vals) and k in (2, 3):  # startedBy / finishedBy
                    for i, subl in val.items():
                        lst = as_list(cur.get(i))
                        lst += as_list(subl)
                        cur[i] = {j + 1: v for j, v in enumerate(lst)}
                elif k in (7, 8) and any(isinstance(v, dict) for v in vals):  # spawns map
                    for z, coords in val.items():
                        lst = as_list(cur.get(z)) + as_list(coords)
                        cur[z] = {j + 1: v for j, v in enumerate(lst)}
                else:
                    lst = as_list(cur) + as_list(val)
                    cur = {j + 1: v for j, v in enumerate(lst)}
                row[k] = cur
            elif key < 0:  # _remove
                k = key + 1000
                cur = row.get(k)
                if not isinstance(cur, dict) or not isinstance(val, dict):
                    continue
                if any(isinstance(v, dict) for v in val.values()):
                    for i, subl in val.items():
                        rm = set(v for v in as_list(subl) if not isinstance(v, dict))
                        if isinstance(cur.get(i), dict):
                            lst = [v for v in as_list(cur[i]) if isinstance(v, dict) or v not in rm]
                            cur[i] = {j + 1: v for j, v in enumerate(lst)}
                else:
                    rm = set(v for v in as_list(val) if not isinstance(v, dict))
                    lst = [v for v in as_list(cur) if isinstance(v, dict) or v not in rm]
                    row[k] = {j + 1: v for j, v in enumerate(lst)}
            else:
                row[key] = val
        n += 1
    return n


def run_fix(path, db):
    src = read(path)
    m = re.search(r'function\s+\w+:Load\(\)', src)
    if not m:
        print('no Load in', path); return
    try:
        fixes = parse_table_after(src, r'return\s*', ENV, start=m.end())
        print('applied', path, apply(db, fixes))
    except Exception as e:
        print('FAILED', path, str(e)[:200])


run_fix('src/corrections/Era/classicQuestFixes.lua', quests)
run_fix('src/corrections/Era/classicNPCFixes.lua', npcs)
run_fix('src/corrections/Era/classicObjectFixes.lua', objs)
run_fix('src/corrections/Era/classicItemFixes.lua', items)
run_fix('src/corrections/Forever/generated/foreverBaseItem.lua', items)
run_fix('src/corrections/Forever/foreverItemFixes.lua', items)
run_fix('src/corrections/Forever/generated/foreverBaseQuest.lua', quests)
run_fix('src/corrections/Forever/generated/foreverBaseNpc.lua', npcs)
run_fix('src/corrections/Forever/generated/foreverBaseObject.lua', objs)
run_fix('src/corrections/Forever/foreverQuestFixes.lua', quests)
run_fix('src/corrections/Forever/foreverNPCFixes.lua', npcs)
run_fix('src/corrections/Forever/foreverObjectFixes.lua', objs)

# ---------- zones ----------
zsrc = read('support/Forever/Zones/areaIdToUiMapId.lua')
zone_map, zone_names = {}, {}
for m in re.finditer(r'\[(\d+)\]\s*=\s*(\d+),\s*--\s*([^\n]+)', zsrc):
    a, u, name = int(m.group(1)), int(m.group(2)), m.group(3).strip()
    if u and (a not in zone_map or zone_map[a] == 0):
        zone_map[a] = u
    if not re.match(r'(Synthetic|Referenced|Existing|Legacy)', name):
        zone_names.setdefault(a, name)
sub = {int(a): int(b) for a, b in re.findall(r'\[(\d+)\]\s*=\s*(\d+),', read('support/Forever/Zones/subZoneToParentZone.lua'))}
dungeons = set()
for sym in re.findall(r'zoneIDs\.([A-Z_0-9]+)', read('support/Forever/Zones/instanceIdToAreaId.lua')):
    if sym in zoneIDs:
        dungeons.add(zoneIDs[sym])
print('zones', len(zone_map), 'dungeons', len(dungeons))

xp = {int(a): int(c) for a, b, c in re.findall(r'\[(\d+)\]\s*=\s*\{(\d+),\s*(\d+)\}', read('support/QuestXP/xpDB-classic.lua'))}


def spawn_of(row, spawnKey):
    sp = row.get(spawnKey)
    if not isinstance(sp, dict):
        return None
    best = None
    for z in sorted(k for k in sp if isinstance(k, int)):
        coords = as_list(sp[z])
        if not coords or not isinstance(coords[0], dict):
            continue
        x, y = coords[0].get(1), coords[0].get(2)
        if not isinstance(x, (int, float)) or not isinstance(y, (int, float)) or x < 0:
            continue
        cand = (z, round(x, 1), round(y, 1))
        if best is None or (best[0] in dungeons and z not in dungeons):
            best = cand
    return best


def locate(sb, kinds):
    if not isinstance(sb, dict):
        return None, None, None
    for kind, db, keys in kinds:
        for sid in as_list(sb.get(kind)):
            r = db.get(sid)
            if not isinstance(r, dict):
                continue
            s = spawn_of(r, keys['spawns'])
            if s:
                return s, r.get(keys['name']), (r.get(NK['friendlyToFaction']) if kind == 1 else None)
    return None, None, None


KINDS = ((1, npcs, NK), (2, objs, OK))


def coords_of(db, keys, ids):
    pts = {}
    for i in ids:
        r = db.get(i)
        if not isinstance(r, dict):
            continue
        sp = r.get(keys['spawns'])
        if not isinstance(sp, dict):
            continue
        for z, lst_ in sp.items():
            if not isinstance(z, int):
                continue
            for c in as_list(lst_):
                if isinstance(c, dict) and isinstance(c.get(1), (int, float)) and isinstance(c.get(2), (int, float)) and c[1] >= 0:
                    pts.setdefault(z, []).append((c[1], c[2]))
    return pts


def hotspot(pts, prefer):
    if not pts:
        return None
    zones = sorted(pts, key=lambda z: (z == prefer, z not in dungeons, len(pts[z])), reverse=True)
    z = zones[0]
    P = pts[z]
    best, bestN = None, -1
    for (x, y) in P:
        n = sum(1 for (a, b) in P if (a - x) ** 2 + (b - y) ** 2 <= 64)
        if n > bestN:
            best, bestN = (x, y), n
    near = [(a, b) for (a, b) in P if (a - best[0]) ** 2 + (b - best[1]) ** 2 <= 64]
    cx = sum(a for a, _ in near) / len(near)
    cy = sum(b for _, b in near) / len(near)
    # snap to the real spawn closest to the centroid so the waypoint lands on a mob
    sx, sy = min(near, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
    return (z, round(sx, 1), round(sy, 1))


def count_in(text, label):
    if not text or not label:
        return 0
    stem = re.escape(label[:max(4, len(label) - 2)])
    m = re.search(r'(\d+)\s+(?:of\s+(?:the\s+)?)?' + stem, text, re.I)
    return int(m.group(1)) if m else 0


def text_all(row):
    return ' '.join(v for v in as_list(row.get(QK['objectivesText'])) if isinstance(v, str))


def objectives_of(row, prefer):
    obj = row.get(QK['objectives'])
    text = ' '.join(v for v in as_list(row.get(QK['objectivesText'])) if isinstance(v, str))
    out = []
    if isinstance(obj, dict):
        for o in as_list(obj.get(1)):
            if isinstance(o, dict) and isinstance(o.get(1), int):
                r = npcs.get(o[1]) or {}
                lab = o.get(2) if isinstance(o.get(2), str) else r.get(NK['name'])
                h = hotspot(coords_of(npcs, NK, [o[1]]), prefer)
                if h and lab: out.append((h, 'Kill ' + lab, count_in(text, r.get(NK['name']) or lab)))
        for o in as_list(obj.get(2)):
            if isinstance(o, dict) and isinstance(o.get(1), int):
                r = objs.get(o[1]) or {}
                lab = o.get(2) if isinstance(o.get(2), str) else r.get(OK['name'])
                h = hotspot(coords_of(objs, OK, [o[1]]), prefer)
                if h and lab: out.append((h, 'Use ' + lab, 0))
        for o in as_list(obj.get(3)):
            if isinstance(o, dict) and isinstance(o.get(1), int):
                it = items.get(o[1]) or {}
                lab = o.get(2) if isinstance(o.get(2), str) else it.get(IK['name'])
                pts = coords_of(npcs, NK, [v for v in as_list(it.get(IK['npcDrops'])) if isinstance(v, int)])
                for z, l in coords_of(objs, OK, [v for v in as_list(it.get(IK['objectDrops'])) if isinstance(v, int)]).items():
                    pts.setdefault(z, []).extend(l)
                h = hotspot(pts, prefer)
                if h and lab: out.append((h, 'Collect ' + lab, count_in(text, it.get(IK['name']) or lab)))
        for o in as_list(obj.get(5)):
            if isinstance(o, dict):
                ids = [v for v in as_list(o.get(1)) if isinstance(v, int)]
                base = o.get(2) if isinstance(o.get(2), int) else None
                lab = o.get(3) if isinstance(o.get(3), str) else (npcs.get(base) or {}).get(NK['name'])
                h = hotspot(coords_of(npcs, NK, ids), prefer)
                if h and lab: out.append((h, lab, 0))
    te = row.get(QK['triggerEnd'])
    if isinstance(te, dict) and isinstance(te.get(2), dict):
        pts = {}
        for z, l in te[2].items():
            for c in as_list(l):
                if isinstance(c, dict) and isinstance(c.get(1), (int, float)):
                    pts.setdefault(z, []).append((c[1], c[2]))
        h = hotspot(pts, prefer)
        if h: out.append((h, te.get(1) if isinstance(te.get(1), str) else 'Explore the area', 0))
    return out[:4]
out = {}
for qid, row in quests.items():
    if not isinstance(qid, int) or not isinstance(row, dict):
        continue
    name = row.get(QK['name'])
    if not isinstance(name, str) or not name:
        continue
    lvl = row.get(QK['questLevel']) or 0
    req = row.get(QK['requiredLevel']) or 0
    if not isinstance(lvl, int) or not isinstance(req, int) or (lvl <= 0 and req <= 0):
        continue
    sb = row.get(QK['startedBy'])
    start, starter, sfac = locate(sb, KINDS)
    finish, finisher, _ = locate(row.get(QK['finishedBy']), KINDS)
    item_start = (not start) and isinstance(sb, dict) and bool(as_list(sb.get(3)))
    zone = row.get(QK['zoneOrSort']) or 0
    if not isinstance(zone, int):
        zone = 0
    sortkey = zone if zone < 0 else 0
    if zone > 0:
        zone = sub.get(zone, zone)
    elif start:
        zone = sub.get(start[0], start[0])
    else:
        zone = 0
    sf = row.get(QK['specialFlags']) or 0
    rs = row.get(QK['requiredSkill'])
    rec = {'n': name, 'l': lvl, 'r': req,
           'ra': int(row.get(QK['requiredRaces']) or 0), 'c': int(row.get(QK['requiredClasses']) or 0),
           'z': zone,
           'pg': [v for v in as_list(row.get(QK['preQuestGroup'])) if isinstance(v, int)],
           'ps': [v for v in as_list(row.get(QK['preQuestSingle'])) if isinstance(v, int)],
           'ex': [v for v in as_list(row.get(QK['exclusiveTo'])) if isinstance(v, int)],
           'nx': row.get(QK['nextQuestInChain']) if isinstance(row.get(QK['nextQuestInChain']), int) else 0,
           'rep': 1 if isinstance(sf, int) and sf % 2 == 1 else 0,
           'sk': 1 if isinstance(rs, dict) and rs.get(1) else 0,
           'xp': xp.get(qid, 0), 'so': sortkey}
    if 'breadcrumbForQuestId' in QK and isinstance(row.get(QK['breadcrumbForQuestId']), int):
        rec['bc'] = row[QK['breadcrumbForQuestId']]
    if 'requiredMaxLevel' in QK and isinstance(row.get(QK['requiredMaxLevel']), int):
        rec['mx'] = row[QK['requiredMaxLevel']]
    if 'parentQuest' in QK and isinstance(row.get(QK['parentQuest']), int) and row[QK['parentQuest']] > 0:
        rec['pq'] = row[QK['parentQuest']]
    if 'requiredMinRep' in QK and isinstance(row.get(QK['requiredMinRep']), dict):
        rec['rr'] = 1
    obs = objectives_of(row, zone)
    objraw = row.get(QK['objectives'])
    total = 0
    if isinstance(objraw, dict):
        for kk in (1, 2, 3, 5):
            total += len(as_list(objraw.get(kk)))
    rec['ou'] = max(0, total - len(obs))
    # quests with no objective data whose text asks you to fetch or kill something: can't be guided
    provided = row.get(QK['sourceItemId'])
    # a quest that hands you the item to carry is a delivery, not a hidden objective
    if total == 0 and not obs and not isinstance(provided, int) and re.search(r'\b(bring|collect|gather|obtain|retrieve|recover|kill|slay|destroy|craft|make)\b', text_all(row), re.I):
        rec['ou'] = 1
    if re.search(r'\b(leatherworking|tailoring|blacksmithing|alchemy|engineering|enchanting|skinning|mining|herbalism|cooking|fishing|first aid)\b', text_all(row), re.I):
        rec['pf'] = 1
    if obs:
        rec['ob'] = [[h[0], h[1], h[2], lab, n] for (h, lab, n) in obs]
    if start:
        rec['s'] = list(start)
        rec['sn'] = starter if isinstance(starter, str) else ''
    if finish:
        rec['f'] = list(finish)
        rec['fn'] = finisher if isinstance(finisher, str) else ''
    if item_start:
        rec['it'] = 1
    if isinstance(sfac, str):
        rec['ff'] = sfac
    out[qid] = rec

# flight masters: by flag, or by title for new Forever NPCs that lack the flag
fms = []
FM_TITLE = re.compile(r'Flight Master|Flight Mistress|Wind Rider Master|Gryphon Master|Hippogryph Master|Bat Handler')
for nid, r in npcs.items():
    if not isinstance(r, dict):
        continue
    sub = r.get(NK['subName']) if isinstance(r.get(NK['subName']), str) else ''
    fl = r.get(NK['npcFlags'])
    flagged = isinstance(fl, int) and (fl // 8) % 2 == 1
    if not flagged and not (FM_TITLE.search(sub) and 'DEBUG' not in (r.get(NK['name']) or '') and '<PH>' not in (r.get(NK['name']) or '')):
        continue
    if 'Spectral' in sub or 'Apprentice' in sub:
        continue
    sp = r.get(NK['spawns'])
    if not isinstance(sp, dict):
        continue
    for z, l in sp.items():
        c = as_list(l)
        if isinstance(z, int) and c and isinstance(c[0], dict) and isinstance(c[0].get(1), (int, float)) and c[0][1] >= 0 and z not in dungeons:
            zz = sub_parent = z
            fms.append([nid, z, round(c[0][1], 1), round(c[0][2], 1), r.get(NK['friendlyToFaction']) or '', r.get(NK['name']) or ''])
            break
print('flight masters', len(fms))

used = set()
for r in out.values():
    used.add(r['z'])
    if 's' in r: used.add(r['s'][0])
    for o in r.get('ob', []): used.add(o[0])
    if 'f' in r: used.add(r['f'][0])
for f in fms: used.add(f[1])
for t in [14, 85, 33, 17, 11, 15, 148, 141]: used.add(t)
SMALL = {'of', 'the', 'and'}
def title(sym):
    words = sym.replace('_OLD', '').split('_')
    return ' '.join(w.capitalize() if (i == 0 or w.lower() not in SMALL) else w.lower() for i, w in enumerate(words))
rev = {}
for sym, a in zoneIDs.items():
    if isinstance(a, int): rev.setdefault(a, title(sym))
zones = {a: {'n': zone_names.get(a) or rev.get(a, ''), 'u': zone_map.get(a, 0), 'd': 1 if a in dungeons else 0}
         for a in used if isinstance(a, int) and a > 0}
json.dump({'q': out, 'z': zones, 'sk': sortKeys, 'fm': fms}, open(os.path.join(ROOT, 'build', 'forever.json'), 'w'))
print('with objectives', sum(1 for r in out.values() if 'ob' in r), 'quests', len(out), 'zones', len(zones), 'with start', sum(1 for r in out.values() if 's' in r))
