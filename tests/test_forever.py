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


def die(L, setup):
    L.execute("RECORDS, PRINTS, TIMERS = {}, {}, {}")
    L.execute(setup)
    L.execute("FIRE('PLAYER_DEAD'); RUN_TIMERS()")
    recs = list(L.eval("RECORDS").values())
    if not recs:
        return None
    r = recs[0]
    return (r["o"], dict(r["flags"].items()) if r["flags"] else None, r["guid"])


# ---------- The helper ----------
L = make()
split = lambda a, b: tuple(L.eval("function(a, b) return dgks.SplitName(a, b) end")(a, b) or (None,))
check("retail: name and realm unchanged", L.eval("dgks.UsesSurnames()") is False and split("Ann", "Realm") == ("Ann", "Realm"))
check("retail: empty realm -> nil", split("Ann", "") == ("Ann", None))
L.execute("RegionalUniqueNamesEnabled = function() return true end")
check("Forever: surname joined with a space, no realm", L.eval("dgks.UsesSurnames()") is True and split("Ann", "Smith") == ("Ann Smith", None), split("Ann", "Smith"))
check("Forever: already full name not doubled", split("Ann Smith", "Smith") == ("Ann Smith", None))
check("Forever: no surname -> first name", split("Ann", "") == ("Ann", None) and split("Ann", None) == ("Ann", None))
check("secret or missing name -> nil", split(None, "x") == (None,) and L.eval("dgks.SplitName(SECRET, 'x')") is None)
L.execute("Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = '_' } }")
check("Forever: uses the game's separator constant", split("Ann", "Smith") == ("Ann_Smith", None))
L.execute("Constants = nil")

# ---------- dgks.lua on Forever ----------
L = make()
L.execute(r'''
RegionalUniqueNamesEnabled = function() return true end
UnitName = function(u) if u == "player" then return "Me", "Smith" end end
GUIDS = { ["Player-1-ME"] = { "Me", "Smith" }, ["Player-2-ZED"] = { "Zed", "Stone" }, ["Player-3-BOB"] = { "Bob", "Brown" } }
GetPlayerInfoByGUID = function(g) local i = GUIDS[g] if i then return "Warrior", "WARRIOR", "Human", "Human", 2, i[1], i[2] end end
dgks:OnEnable()
SENT = {}
function dgks:KillshotTX(v) SENT[#SENT+1] = v end
dgks.TargetCheck = function() return true end
''')
check("own name is First Surname; own messages recognised with or without surname",
      L.eval("dgks:IsOwnSender('Me Smith')") and L.eval("dgks:IsOwnSender('Me')") and not L.eval("dgks:IsOwnSender('Zed Stone')"))
L.execute("FIRE('PARTY_KILL', 'Player-1-ME', 'Player-2-ZED')")
check("kill broadcast names the victim First Surname", list(L.eval("SENT").values()) == ["Zed Stone"], list(L.eval("SENT").values()))

r = die(L, "RECAP = { { sourceName = SECRET } }; UNITS = { nameplate1 = { player = true, enemy = true, targetsMe = true, name = 'Ann', realm = 'Smith', guid = 'Player-4-ANN' } }")
check("likely killer is First Surname on our realm, not First-Surname", r and r[0] == "Ann Smith-Realm", r)

# Forever's normalized realm name can be empty: the realm then comes from GetRealmName, never ""
GUESS = "RECAP = { { sourceName = SECRET } }; UNITS = { nameplate1 = { player = true, enemy = true, targetsMe = true, name = 'Ann', realm = 'Smith', guid = 'Player-4-ANN' } }"
L.execute("GetNormalizedRealmName = function() return '' end; GetRealmName = function() return 'CAMWOW US2-Realm' end")
check("RealmName falls back to GetRealmName, normalized", L.eval("dgks.RealmName()") == "CAMWOWUS2Realm", L.eval("dgks.RealmName()"))
r = die(L, GUESS)
check("empty normalized realm: likely killer gets the realm from GetRealmName, no bare dash", r and r[0] == "Ann Smith-CAMWOWUS2Realm", r)
L.execute("GetRealmName = function() return '' end")
check("no realm at all: RealmName is nil, not ''", L.eval("dgks.RealmName()") is None)
r = die(L, GUESS)
check("no realm at all: likely killer is the bare name", r and r[0] == "Ann Smith", r)
L.execute("GetNormalizedRealmName = function() return 'Realm' end; GetRealmName = nil")

# Duel messages with full or first-only names
L.execute(r'''
DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
DUEL_COUNTDOWN = "Duel starting: %d"
format = function(f, ...) local a = { ... } return (f:gsub("%%(%d)%$s", function(i) return a[tonumber(i)] end)) end
strmatch = string.match
DUELS = {}
function dgks:DuelTX(o) DUELS[#DUELS+1] = "won:" .. o end
function dgks:PlayerLoss(o) DUELS[#DUELS+1] = "lost:" .. o end
dgks.db.profile.duelhumiliation = false
local ev = FRAME.events
''')
L.execute("FRAME.OnEvent(FRAME, 'CHAT_MSG_SYSTEM', 'Me Smith has defeated Zed Stone in a duel')")
L.execute("FRAME.OnEvent(FRAME, 'CHAT_MSG_SYSTEM', 'Zed Stone has defeated Me Smith in a duel')")
L.execute("FRAME.OnEvent(FRAME, 'CHAT_MSG_SYSTEM', 'Me has defeated Bob in a duel')")
duels = list(L.eval("DUELS").values())
check("duel results matched with full and first-only names", duels == ["won:Zed Stone", "lost:Zed Stone", "won:Bob"], duels)

# ---------- History, players, tooltip on Forever ----------
H = lua51.LuaRuntime(unpack_returned_tuples=True)
H.execute(r'''
issecretvalue = function() return false end
RegionalUniqueNamesEnabled = function() return true end
NOW = 1790000000
time = function(t) if t then return os.time(t) end return NOW end
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
GetNormalizedRealmName = function() return "Realm" end
UnitName = function(u) if u == "player" then return "Me", "Smith" end end
IsInGuild = function() return false end
C_Timer = { After = function(_, fn) fn() end }
GUIDS = { ["Player-2-ZED"] = { "MAGE", "Zed", "Stone" }, ["Player-3-BOB"] = { "PALADIN", "Bob", "Brown" } }
GetPlayerInfoByGUID = function(g) local i = GUIDS[g] if i then return "x", i[1], "x", "Human", 2, i[2], i[3] end end
UnitGUID = function(u) if u == "player" then return "Player-1-ME" end return UNIT_GUID end
UnitLevel = function() return 80 end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitRace = function() return "Human", "Human" end
GetRealZoneText = function() return "Arathi" end
GetSubZoneText = function() return "" end
IsInInstance = function() return false, "none" end
dgks = { db = { profile = { historyShare = true, historyRetentionDays = 90, historyTooltip = true, recordTeamKills = true, inspectSpecs = false },
  global = { history = { guilds = {} } }, char = { history = { records = {} } } } }
function dgks:Print(m) print("PRINT", m) end
''')
H.execute(src("dgks_history.lua"))
H.execute(src("dgks_players.lua"))
H.execute(src("dgks_history_ui.lua"))
H.execute("dgks.History:UpdateIdentity()")
H.execute("dgks.History:Record('K', 'Zed', 'Player-2-ZED', 1, 0)")
H.execute("dgks.History:RecordTeamKill('Player-3-BOB', 'Player-2-ZED')")
recs = list(H.eval("dgks.History:PersonalRecords()").values())
check("history author is First Surname", recs[0]["a"] == "Me Smith-Realm", recs[0]["a"])
check("opponent from GUID stored as First Surname", recs[0]["o"] == "Zed Stone-Realm", recs[0]["o"])
check("team kill: victim and killer both First Surname", recs[1]["o"] == "Zed Stone-Realm" and recs[1]["kn"] == "Bob Brown-Realm", (recs[1]["o"], recs[1]["kn"]))
check("shown without our realm: Zed Stone", H.eval("dgks.History.ShortName('Zed Stone-Realm')") == "Zed Stone")

# Player cache from a unit
H.execute(r'''
UNIT = { exists = true, player = true, name = "Ann", second = "Smith", class = "ROGUE" }
UnitExists = function() return UNIT.exists end
UnitIsPlayer = function() return UNIT.player end
UnitFullName = function() return UNIT.name, UNIT.second end
UnitClass = function() return "Rogue", UNIT.class end
UnitRace = function() return "Human", "Human" end
UnitCanAttack = function() return false end
UNIT_GUID = "Player-5-ANN"
dgks.Players:Note("target")
''')
info = H.eval("dgks.Players:Lookup('Ann Smith')")
check("player cache keys the unit as First Surname", info is not None and info["class"] == "ROGUE" and info["guid"] == "Player-5-ANN")
check("player cache does not treat the surname as a realm", H.eval("dgks.Players:Lookup('Ann-Smith')") is None)

# Tooltip counts for a unit with a surname
H.execute("dgks.History:Record('K', 'Ann Smith', nil, 1, 0)")
H.execute(r'''
UnitIsUnit = function() return false end
LINES = {}
local tt = { AddDoubleLine = function(_, l, r) LINES[#LINES+1] = l .. " | " .. r end }
GameTooltip = tt
''')
mine, _ = H.eval("dgks.History:CountsFor(dgks.History.PlayerKey('Ann Smith'))")
check("tooltip counts found for First Surname", mine["K"] == 1)

# Window subtitle uses the full name
check("PlayerFullName (window subtitle)", H.eval("(dgks.PlayerFullName())") == "Me Smith")

# Names saved with an empty realm ("Zed Stone-") by earlier versions
check("display drops a bare trailing dash", H.eval("dgks.History.ShortName('Zed Stone-')") == "Zed Stone")
check("tooltip/opponent key treats 'Zed Stone-' as 'Zed Stone'",
      H.eval("dgks.History.PlayerKey('Zed Stone-')") == H.eval("dgks.History.PlayerKey('Zed Stone')") == "Zed Stone-Realm")
check("FullName drops a bare trailing dash", H.eval("dgks.History.FullName('Zed Stone-')") == "Zed Stone-Realm")
H.execute(r'''
local recs = dgks.db.char.history.records
recs[#recs+1] = { k = "D", t = NOW, o = "Zed Stone-", a = "Me Smith-Realm", g = 1 }
recs[#recs+1] = { k = "X", t = NOW, o = "Bob Brown-Far", kn = "Ann Smith-", a = "Me Smith-Realm" }
recs[#recs+1] = { k = "K", t = NOW, o = "Ann Smith-Other", a = "Me Smith-Realm" }
dgks.db.global.history.guilds["G-Realm"] = { streams = { ["Bo Reed-Elsewhere#1"] = { h = 1, r = { { k = "D", t = NOW, o = "Zed Stone-", a = "Bo Reed-Elsewhere", e = 1, s = 1 } } } } }
dgks.History:RepairEmptyRealms()
''')
n = H.eval("#dgks.db.char.history.records")
rec = lambda i: H.eval(f"dgks.db.char.history.records[{i}]")
check("repair: personal death gets our realm", rec(n - 2)["o"] == "Zed Stone-Realm", rec(n - 2)["o"])
check("repair: team kill killer gets our realm, victim untouched", rec(n - 1)["kn"] == "Ann Smith-Realm" and rec(n - 1)["o"] == "Bob Brown-Far")
check("repair: names with a realm untouched", rec(n)["o"] == "Ann Smith-Other")
g = H.eval("dgks.db.global.history.guilds['G-Realm'].streams['Bo Reed-Elsewhere#1'].r[1]")
check("repair: guild record gets its author's realm, author unchanged", g["o"] == "Zed Stone-Elsewhere" and g["a"] == "Bo Reed-Elsewhere", g["o"])
print("FAILS:", fails)
sys.exit(1 if fails else 0)
