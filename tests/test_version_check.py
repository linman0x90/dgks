"""Version check: one reply per player per check, and none to ourselves.

A check goes out to the guild, the group and friends, and our own copy comes back on the guild and
group channels. Players who share several channels with us hear it several times, seconds apart.

dgks.lua runs in a Lua 5.1 sandbox with stand-ins for the game API. Needs Python 3 and lupa
(pip install lupa). Run from anywhere:

    python tests/test_version_check.py

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
CLOCK = 1790000000
time = function() return CLOCK end
REPLIES = {}
function dgks:SendCommMessage(prefix, msg, dist, target)
  if prefix == "dgksVR" then REPLIES[#REPLIES+1] = target end
end
function dgks:Deserialize() return false end
local p = dgks.db.profile
p.dobroadcasts, p.doguild, p.doraid, p.dobg = true, true, true, true
''')


def hear(sender, dist, after=0, cchan="dgksV"):
    L.execute(f"CLOCK = CLOCK + {after}")
    L.eval("function(c, s, d) dgks:OnCommReceived(c, '12.0.014', d, s) end")(cchan, sender, dist)


def replies():
    return list(L.eval("REPLIES").values())


hear("Me", "GUILD")
hear("Me", "PARTY")
check("our own check coming back is not answered", replies() == [], replies())

hear("Amy", "GUILD", after=5)
hear("Amy", "PARTY", after=1)
hear("Amy", "WHISPER", after=1)
check("one check heard on guild, party and whisper: one reply", replies() == ["Amy"], replies())

hear("Bob", "GUILD", after=1)
hear("Zed", "GUILD", cchan="dgks")  # a kill message in between
hear("Bob", "PARTY")
check("a kill message in between doesn't cause a second reply", replies() == ["Amy", "Bob"], replies())

hear("Cy-Otherrealm", "GUILD", after=1)
hear("cy-otherrealm", "WHISPER")
check("the same player, written in another case: one reply", replies() == ["Amy", "Bob", "Cy-Otherrealm"], replies())

hear("Amy", "GUILD", after=60)
check("a new check a minute later is answered", replies() == ["Amy", "Bob", "Cy-Otherrealm", "Amy"], replies())

L.execute("dgks.db.profile.dobroadcasts = false")
hear("Dee", "GUILD", after=60)
check("not answered with broadcasts off", "Dee" not in replies(), replies())

print("FAILS:", fails)
sys.exit(1 if fails else 0)
