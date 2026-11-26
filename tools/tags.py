"""Dungeon / Raid / Elite quest tags from Questie's tag corrections (data only, nothing executed)."""
import re, json, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(ROOT, 'vendor', 'Questie', 'Database', 'Corrections', 'questTagInfoCorrections.lua'), encoding='utf-8').read()
tags = {}
for m in re.finditer(r'\[(\d+)\]\s*=\s*(.*?)\{(\d+),\s*l10n', src):
    qid, cond, tag = int(m.group(1)), m.group(2).strip(), int(m.group(3))
    if cond:
        # Forever is Era-based: keep only conditions that include Era
        if not ('Expansions.Era' in cond and '==' in cond) and not re.search(r'Expansions.Current\s*<=?\s*Expansions\.\w+', cond):
            continue
    if tag in (1, 62, 81):
        tags[qid] = tag
os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
json.dump(tags, open(os.path.join(ROOT, 'build', 'tags.json'), 'w'))
print(len(tags), 'quest tags')
