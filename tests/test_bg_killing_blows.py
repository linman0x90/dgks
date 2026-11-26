"""Killing blows in battlegrounds and arenas, where PARTY_KILL's GUIDs are secret (#35).

The statistic "Total Killing Blows" (achievement criteria 1487) still goes up with each of our killing
blows, so a hidden PARTY_KILL that comes with it going up was ours. The victim is our target if it
died at that moment (marked likely), otherwise unknown.

dgks.lua runs in a Lua 5.1 sandbox with stand-ins for the game API (retail path). Needs Python 3 and
lupa (pip install lupa). Run from anywhere:

    python tests/test_bg_killing_blows.py

Exits with 1 if any check fails.
"""
import os
import sys
from lupa import lua51

from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)
HERE = os.path.dirname(os.path.abspath(__file__))
exec(open(HERE + "/test_death.py").read().split("fails = 0")[0])  # make(): dgks.lua with retail stubs

fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)


L = make()
L.execute(r'''
KB = 10
GetAchievementCriteriaInfoByID = function(id, i)
  if id ~= 1487 then return nil end
  return "Total Killing Blows", 0, false, KB, 0, "", 0, 0, tostring(KB), 0, true, 0, 0
end
GetPlayerInfoByGUID = function(g) if g == 'Player-2-ZED' then return "Mage", "MAGE", "Human", "Human", 2, "Zed", "Other" end return "Warrior", "WARRIOR", "Human", "Human", 2, "Me", "Realm" end
dgks.TargetCheck = function() return true end
function dgks:ProcessKillshot() end
function dgks:SendCM() end
function dgks:Serialize() return "x" end
dgks.db.profile.kstextM = { "a", "b" }
''')


def enter(instance_type):
    L.execute(f"IsInInstance = function() return {'true' if instance_type != 'none' else 'false'}, '{instance_type}' end")
    L.execute("FIRE('PLAYER_ENTERING_WORLD')")


def kills(code):
    """Run code, then every pending timer; return the kills recorded as (victim, flags)."""
    L.execute("RECORDS = {}; NOW = NOW + 30")
    L.execute(code)
    L.execute("RUN_TIMERS()")
    out = []
    for r in L.eval("RECORDS").values():
        if r["k"] == "K":
            f = r["flags"]
            out.append((r["o"], dict(f.items()) if f else None))
    return out


TARGET_DIES = "UNITS = { target = { name = 'Zed', realm = 'Other', player = true } }; FIRE('PLAYER_TARGET_DIED')"
HIDDEN = "FIRE('PARTY_KILL', SECRET, SECRET)"

enter("pvp")
r = kills(f"{TARGET_DIES}; KB = KB + 1; {HIDDEN}")
check("battleground: our hidden killing blow on our dying target: a likely kill of Zed", r == [("Zed-Other", {"guessed": 1})], r)
r = kills(f"KB = KB + 1; {HIDDEN}; {TARGET_DIES}")
check("battleground: target's death reported just after the PARTY_KILL: still named", r == [("Zed-Other", {"guessed": 1})], r)
r = kills(f"UNITS = {{ target = {{ name = SECRET, player = true }} }}; FIRE('PLAYER_TARGET_DIED'); KB = KB + 1; {HIDDEN}")
check("battleground: target's name hidden (retail 12.0.5+): a kill of an unknown enemy", r == [("an enemy player", {"unknown": True})], r)
r = kills(HIDDEN)
check("battleground: a teammate's kill (count unchanged): nothing", r == [], r)
r = kills(f"{HIDDEN}; KB = KB + 1")
check("battleground: the count goes up just after the event: still ours", len(r) == 1, r)
r = kills(f"KB = KB + 1; {HIDDEN}")
check("battleground: no target died: a kill of an unknown enemy", r == [("an enemy player", {"unknown": True})], r)
r = kills(f"{TARGET_DIES}; NOW = NOW + 5; KB = KB + 1; {HIDDEN}")
check("battleground: target died seconds earlier: not taken as the victim", r == [("an enemy player", {"unknown": True})], r)
r = kills(f"KB = KB + 2; {HIDDEN}; {HIDDEN}")
check("battleground: two killing blows at once: two kills", len(r) == 2, r)

enter("arena")
r = kills(f"{TARGET_DIES}; KB = KB + 1; {HIDDEN}")
check("arena: works the same", r == [("Zed-Other", {"guessed": 1})], r)

enter("none")
r = kills(f"KB = KB + 1; {HIDDEN}")
check("outside battlegrounds and arenas: a hidden PARTY_KILL is not taken", r == [], r)
L.execute("KB = KB + 3")  # world PvP killing blows
enter("pvp")
r = kills(HIDDEN)
check("killing blows outside don't count as ours on entering a battleground", r == [], r)

r = kills("KB = KB + 1; FIRE('PARTY_KILL', 'Player-1-ME', 'Player-2-ZED')")
check("battleground: a readable killing blow is handled as before", r == [("Zed", None)], r)
r = kills(HIDDEN)
check("... and isn't taken again by the next hidden PARTY_KILL", r == [], r)

L.execute("GetAchievementCriteriaInfoByID = function() return nil, nil, nil, SECRET end")
r = kills(f"KB = KB + 1; {HIDDEN}")
check("the count hidden too: nothing (as before)", r == [], r)

print("FAILS:", fails)
sys.exit(1 if fails else 0)
