# Civ-V-Access

Civ-V-Access is an accessibility mod that makes Sid Meier's Civilization V playable for blind users through screen reader speech. It covers Brave New World only. The mod ships a single BNW manifest, so base-game and Gods and Kings sessions activate no accessibility layer at all.

## Install

With Civilization V closed, run `./deploy.ps1` from the repo root. It copies the committed proxy DLL, DLC payload, and every screen-reader bridge (Tolk plus the per-reader DLLs) into the Steam install — no compile step needed for a normal install. `./deploy.ps1 -Uninstall` removes everything.

When you launch the game and start or load a Brave New World match, the mod speaks "Civilization V accessibility loaded in-game." That confirms the proxy resolved, the DLC activated, and the Lua side is wired. If you don't hear it, something failed silently. See Troubleshooting.

## The hex grid

Civ V's map is a hex grid, not a square one. Each tile has six neighbours. The mod lays the six directions onto QAZEDC: Q for north-west, E for north-east, A for west, D for east, Z for south-west, C for south-east. There are no Up or Down arrow keys for the cursor because there are no straight north or south neighbours. The Shift-letter cluster on the same six keys feeds the surveyor, so the same fingers stay on the home row whether you're moving the cursor or asking what's around it.

## Map keys

Map mode is what you're in whenever no screen, popup, or chooser is on top. The cursor cluster, empire status keys, unit control, and turn lifecycle all live here. **Shift+/** (the question mark key) opens an in-game contextual help list at any time, and that list is the canonical reference. This section is a summary.

### Cursor and tile inspection

**Q, A, Z, E, D, C** move the hex cursor. Each move speaks the new tile: terrain, feature, river edges, resource, improvement, owner, working city, units, yields. **S** reads the unit on the current tile. **W** reads the tile's economic detail (yields and per-source breakdown). **X** reads combat detail (defense bonus, terrain modifiers, river crossings). **1**, **2**, and **3** ask about a city under the cursor: identity and combat, production and growth, diplomacy. **Enter** activates the tile, which selects a unit, opens the city screen on an owned city, or opens diplomacy on a met major civ's city. **Shift+S** speaks distance and direction from the capital. **Ctrl+I** opens the Civilopedia for everything at the cursor's tile.

### Empire status

Bare letters speak one-line headlines. **T** turn and date. **R** current research and science per turn. **G** gold per turn, total, and trade-route slot count. **H** happiness state and golden-age progress. **F** faith per turn and total. **P** culture per turn and turns to the next policy. **I** tourism per turn and influential-civ count. The Shift variants (**Shift+R**, **Shift+G**, **Shift+H**, **Shift+F**, **Shift+P**, **Shift+I**) speak the per-source breakdown a sighted player gets from the top panel's tooltip on hover. Shift+T isn't bound; the bare T already includes everything its tooltip would add.

### Unit control

**.** and **,** cycle to the next or previous unit needing orders. **Ctrl+.** and **Ctrl+,** cycle through every unit including idle ones. **/** reads the selected unit's combat and promotion info. **Ctrl+/** recenters the hex cursor on the selected unit. **Tab** opens the action menu, which lists every action legal for the unit on its current plot, with disabled actions filtered out.

Common actions are also bound to Alt-letter quick keys without going through the menu. **Alt+Q/A/Z/E/D/C** moves the unit one hex in that direction. **Alt+F** fortifies a military unit or sleeps a civilian. **Alt+S** sentries (sleep until an enemy is sighted). **Alt+W** wakes a sleeping or fortified unit. **Alt+Space** skips the unit's turn. **Alt+H** heals until full. **Alt+R** ranged attack. **Alt+P** pillages the unit's tile. **Alt+U** upgrades.

### Turn lifecycle

**Ctrl+Space** ends the turn. If something is blocking, for example a city needing production, no research set, a unit needing orders, a policy waiting, or a religion or ideology pick pending, the mod names the blocker and routes you to the screen that resolves it. **Ctrl+Shift+Space** mirrors the engine's force-end: it gets past unit-action blockers, but other blockers still announce and open.

### Engine screens

These F-row keys reach the engine's own screens. They aren't mod bindings; they pass through. **F1** Civilopedia. **F2** Economic Advisor. **F3** Military Advisor. **F4** Diplomacy Advisor. **F5** Social Policies. **F6** Tech Tree. **F7** turn and event log. **F8** Victory Progress. **F9** Demographics. **F10** opens the advisor counsel popup (rebound from the engine's Strategic View, which has no use without sight). **F12** opens the mod's settings overlay.

## Surveyor

The surveyor answers the question "what's within N tiles of my cursor." Where the cursor reads one hex, the surveyor sweeps a radius of one to five tiles around it and reports counts, totals, or lists. Each Shift-letter key answers one scope question against the current cursor and the shared radius.

**Shift+W** grows the radius. **Shift+X** shrinks it. **Shift+Q** sums yields in range. **Shift+A** counts resources in range, by name. **Shift+Z** counts terrain and features in range. **Shift+E** lists own units in range. **Shift+D** lists enemy units in range. **Shift+C** lists cities in range, closest first.

Each query re-reads live engine state, so a sweep right after a move reflects the new positions.

## Scanner

The scanner answers the question "where is X." It catalogs everything reachable on the map into a four-level hierarchy: category, subcategory, item, instance. Categories cover My, Neutral, and Enemy cities (plus barbarian camps); My, Neutral, and Enemy units split by class (melee, ranged, siege, mounted, naval, air, civilian, great people, plus barbarians for enemy); resources split by strategic, luxury, and bonus; improvements by ownership; special (natural wonders, ancient ruins); terrain (base, features, elevation); and recommendations (settler founding spots and worker tile recommendations).

Each entry announces its name, distance from the cursor, and list position, sorted by distance. The snapshot rebuilds when you change category, and destroyed entities are pruned silently.

**Page Up** and **Page Down** cycle items within the current subcategory. **Shift+Page Up/Down** cycles subcategories within the category. **Ctrl+Page Up/Down** cycles categories. **Alt+Page Up/Down** cycles instances of the current item, for example individual barbarians of one type or each Wheat tile.

**Home** jumps the cursor to the current entry. **Backspace** returns to the cell you were on before the jump (one position saved). **End** speaks distance and direction from the cursor to the current entry without moving. **Shift+End** toggles auto-move; when on, the cursor teleports as you cycle. **Ctrl+F** opens search. Type a query, press Enter, and results group across categories sorted by match quality.

## What doesn't work yet

The audit at `docs/civ_v_accessibility_audit.md` walks every surface in the game and marks each one done, partial, not started, or out of architectural reach. The big gaps a player feels day to day:

- Empire-wide overview screens. The Economic Overview's gold and city tables, the Happiness ledger, the Resource List sidebar, the Demographics screen, and the Victory Progress screen are all unread. Headline numbers are reachable through the empire-status letters, but the source-by-source breakdowns those screens give a sighted player aren't.
- The Brave New World trade route system. The chooser popup that assigns a caravan or cargo ship to a destination isn't read, and neither is the trade-route overview. Caravans build but currently can't be steered, so the system is effectively idle.
- Espionage. Nothing in the spy system reads today: the overview screen, the assignment popup, the intrigue log, election rigging, coups, counterspy results. Spies become a meaningful late-game lever and currently aren't usable.
- The World Congress full session. Vote Results, the League Splash, and the League Project popup are read. The in-session voting screen and the dedicated diplo-vote ballot are not, so most votes outside simple ballots can't be cast.
- The four sidebar lists. City List, Unit List, Great People List, and Resource List, the sortable filterable views of every owned city and unit and so on, aren't reachable.
- Smaller surfaces. The in-game Replay viewer, Hall of Fame, online Leaderboards, scenario per-scenario setup popups, and the task list panel that scenarios use for objectives. The post-game Demographics, Ranking, and Replay tabs of the end-game menu inherit their not-started state too.
- Out of architectural reach. The Pitboss dedicated server runs as a separate executable, and this mod's Lua hooks can't see into another process.

A few partial coverages worth knowing about: foreign city view through espionage (the screen works, the espionage path that opens it doesn't), unit upgrade popup stat-delta detail, and target-mode enumeration for nuke blast radius and rebase range.

## Troubleshooting

If something isn't working, the player log usually has the answer. Civ V writes Lua errors and `print` output to `Lua.log` at `%USERPROFILE%\Documents\My Games\Sid Meier's Civilization 5\Logs\Lua.log`, but only when `LoggingEnabled=1` is set in `config.ini` in the parent of that Logs folder. Engine-level errors land in `APP.log` in the same Logs folder.

The proxy DLL writes `proxy_debug.log` next to itself in the game install directory. This records whether the proxy resolved, whether Tolk loaded, and which screen reader (if any) was found. If you don't hear the boot announcement on first game load, this is the file to check first.

When reporting a bug, include `Lua.log` and `proxy_debug.log` if you have them.
