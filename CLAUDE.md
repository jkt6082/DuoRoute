# DuoRoute project: briefing for Claude Code

Joel's World of Warcraft **Forever** addons. Main one is **DuoRoute**, a Zygor-style levelling guide
built for a duo (Joel: Horde Troll Warlock, ~level 49-50; his friend: Paladin). Started in a claude.ai
chat; this folder is the full project so work can continue here.

Joel prefers brief replies and no em dashes in writing. Describe changes by their in-game effect,
and always say whether a change needs `/reload` or a full restart.

## Layout
- `DuoRoute/`: the addon (deploy target: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\DuoRoute`)
- Joel's other addons (NightfallAlert, NightfallBorder, ShoutReminder) live in a separate repo.
- `tools/`: data pipeline. `build_data.py` runs `extract.py` -> `tags.py` -> `gendata.py` and rewrites `DuoRoute/Data.lua`
- `tests/`: Python + `lupa` harness running the addon against `mockwow.lua` (a mock WoW API). `python tests/run_tests.py`
- `build/forever.json`, `build/tags.json`: pipeline intermediates (tests read forever.json)
- `vendor/` (not included): put `QuestieDB` and `Questie` here to rebuild data
  (github.com/Questie/QuestieDB and github.com/Questie/Questie, default branches)
- `deploy.ps1`: copies DuoRoute into the AddOns folder

## Client facts (important)
- WoW Forever runs on the **Midnight retail client**: `## Interface: 16001`, retail APIs (`C_QuestLog`,
  `C_Map`, `C_TaxiMap`, `C_Spell`...), Lua 5.1. Avoid Lua 5.2+ syntax (no `goto`, `//`, bit ops).
- Midnight "secret values": aura data is often unreadable by addons in combat; wrap reads in `pcall`.
  (This is why NightfallAlert also watches Shadow Bolt cast time and proc glow.)
- `/reload` picks up edits to existing files. Any NEW file (lua, tga, mp3) or `.toc` change needs a full restart.
- Images are 32-bit TGA, power-of-two sizes. Addon paths: `Interface\\AddOns\\<Addon>\\file.tga`.

## DuoRoute architecture (load order = .toc order)
- `Data.lua` (generated, ~900 KB): `DuoRoute_Data.Q[questID]` positional records (field indices in `Core.lua` `DR.F`),
  `Z` zones `{name, uiMapID, isDungeon}`, `FM` flight masters, `TR` boats/zeppelins (hand-entered, classic only),
  `TAG` dungeon/raid/elite tags, `LX` median quest XP by level. Never hand-edit; change the tools.
- `Core.lua`: player context (`DR.me`), saved vars (`DuoRouteDB` account, `DuoRouteChar` per character),
  learning: XP/hour per zone, quest XP calibration vs database, abandoned quests.
- `Engine.lua`: quest status per player (`DR.Status`), XP estimates, quest tags, zone planner (`DR.Plan`), waypoints (`DR.SetWaypoint` also drives the arrow).
- `Sync.lua`: party addon messages (prefix `DuoRt1`): hello/levels, completed quests (base36, chunked), quest logs, turn-ins.
- `Travel.lua`: known flight paths (only confirmed via the flight map, never guessed), hearthstone, Dijkstra over walk/fly/boat/hearth,
  town names, flight-map marker on the node to pick (supports FlightMapFrame pins and classic TaxiFrame buttons).
- `Route.lua`: simulator that plays forward to 60: zone choice by XP/minute incl. real travel, nearest-first ordering of
  accept/objective/turn-in, chain unlocks, level-ups, trainer steps, flight-path pickup steps, 20-quest log cap. Live step tracking (`DR.StepDone`, `DR.AdvanceRoute`).
  Excludes dungeon/raid quests always and elite quests when solo.
- `Guide.lua`: floating step viewer; keeps solo + duo routes, Solo/Duo switch, estimates to 60 (plan + measured pace), travel legs, replans on level-up, partner change, flight path change, and off-route accepts/turn-ins.
- `Arrow.lua`: on-screen arrow (GetPlayerFacing + map position), check mark on arrival.
- `UI.lua`: `/duo` planner window (zones / dungeons / what it's learned) and slash commands.

## Data pipeline rules
- QuestieDB files are read as DATA by `tools/luaparse.py` (a table-literal parser). Do **not** execute QuestieDB/Questie Lua or their bundled binaries.
- Merge order: Era fixes -> Forever generated base -> Forever authored fixes (`_add`/`_remove` keys = index +/- 1000).
- Objective locations = densest spawn cluster of the mob/object/item-drop source; ~1/3 of 44-60 quests have no locatable objective
  (flag 128 UNLOCATED -> "Finish the remaining objectives" step). Quests that hand you an item to carry are deliveries, not unlocated.
- Repo is GPL-3.0 (LICENSE); Data.lua is derived from QuestieDB/Questie (see DuoRoute/NOTICE.txt). Never use the Questie name or logo.

## Known gaps / backlog
- Dungeon runs as optional route steps (asked about; pending Joel's answer on whether they group via LFG).
- Forever-new boats/zeppelins (e.g. new Hillsbrad boat) not in `TR`; no portals.
- Travel and kill-time constants are estimates, untested against real map geometry; "your pace" corrects ETA from real play.
- Untested in the live client: which flight map frame Forever uses; GetQuestTagInfo availability.
- Redesign of the UI may come: a design canvas of the current layout exists on claude.ai.

## Workflow
1. Edit `DuoRoute/...` (or `tools/` then `python tools/build_data.py`).
2. `python tests/run_tests.py` (needs `pip install lupa`; Pillow for regenerating TGA art).
3. `powershell -ExecutionPolicy Bypass -File deploy.ps1`, then tell Joel `/reload` or restart.
