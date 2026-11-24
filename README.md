# pfQuest Epoch Commission Tracker

A small, separate addon for WoW 3.3.5 that adds multi-profession checkbox filtering, explicit faction-plus-neutral views, and map markers for Project Epoch commission quests. It uses the quest and location databases already loaded by `pfQuest-wotlk` and `pfQuest-epoch`; it does not modify either addon.

## Features

- Detects commission quests from the Epoch quest database by the `Commission for` title and the quest metadata's profession (`skill`) ID.
- Lists quests by profession, including the minimum required skill rank and quest level.
- Multi-select profession checkboxes: choose any combination of professions, use **Select all**, or clear the selection.
- Faction views: `My Faction + Neutral`, `Alliance + Neutral`, `Horde + Neutral`, or `All (Alliance + Horde + Neutral)`. Neutral commissions are included in either faction-specific view and appear once in the all-factions list.
- Detects explicit quest race masks and, when absent, uses pfQuest's own quest-starter faction lookup to identify Alliance/Horde commissions.
- Shows each commission's faction classification in the list and tooltip.
- Marks the quest issuer and destination NPC/object, plus any additional objective locations that pfQuest has indexed.
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
- **Show map markers** controls whether the filtered unfinished commissions are added to the world map and minimap.
- **Include completed** adds completed commissions back to the list and marker set.
- Click a quest row to open the map at the best indexed location for that commission.
- **Open map** opens a map that contains the highest concentration of the filtered commission locations.
- **Sync completions** requests the completed-quest list from the server, if the client/server exposes `QueryQuestsCompleted()`.

Slash commands:

- `/commission` — open the tracker
- `/commission sync` — request a fresh server completion query
- `/commission refresh` — rebuild the list and markers

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
