"""The "killed N times" chat lines count from personal history, and the old kill/death lists are gone.

Drives dgks.lua's kill, death and duel handlers with the real dgks_history.lua, and checks:
- kills, deaths, duel wins and duel losses are counted separately (a duel loss is not a death)
- the count includes the event just recorded, and finds a victim whose realm came from the GUID
- an NPC that history doesn't keep gets a line without a count
- killList, deathList and killlog are not written

Needs Python 3 and lupa (pip install lupa). Run from anywhere:

    python tests/test_chat_counts.py

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
time = function(t) if t then return os.time(t) end return 1790000000 + NOW end
IsInGuild = function() return false end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitLevel = function() return 80 end
GetSubZoneText = function() return "" end
GetPlayerInfoByGUID = function(g)
  if g == 'Player-2-ZED' then return "Mage", "MAGE", "Human", "Human", 2, "Zed", "Other" end
  return "Warrior", "WARRIOR", "Human", "Human", 2, "Me", "Realm"
end
dgks.Players.Lookup = function() return nil end
dgks.Players.MySpec = function() return nil end
dgks.TargetCheck = function() return true end
function dgks:RegisterComm() end
function dgks:EmoteAt() end
function dgks:ScrollText() end
function dgks:dgks_SoundPack() end
function dgks:GetKillshotSound() end
function dgks:SoundEventHandler() end
function dgks:SendCM() end
function dgks:Serialize() return "x" end
local p = dgks.db.profile
p.killList, p.deathList, p.killlog = nil, nil, nil
for k, v in pairs({ kstextS = {}, kstext = "$k killed $v", kstextM = { "x" }, doemote = "none", dotxtemote = false,
  dueltext = "$k beat $v", dueltxtemote = false, duelemotewin = "none", duelemoteloss = "none",
  doscreenshotonduelloss = false, dobroadcasts = false, historyShare = false, historyPve = false }) do p[k] = v end
dgks.db.global = { history = { guilds = {} } }
dgks.db.char = { history = { records = {} } }
''')
L.execute(src("dgks_history.lua"))
L.execute("dgks.History:Initialize()")


def lines(code):
    L.execute("PRINTS = {}")
    L.execute(code)
    L.execute("RUN_TIMERS()")
    return [m for m in L.eval("PRINTS").values() if m.startswith("You ")]


def advance():
    L.execute("NOW = NOW + 10")


r = lines("dgks:PlayerDeath('Zed-Other', nil, 'Player-2-ZED')")
check("first death: once", r == ["You have been killed by Zed-Other once."], r)
advance()
r = lines("dgks:PlayerDeath('Zed-Other', nil, 'Player-2-ZED')")
check("second death: 2 times", r == ["You have been killed by Zed-Other 2 times."], r)
advance()
r = lines("dgks:PlayerLoss('Zed-Other')")
check("a duel loss is counted on its own", r == ["You have been defeated by Zed-Other once."], r)
advance()
r = lines("dgks:PlayerDeath('Zed-Other', nil, 'Player-2-ZED')")
check("the duel loss is not a death: 3 times", r == ["You have been killed by Zed-Other 3 times."], r)

advance()
r = lines("dgks:KillshotTX('Zed', NOW, 'Player-2-ZED')")
check("kill by bare name, realm from the GUID: once", r == ["You have killed Zed once."], r)
advance()
r = lines("dgks:KillshotTX('Zed', NOW, 'Player-2-ZED')")
check("second kill: 2 times", r == ["You have killed Zed 2 times."], r)
advance()
r = lines("dgks:DuelTX('Zed-Other', NOW)")
check("a duel win is counted on its own", r == ["You have beaten Zed-Other once."], r)

advance()
r = lines("dgks:KillshotTX('Boar', NOW, 'Creature-0-1-2-3-4-5')")
check("an NPC history doesn't keep: no count", r == ["You have killed Boar."], r)

kinds = [rec["k"] for rec in L.eval("dgks.History:PersonalRecords()").values()]
check("history holds 3 deaths, 1 duel loss, 2 kills, 1 duel win", sorted(kinds) == sorted("DDLDKKW"), kinds)
check("killList, deathList and killlog are not written",
      L.eval("dgks.db.profile.killList == nil and dgks.db.profile.deathList == nil and dgks.db.profile.killlog == nil") is True)

print("FAILS:", fails)
sys.exit(1 if fails else 0)
