"""Version check: one reply per player per check, none to ourselves, and a chat note when a check
or a reply shows a newer version than ours.

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
HERE = os.path.dirname(os.path.abspath(__file__))
exec(open(HERE + "/test_death.py").read().split("fails = 0")[0])  # make(): dgks.lua with retail stubs

# Run dgks.lua as the packager builds a release: version 12.0.014, and the @debug@ blocks cut out (a
# development copy shows "@project-version@", which can't tell newer from older). This replaces the
# src that test_death.py set up, before make() loads the addon.
import re
import names_prelude
src = names_prelude.wrap(
    lambda f: re.sub(r"--@debug@.*?--@end-debug@", "", open(f"{REPO}/{f}", encoding="utf-8").read(),
                     flags=re.S).replace("@project-version@", "12.0.014"),
    REPO)

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
PRINTED = {}
function dgks:Print(...) PRINTED[#PRINTED+1] = table.concat({...}, " ") end
function dgks:SendCommMessage(prefix, msg, dist, target)
  if prefix == "dgksVR" then REPLIES[#REPLIES+1] = target end
end
function dgks:Deserialize() return false end
local p = dgks.db.profile
p.dobroadcasts, p.doguild, p.doraid, p.dobg = true, true, true, true
''')


def hear(sender, dist, after=0, cchan="dgksV", msg="12.0.014"):
    L.execute(f"CLOCK = CLOCK + {after}")
    L.eval("function(c, s, d, m) dgks:OnCommReceived(c, m, d, s) end")(cchan, sender, dist, msg)


def printed():
    return list(L.eval("PRINTED").values())


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

# The newer-version note: in chat, once per session, only for a newer version
hear("Eve", "GUILD", after=60, msg="12.0.014")
hear("Eve", "GUILD", after=60, msg="12.0.010")
hear("Eve", "GUILD", cchan="dgksVR", msg="hello")
hear("Eve", "GUILD", cchan="dgksVR", msg="12.0.9")
check("the same or an older version, or anything unreadable: no note", printed() == [], printed())

hear("Me", "GUILD", after=60, msg="12.0.099")
check("our own check coming back: no note", printed() == [], printed())

hear("Fay", "GUILD", after=60, msg="12.0.017")
check("a check from a newer version: one note naming both versions",
      len(printed()) == 1 and "12.0.017" in printed()[0] and "12.0.014" in printed()[0], printed())

hear("Gus", "GUILD", after=60, msg="12.0.017")
hear("Gus", "GUILD", cchan="dgksVR", msg="12.0.016")
hear("Gus", "GUILD", cchan="dgksVR", msg="12.0.017")
check("the same or an older newer version: no second note", len(printed()) == 1, printed())

hear("Hal", "GUILD", cchan="dgksVR", msg="12.0.018")
check("a reply with a still newer version: a second note", len(printed()) == 2 and "12.0.018" in printed()[1], printed())

hear("Ivy", "GUILD", after=60, msg="12.0.019 |cffff0000click here|r")
check("only the version itself reaches the chat",
      len(printed()) == 3 and "12.0.019" in printed()[2] and "click" not in printed()[2], printed())

hear("Jo", "GUILD", after=60, msg=L.eval("SECRET"))
hear("Jo", "GUILD", cchan="dgksVR", msg=L.eval("SECRET"))
check("a secret value is ignored", len(printed()) == 3, printed())

L.execute("dgks.db.profile.dobroadcasts = false")
hear("Dee", "GUILD", after=60)
check("not answered with broadcasts off", "Dee" not in replies(), replies())

print("FAILS:", fails)
sys.exit(1 if fails else 0)
