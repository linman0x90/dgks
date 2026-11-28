"""Our kills in battlegrounds, where PARTY_KILL hides the killer and the victim (dgks_bgkills.lua).

A hidden PARTY_KILL is our killing blow on a player when the Battleground Killing Blows statistic
rises with it and Total Honorable Kills follows; the victim is our target (or soft target) then,
recorded as likely. NPC kills, groupmates' kills, kills with nobody targeted, and anything outside
a battleground are left alone. Runs dgks.lua's retail PARTY_KILL handler with stand-ins for the game.

Needs Python 3 and lupa (pip install lupa). Run from anywhere:

    python tests/test_bgkills.py

Exits with 1 if any check fails.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from names_prelude import REPO

death_code = open(os.path.join(HERE, "test_death.py"), encoding="utf-8").read()
exec(death_code.split("fails = 0")[0])  # defines make(): dgks.lua loaded, History.Record captured

fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra if not cond else "")


L = make()
L.execute(r'''
INSTANCE = "pvp"
IsInInstance = function() return true, INSTANCE end
KB, HK = 17, 222
GetStatistic = function(id)
  if id == 1491 then return KB == 0 and "--" or tostring(KB) end
  if id == 588 then return tostring(HK) end
end
UnitName = function(u) if u == "player" then return "Me", nil end local x = UNITS[u] if x then return x.name, x.realm end end
UnitLevel = function(u) return UNITS[u] and UNITS[u].level end
UnitClass = function(u) return "x", UNITS[u] and UNITS[u].class end
dgks.db.profile.kstextM = { "a", "b", "c" }
KILLSHOTS = {}
function dgks:ProcessKillshot(chan, killer, victim) KILLSHOTS[#KILLSHOTS+1] = victim end
function dgks:SendCM() end
function dgks:Serialize() return '' end
''')
L.execute(open(os.path.join(REPO, "dgks_bgkills.lua"), encoding="utf-8").read())
L.execute("FIRE('ZONE_CHANGED_NEW_AREA')")  # entering the battleground: start from KB = 17


def kill(setup="", kb_rise=True, hk_rise=True, units=None):
    """A hidden PARTY_KILL; the statistics move as the probe saw: KB at once, HK 0.1 s later."""
    L.execute("RECORDS, KILLSHOTS = {}, {}")
    if units is not None:
        L.execute("UNITS = " + units)
    L.execute(setup)
    if kb_rise:
        L.execute("KB = KB + 1")
    L.execute("FIRE('PARTY_KILL', SECRET, SECRET)")
    if hk_rise:
        L.execute("C_Timer.After(0.1, function() HK = HK + 1 end)")
    L.execute("UNITS = {}")  # the target is gone a moment later, as in the probe
    L.execute("RUN_TIMERS(); NOW = NOW + 10")
    return [dict(r.items()) for r in L.eval("RECORDS").values()]


ENEMY = "{ target = { name = 'Sdot', realm = 'Other', player = true, enemy = true, level = 59, class = 'ROGUE' } }"

recs = kill(units=ENEMY)
check("our killing blow on a player: one kill of our target", len(recs) == 1 and recs[0]["k"] == "K" and recs[0]["o"] == "Sdot-Other", recs)
flags = recs[0]["flags"] if recs else None
check("recorded as likely, with the level and class read from the target",
      flags is not None and flags["guessed"] == 1 and flags["level"] == 59 and flags["class"] == "ROGUE", flags and dict(flags.items()))
check("no GUID is claimed", recs and recs[0].get("guid") is None)
check("announced like any killshot", list(L.eval("KILLSHOTS").values()) == ["Sdot-Other"])

recs = kill(units="{ softenemy = { name = 'Round', realm = 'Other', player = true, enemy = true, level = 60 } }")
check("no target: the soft target is the victim", len(recs) == 1 and recs[0]["o"] == "Round-Other", recs)

recs = kill(units=ENEMY, hk_rise=False)
check("killing blow without an honorable kill (an NPC): nothing recorded", recs == [], recs)

recs = kill(units=ENEMY, kb_rise=False)
check("a groupmate's kill (the statistic does not move): nothing recorded", recs == [], recs)

recs = kill(units="{ target = { name = 'Pal', realm = 'Mine', player = true, enemy = false } }")
check("our target is a friend: the victim cannot be named, nothing recorded", recs == [], recs)

recs = kill(units="{}")
check("nobody targeted: nothing recorded", recs == [], recs)

# The statistics count NPC and group kills in between: the next kill of ours is still found
recs = kill(units=ENEMY)
check("after NPC and group kills, our next player kill is found again", len(recs) == 1, recs)

# Two hidden kills in the same moment, both ours: each claims one rise
L.execute("RECORDS, KILLSHOTS = {}, {}")
L.execute("UNITS = " + ENEMY + "; KB = KB + 2")
L.execute("FIRE('PARTY_KILL', SECRET, SECRET); FIRE('PARTY_KILL', SECRET, SECRET)")
L.execute("C_Timer.After(0.1, function() HK = HK + 2 end); UNITS = {}; RUN_TIMERS(); NOW = NOW + 10")
check("two kills at once, both ours: two records", len(L.eval("RECORDS")) == 2)
L.execute("RECORDS = {}; UNITS = " + ENEMY + "; KB = KB + 1")
L.execute("FIRE('PARTY_KILL', SECRET, SECRET); FIRE('PARTY_KILL', SECRET, SECRET)")
L.execute("C_Timer.After(0.1, function() HK = HK + 2 end); UNITS = {}; RUN_TIMERS(); NOW = NOW + 10")
check("two kills at once, one ours: one record", len(L.eval("RECORDS")) == 1)

# Forever: first and last name, no realm
L.execute("RegionalUniqueNamesEnabled = function() return true end; GetNormalizedRealmName = function() return nil end")
uses = L.eval("dgks.UsesSurnames and dgks.UsesSurnames()")
recs = kill(units="{ target = { name = 'Chain', realm = 'Lightning', player = true, enemy = true, level = 60 } }")
if uses:
    check("Forever: the victim's first and last name", len(recs) == 1 and recs[0]["o"].startswith("Chain Lightning"), recs)
L.execute("RegionalUniqueNamesEnabled = nil; GetNormalizedRealmName = function() return 'Realm' end")

# Outside a battleground nothing happens (dungeons hide PARTY_KILL too)
L.execute("INSTANCE = 'party'")
recs = kill(units=ENEMY)
check("in a dungeon: nothing recorded", recs == [], recs)
L.execute("INSTANCE = 'arena'")
recs = kill(units=ENEMY)
check("in an arena (not probed): nothing recorded", recs == [], recs)

# Zoning in again resets the count; a statistic that cannot be read means no records, no errors
L.execute("INSTANCE = 'pvp'; FIRE('ZONE_CHANGED_NEW_AREA')")
recs = kill(units=ENEMY)
check("after zoning in again, kills are found", len(recs) == 1, recs)
L.execute("GetStatistic = function() return SECRET end; FIRE('ZONE_CHANGED_NEW_AREA')")
recs = kill(units=ENEMY)
recs += kill(units=ENEMY)
check("statistics hidden: nothing recorded, no error", recs == [] and not any("failed" in str(p) for p in L.eval("PRINTS").values()),
      (recs, [p for p in L.eval("PRINTS").values() if "failed" in str(p)]))

# A visible PARTY_KILL still goes the usual way (not through the statistics)
L.execute("GetStatistic = function() error('should not be read') end")
L.execute("RECORDS = {}; dgks.TargetCheck = function() return true end")
L.execute("FIRE('PARTY_KILL', 'Player-1-ME', 'Player-2-ZED'); RUN_TIMERS()")
check("a visible PARTY_KILL of ours is recorded as before, not as likely",
      len(L.eval("RECORDS")) == 1 and L.eval("RECORDS[1].flags") is None)

print("FAILS:", fails)
sys.exit(1 if fails else 0)
