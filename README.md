# pfQuest Epoch Commission Tracker

A small, separate addon for WoW 3.3.5 that adds multi-profession checkbox filtering, explicit faction-plus-neutral views, and map markers for Project Epoch commission quests. It uses the quest and location databases already loaded by `pfQuest-wotlk` and `pfQuest-epoch`; it does not modify either addon.

## Features
<img width="1248" height="1202" alt="Screenshot 2026-11-24 185958" src="https://github.com/user-attachments/assets/34371cab-448e-4b37-878c-fc125d639f29" />
<img width="1161" height="663" alt="Screenshot 2026-11-24 185949" src="https://github.com/user-attachments/assets/b227319e-76a0-41e6-959d-c0f50204d23e" />

- Detects commission quests from the Epoch quest database by the `Commission for` title and the quest metadata's profession (`skill`) ID.
- Lists quests by profession, including the minimum required skill rank and quest level.
- Multi-select profession checkboxes: choose any combination of professions, use **Select all**, or clear the selection.
- Faction views: `My Faction + Neutral`, `Alliance + Neutral`, `Horde + Neutral`, or `All (Alliance + Horde + Neutral)`. Neutral commissions are included in either faction-specific view and appear once in the all-factions list.
- Detects explicit quest race masks and, when absent, uses pfQuest's own quest-starter faction lookup to identify Alliance/Horde commissions.
- Shows each commission's faction classification in the list and tooltip.
- Marks only the commission quest giver and turn-in NPC/object locations. Objective mobs, gathering nodes, item sources, area triggers, and other objective locations are deliberately excluded. All tracker locations use pfQuest-wotlk’s dedicated `img/track.tga` pin texture, clearly distinguishing tracked commissions from normal available/completed quest question marks.
- Includes unfinished quests by default, including quests already in the quest log.
- Can optionally include completed commissions.
- Can request the character's completed-quest list from the server when `QueryQuestsCompleted()` is available; otherwise it falls back to pfQuest's local quest history.
- Keeps the selected combination of professions and display options in per-character SavedVariables.

The supplied database contains **473** commission records with a profession requirement across 12 skill lines: Alchemy, Blacksmithing, Enchanting, Engineering, First Aid, Fishing, Herbalism, Leatherworking, Mining, Skinning, Tailoring, and Cooking.

## Installation

1. Keep `pfQuest-wotlk` and `pfQuest-epoch` installed as usual.
2. Extract the `pfQuest-epoch-commissions` folder from this archive into `World of Warcraft\Interface\AddOns\`.
3. Enable **pfQuest [Epoch Commission Tracker]** at the character-select AddOns screen.
4. Log in and type `/commission` or `/pfc`.

## Use

- Tick one or more profession checkboxes. **Select all** selects every detected commission profession; **Clear** removes every selection. With no professions selected, the list and markers are empty.
- Select **My Faction + Neutral**, **Alliance + Neutral**, **Horde + Neutral**, or **All (Alliance + Horde + Neutral)** from the faction dropdown. My Faction follows the character. Neutral commissions are included in both faction-specific views; the all-factions view shows the union of both faction sets and neutral commissions without duplicating rows.
- **Show tracked quest pins** controls whether the filtered unfinished commissions are added to the world map and minimap. Pins mark only quest givers and turn-in NPCs/objects; objective mobs, resource nodes, item sources, and other objective locations are not marked. This keeps the tracker focused on where commissions are accepted and turned in.
- **Include completed** adds completed commissions back to the list and marker set.
- Click a quest row to open the map at the best indexed location for that commission.
- **Open map** opens a map that contains the highest concentration of the filtered commission locations.
- **Sync completions** requests the completed-quest list from the server, if the client/server exposes `QueryQuestsCompleted()`.

Slash commands:

- `/commission` — open the tracker
- `/commission sync` — request a fresh server completion query
- `/commission refresh` — rebuild the list and markers

## Version 1.2.5

- Fixed marker generation by reading each commission's explicit `start` and `end` NPC/gameobject IDs and searching only those entities with pfQuest's `SearchMobID()` / `SearchObjectID()` APIs.
- Removed the fragile post-filtering of `SearchQuestID()` results. That API includes objective mobs, objects, item sources, and area triggers, and its mixed result set was causing tracked markers and map indexes to be lost in the supplied Epoch/pfQuest combination.
- Restored per-quest map indexes so clicking a commission opens a map containing its indexed quest giver or turn-in location.
- Uses pfQuest-wotlk's dedicated `img/track.tga` texture. A small `pfMap.UpdateNode` compatibility hook preserves the track pin's layer-6 priority while displaying the actual `track.tga` artwork.
- Keeps commission pins limited to quest givers and turn-in NPCs/objects; objective locations are not added.

## Version 1.2.3

- Restricted tracker stars to commission quest givers and turn-in NPCs/objects.
- Removed objective mobs, gathering nodes, item sources, area triggers, and other quest-objective locations from the tracker marker set.
- Removed this addon's objective tooltip associations, so objective creatures no longer appear to be tracked by the commission tracker.
- Rebuilt each quest's map index from the retained giver/turn-in markers only.

## Version 1.2.2

- Replaced the misleading yellow available/completed quest question-mark markers with pfQuest’s gold star marker for tracked commission locations.
- Renamed the map-marker checkbox to **Show tracked quest stars** so the in-game control matches the new marker.

## Version 1.2.1

- Fixed profession checkbox sizing: checkboxes now render as normal square boxes instead of stretched horizontal bars. The profession label remains clickable.

## Version 1.2.0

- Replaced the single-profession dropdown with persistent multi-select profession checkboxes.
- Added **Select all** and **Clear** actions.
- Made faction scope explicit: Alliance and Horde views each include neutral quests, while the all-factions view shows both faction sets plus neutral quests.
- Quest rows distinguish **Alliance**, **Horde**, **Alliance & Horde**, and **Neutral** commissions.
- Existing single-profession settings are migrated to the corresponding checkbox selection; the previous default of all professions is preserved.

## Notes / limitations

- Map markers can only be shown where the pfQuest databases contain coordinates. A quest with missing NPC/object coordinates will still appear in the list but may have no clickable map location.
- The server completion query depends on the Epoch server exposing the WotLK `QueryQuestsCompleted()` API. When unavailable, completed status depends on pfQuest's saved per-character quest history.
- Faction matching uses the standard WotLK race masks (including Draenei and Blood Elf) and pfQuest's `GetRaceMaskByID()` helper. Quests with no race restriction and no faction-specific quest starter are treated as available to all factions.
- Profession names and quest titles use the enUS data supported by the supplied `pfQuest-epoch` package.


### Map marker indexing (1.2.5)

Commission pins are now created directly from each quest record's explicit `start` and `end` entity IDs. The tracker uses pfQuest's `SearchMobID()` and `SearchObjectID()` APIs for those NPC/gameobject IDs only. It does **not** use `SearchQuestID()` for pin generation, because that API also indexes objective creatures, objects, item sources, and area triggers. Clicking a commission now opens the best map containing its indexed starter/turn-in locations.
