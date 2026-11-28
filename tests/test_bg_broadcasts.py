"""Ignoring guild members' killshots from battlegrounds we are not in (Settings > Broadcasts).

A guild broadcast is dropped when the option is on, the guild roster shows the sender in a
battleground zone, and the sender is not in our group (in a battleground together, they are in the
battleground's raid). Other broadcasts, other zones and unknown senders pass. Runs dgks.lua with
stand-ins for the game and the Ace libraries.

Needs Python 3 and lupa (pip install lupa). Run from anywhere:

    python tests/test_bg_broadcasts.py

Exits with 1 if any check fails.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# The options test's setup: dgks.lua loaded and initialised with stand-in Ace libraries
setup = open(os.path.join(HERE, "test_options.py"), encoding="utf-8").read().split("reg = L.eval")[0]
exec(setup)

fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra if not cond else "")


REG = L.eval("REGISTERED")
validate = L.eval("function(name) local t = REGISTERED[name]() local ok, err = pcall(REAL_REG.ValidateOptionsTable, REAL_REG, t, name) return ok, err, t end")
ok, err, settings = validate("dG KillShot Settings")
check("the settings still validate", ok, err)
bc = settings["args"]["broadcasts"]["args"]
opt = bc["ignoreOtherBGs"]
check("the option sits right under Broadcasts to/from Guild",
      opt["type"] == "toggle" and bc["doguild"]["order"] < opt["order"] < bc["doraid"]["order"], opt["order"])
check("off by default", L.eval("dgks.db.profile.ignoreOtherBGs") is False)
L.execute("dgks.db.profile.doguild = false")
check("greyed out when guild broadcasts are off", opt["disabled"]() is True)
L.execute("dgks.db.profile.doguild = true")
check("available when guild broadcasts are on", opt["disabled"]() is False)
opt["set"](None, True)
check("the toggle sets the option", L.eval("dgks.db.profile.ignoreOtherBGs") is True)

L.execute(r'''
issecretvalue = function(v) return v == SECRET end
SECRET = setmetatable({}, {})
time = os.time
SHOWN = {}
function dgks:ProcessKillshot(chan, killer) SHOWN[#SHOWN+1] = chan .. ":" .. killer end
function dgks:Deserialize(m) return true, m, "Zed", 1, 1, 0 end
ROSTER = {
  { "Bob-Realm", "Alterac Valley" }, { "Cara-Realm", "Ironforge" }, { "Dan-Realm", "Warsong Gulch" },
  { "Pink Tonic", "Alterac Valley" }, { "Eve-Realm", SECRET }, { "Hans-Realm", "Alteractal" },
}
IsInGuild = function() return true end
GetNumGuildMembers = function() return #ROSTER end
GetGuildRosterInfo = function(i) local m = ROSTER[i] return m[1], "Member", 1, 60, "Rogue", m[2] end
RAID = { Dan = 3 }
UnitInRaid = function(n) return RAID[n] end
UnitInParty = function() return false end
''')
recv = L.eval("function(chan, sender, dist) dgks:OnCommReceived(chan, sender, dist or 'GUILD', sender) end")


def shown(chan, sender, dist="GUILD"):
    L.execute("SHOWN = {}")
    recv(chan, sender, dist)
    return len(L.eval("SHOWN")) == 1


check("a guild member in a battleground we are not in: ignored", not shown("dgks", "Bob-Realm"))
check("their duel results too", not shown("dgksDUEL", "Bob-Realm"))
check("sender without the realm still found in the roster", not shown("dgks", "Bob"))
check("Forever names: first and last name", not shown("dgks", "Pink Tonic"))
check("a guild member out in the world: shown", shown("dgks", "Cara-Realm"))
check("a guild member in our battleground (in our raid): shown", shown("dgks", "Dan-Realm"))
check("a member the roster does not list: shown", shown("dgks", "Stranger-Realm"))
check("a hidden roster zone: shown", shown("dgks", "Eve-Realm"))
check("the same member through the raid or battleground channel: shown",
      shown("dgks", "Bob-Realm", "RAID") and shown("dgks", "Bob-Realm", "INSTANCE_CHAT"))

# The game's own battleground names (localized) count too
L.execute("GetNumBattlegroundTypes = function() return 1 end; GetBattlegroundInfo = function() return 'Alteractal' end")
check("a battleground the game names in another language: ignored", not shown("dgks", "Hans-Realm"))

L.execute("dgks.db.profile.ignoreOtherBGs = false")
check("option off: everything is shown, as before", shown("dgks", "Bob-Realm") and shown("dgksDUEL", "Pink Tonic"))

# The game blocks addon messages in battlegrounds: no sends, and the version check says why
L.execute(r"""
SENTCM = {}
function dgks:SendCommMessage(prefix, text, dist) SENTCM[#SENTCM+1] = prefix .. ":" .. dist end
function dgks:RefreshSettings() end
dgks.db.profile.dobroadcasts = true; dgks.db.profile.doguild = true
dgks.db.profile.doraid = false; dgks.db.profile.dofriends = false; dgks.db.profile.dobg = false
LOCKED = true
C_ChatInfo = { InChatMessagingLockdown = function() return LOCKED end }
""")
L.execute("dgks:SendCM('dgks', 'x')")
check("messages blocked: a killshot is not sent", len(L.eval("SENTCM")) == 0)
L.execute("dgks:VersionCheck()")
text = L.eval("dgks:VersionCheckText()")
check("messages blocked: the version check asks no one and says why",
      len(L.eval("SENTCM")) == 0 and "blocks addon messages here" in text and "Waiting" not in text, text)
L.execute("LOCKED = false; dgks:SendCM('dgks', 'x')")
check("not blocked: sent as before", list(L.eval("SENTCM").values()) == ["dgks:GUILD"], list(L.eval("SENTCM").values()))
L.execute("SENTCM = {}; dgks:VersionCheck()")
check("not blocked: the version check goes out and waits for replies",
      list(L.eval("SENTCM").values()) == ["dgksV:GUILD"] and "Waiting for replies" in L.eval("dgks:VersionCheckText()"))
L.execute("SENTCM = {}; C_ChatInfo = nil; dgks:SendCM('dgks', 'x')")
check("a client without the lockdown API sends as before", len(L.eval("SENTCM")) == 1)
L.execute("SENTCM = {}; C_ChatInfo = { InChatMessagingLockdown = function() return SECRET end }; dgks:SendCM('dgks', 'x')")
check("a hidden answer counts as not blocked", len(L.eval("SENTCM")) == 1)
desc = bc["dobg"]["desc"]
check("the Battleground option says the game blocks messages there", "blocks addon messages inside battlegrounds" in desc, desc)

print("FAILS:", fails)
sys.exit(1 if fails else 0)
