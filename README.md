# DuoRoute

A step-by-step levelling guide and duo planner for **World of Warcraft: Forever**, built around
levelling with a partner. It plans a full route to level 60 from the quests you've actually done,
syncs with your partner's copy, and learns from how you play.

## Features
- **Route to 60:** simulates your levelling, picking zones by XP per minute, ordering pickups,
  objectives and turn-ins by distance, following quest chains and level-ups.
- **Duo aware:** syncs levels, finished quests and quest logs over party addon messages; favours
  quests you can both do; Solo/Duo switch with time-to-60 estimates for each.
- **Travel:** fastest path using the flight paths you actually know, boats, zeppelins and your
  hearthstone; marks the flight point to pick on the flight map; picks up missing flight paths.
- **On-screen arrow** pointing at your next step, with distance.
- **Learns:** real quest XP vs the database, your XP/hour per zone, quests you abandon.
- **Planner (`/duo`):** best zones for the pair, dungeon quests you both need, what it has learned.
- Never routes into dungeons or raids; elite quests only when grouped.

## Install
Copy the `DuoRoute` folder into `World of Warcraft\_forever_\Interface\AddOns`
(or run `deploy.ps1` on Windows). Both partners need it for duo features.

## Commands
`/duo` planner, `/duo guide` guide window, `/duo arrow` arrow, `/duo reroute`, `/duo sync`,
`/duo fp` flight paths known, `/duo autowp` automatic waypoints, `/duo unhide`.

## Development
- `tools/build_data.py` rebuilds `DuoRoute/Data.lua` from QuestieDB and Questie checked out in `vendor/`.
  The source files are parsed as data (`tools/luaparse.py`); nothing from them is executed.
- `tests/run_tests.py` runs the addon against a mock WoW API (`pip install lupa`).
- `CLAUDE.md` describes the architecture and client quirks.

## Credits and licence
Quest data from [QuestieDB](https://github.com/Questie/QuestieDB) and [Questie](https://github.com/Questie/Questie)
(not affiliated). DuoRoute is licensed under GPL-3.0; see `LICENSE` and `DuoRoute/NOTICE.txt`.
