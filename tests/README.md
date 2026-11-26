# dG KillShot tests

These tests run the addon's Lua files in a Lua 5.1 sandbox, with stand-ins for the game API. They check the addon's logic. They don't check how anything looks in game, and frames are stand-ins, so layout isn't tested.

They need Python 3 and [lupa](https://pypi.org/project/lupa/):

```
pip install lupa
python tests/run_all.py            # every test, with a summary
python tests/run_all.py -v         # also print each test's output
python tests/run_all.py sync pvp   # only tests whose file name contains one of the words
python tests/test_sync_fields.py   # one test
```

They work from any folder. Each test prints PASS or FAIL for each check and exits with 1 if any check fails, and so does `run_all.py`.

`.pkgmeta` leaves this folder out of the release package.

## Tests

| File | What it checks |
| --- | --- |
| `test_sync.py` | Guild history sync between simulated clients: live records, catch-up after being offline, late joiners, backlogs over several rounds, forged or malformed messages, pruning, no whispers to members who logged off, and hiding "No player named …" |
| `test_sync_fields.py` | Every shared record field reaches other members unchanged, live and through catch-up sync, on retail and Forever names |
| `test_battleground.py` | Team kills by party and raid members: who records them, and which reach guild history |
| `test_death.py` | Deaths on retail: the killer from Blizzard's Death Recap, secret or hidden killers, and the likely-killer guess |
| `test_pvp_logging.py` | Only PvP kills and deaths are logged by default; the *Also log PvE kills and deaths* option; Classic deaths by who landed the last hit |
| `test_chat_counts.py` | The "killed N times" chat lines count kills, deaths, duel wins and duel losses separately from personal history; the old kill and death lists are no longer written |
| `test_unknown_killer.py` | Unknown and likely killers: how they're stored, counted and shown |
| `test_forever.py` | Forever first and last names in your own name, kills, history, team kills, duels and the player cache; retail unchanged |
| `test_guild_forever.py` | Forever guild history: merging stores saved by older versions without losing records, our own name read late at login, and members recorded by first name only (departed members, classes, shared first names, an empty roster, the surname separator) |
| `test_player_not_found.py` | Kill and duel emotes target the victim's unit, never a name; Battle.net whisper names |
| `test_emotes.py` | The emote choices offer exactly the targetable emotes of each game version (`data/targetable_emotes.json`, from the game's emote tables) |
| `test_players.py` | The player cache: inspecting enemies for their spec, throttling, and lookups |
| `test_tooltip.py` | Kill and death counts in unit tooltips, across realm spellings |
| `test_guild_opponents.py` | The Guild opponents view: one opponent across realm spellings, totals and top killers |
| `test_window.py` | The main window: Overview numbers, the 14-day chart, top prey and predators, History rows, sorting and filters |
| `test_main_window.py` | The Settings tab's History options |
| `test_options.py` | The options: what is registered and the order of the Settings tabs |
| `test_minimap.py` | The minimap button: position, clicks, dragging and tooltip |
| `test_recap_window.py` | The death recap: rows, times, crits, school and health colours, the killing-blow row and the Compact view |
| `test_recap_close.py` | The death recap closes when you're alive again, but not when you release to a ghost |

`names_prelude.py` loads dgks.lua's name helpers into tests that load a single module without dgks.lua.
