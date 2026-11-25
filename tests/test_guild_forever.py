"""Guild history on WoW Forever: merging the stores older versions saved, reading our own name late,
and listing members recorded by first name only ("Pink" for "Pink Tonic").

dgks_history.lua runs in a Lua 5.1 sandbox with stand-ins for the game API. Needs Python 3 and lupa
(pip install lupa). Run from anywhere:

    python tests/test_guild_forever.py

Exits with 1 if any check fails.
"""
import sys
from lupa import lua51

from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)

fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra if not cond else "")


STUBS = r'''
issecretvalue = function() return false end
RegionalUniqueNamesEnabled = function() return true end
UNKNOWNOBJECT = "Unknown"
NOW = 1790000000
time = function(t) if t then return os.time(t) end return NOW end
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
GetNormalizedRealmName = function() return nil end  -- Forever has no realm
PLAYER = { "Me", "Smith" }
UnitName = function(u) if u == "player" then return PLAYER[1], PLAYER[2] end end
IsInGuild = function() return true end
GetGuildInfo = function() return "G", "Member", 1, nil end
ROSTER = {}
GetNumGuildMembers = function() return #ROSTER end
GetGuildRosterInfo = function(i) local m = ROSTER[i] return m[1], "", 1, 80, "", "", "", "", true, 0, m[2] end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() end }
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
UnitGUID = function() return nil end
UnitLevel = function() return 80 end
UnitClass = function() return "Warrior", "WARRIOR" end
GetRealZoneText = function() return "Arathi" end
GetSubZoneText = function() return "" end
IsInInstance = function() return false, "none" end
dgks = { db = { profile = { historyShare = true, historyRetentionDays = 90 },
  global = { history = { guilds = {} } }, char = { history = { records = {} } } } }
LibStub("AceSerializer-3.0"):Embed(dgks)
function dgks:Print(m) print("PRINT", m) end
function dgks:RegisterComm() end
SENT = {}
function dgks:SendCommMessage(prefix, msg, dist, target) SENT[#SENT+1] = dist end
'''


def runtime(setup=""):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.execute(src("libs/LibStub/LibStub.lua"))
    L.execute(src("libs/AceSerializer-3.0/AceSerializer-3.0.lua"))
    L.execute(STUBS)
    L.execute(setup)
    L.execute(src("dgks_history.lua"))
    return L


def stream(L, key, guild="G-Unknown"):
    return L.eval(f"(dgks.db.global.history.guilds['{guild}'] or {{ streams = {{}} }}).streams['{key}']")


# ---------- 1. Merging the store saved under "G-" by versions before 12.0.010 ----------
L = runtime(r'''
local function rec(s, t) return { a = "Ann Smith-", e = 1, s = s, t = t, k = "K", o = "Zed Stone-" } end
dgks.db.global.history.guilds["G-"] = { streams = { ["Ann Smith-#1"] = { h = 5, r = {
  [2] = rec(2, NOW - 200 * 86400),                       -- past the 90-day retention
  [3] = rec(3, NOW), [4] = rec(4, NOW),
  [5] = { a = "Ann Smith-", e = 1, s = 5, t = NOW, k = "K", o = "" },  -- not valid: empty opponent
} } } }
''')
L.execute("dgks.History:UpdateIdentity(); dgks.History:UpdateGuild()")
st = stream(L, "Ann Smith-#1")
have = sorted(st["r"].keys()) if st else []
check("valid records moved to the current store", have == [3, 4], have)
check("head kept up to the last record merged", st and st["h"] == 4, st and st["h"])
old = stream(L, "Ann Smith-#1", "G-")
left = sorted(old["r"].keys()) if old else []
check("an invalid record stays in the old store instead of being lost", left == [5], left)
check("records past retention are not copied", st and st["r"][2] is None)
L.execute("dgks.db.global.history.guilds['G-'].streams['Ann Smith-#1'].r[5].o = 'Zed Stone-'")
L.execute("dgks.History:UpdateGuild()")
check("once everything has merged, the old store is removed", L.eval("dgks.db.global.history.guilds['G-']") is None)
check("and the last record arrives", sorted(stream(L, "Ann Smith-#1")["r"].keys()) == [3, 4, 5])

# ---------- 2. Our own name not readable at login ----------
L = runtime("PLAYER = { 'Unknown', nil }")
L.execute("dgks.History:Initialize(); dgks.History:UpdateGuild()")
check("guild key set even before our name is known", L.eval("dgks.History:GuildKey()") == "G-Unknown")
recv = L.eval("function(m, s) dgks:OnHistoryComm('dgksH', m, 'GUILD', s) end")
live = lambda: L.eval("dgks:Serialize('R', 'G-', { a = 'Pink Tonic-', e = 1, s = 1, t = NOW, k = 'K', o = 'Zed Stone-' })")
recv(live(), "Pink Tonic")
check("messages wait until we know our own name", stream(L, "Pink Tonic-#1") is None)
L.execute("PLAYER = { 'Me', 'Smith' }")
recv(live(), "Pink Tonic")
st = stream(L, "Pink Tonic-#1")
check("once the name is readable, a 12.0.009 member's live record is taken", st is not None and st["r"][1] is not None)
check("our own name was read on the way", L.eval("dgks.History.FullName('Me Smith')") == "Me Smith-Unknown")

# ---------- 3. Members recorded by first name only ----------
L = runtime(r'''ROSTER = { { "Pink Tonic", "MAGE" }, { "Bo Reed", "WARRIOR" } }''')
L.execute("dgks.History:UpdateIdentity(); dgks.History:UpdateGuild(); dgks.History:UpdateRoster()")
canon = L.eval("function(n, c) return dgks.History.CanonicalMember(n, c) end")
check("a first name maps to the only member with it", canon("Pink", None) == "Pink Tonic")
check("same class: still mapped", canon("Pink-", "MAGE") == "Pink Tonic")
check("another class: left alone", canon("Pink", "ROGUE") == "Pink")
check("a name nobody has: left alone", canon("Cy", None) == "Cy")

# A member who has left the guild still matches the full name their own records give
L.execute(r'''
local guilds = dgks.db.global.history.guilds
guilds["G-Unknown"] = guilds["G-Unknown"] or { streams = {} }
local g = guilds["G-Unknown"]
g.streams["Pat Long-Unknown#1"] = { h = 1, r = { { a = "Pat Long-Unknown", c = "PRIEST", e = 1, s = 1, t = NOW - 60, k = "D", o = "Zed Stone-Unknown" } } }
-- An old first-name-only kill by Pat, and Bo's witness report of the same kill
g.streams["Pat-#2"] = { h = 1, r = { { a = "Pat-", c = "PRIEST", e = 2, s = 1, t = NOW, k = "K", o = "Zed Stone-" } } }
g.streams["Bo Reed-Unknown#3"] = { h = 1, r = { { a = "Bo Reed-Unknown", c = "WARRIOR", e = 3, s = 1, t = NOW + 2, k = "X", o = "Zed Stone-Unknown", kn = "Pat Long-Unknown", kc = "PRIEST" } } }
''')
recs = list(L.eval("dgks.History:GuildRecords()").values())
check("a departed member matches their own full name", canon("Pat", "PRIEST") == "Pat Long")
kills = [r for r in recs if r["k"] in ("K", "X")]
check("their kill and a witness report of it count once", len(kills) == 1, [(r["k"], r["a"]) for r in kills])

# Two members share the first name: no guess
L.execute("ROSTER[3] = { 'Pink Lady', 'MAGE' }; dgks.History:UpdateRoster()")
check("two members with the same first name: left alone", canon("Pink", "MAGE") == "Pink")
check("and with no class known either", canon("Pink", None) == "Pink")
L.execute("ROSTER[3] = { 'Pink Lady', 'DRUID' }; dgks.History:UpdateRoster()")
check("different classes: the record's class picks the member", canon("Pink", "MAGE") == "Pink Tonic")

# A roster that reads empty while it loads keeps the members we had
L.execute("SAVED = ROSTER; ROSTER = {}; dgks.History:UpdateRoster()")
check("an empty roster while loading is ignored", canon("Bo", None) == "Bo Reed" and canon("Pink", "MAGE") == "Pink Tonic")
L.execute("ROSTER = SAVED")

# The game's own surname separator
L = runtime(r'''Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = "_" } }
ROSTER = { { "Pink_Tonic", "MAGE" } }''')
L.execute("dgks.History:UpdateIdentity(); dgks.History:UpdateGuild(); dgks.History:UpdateRoster()")
check("uses the game's surname separator", L.eval("dgks.History.CanonicalMember('Pink')") == "Pink_Tonic")

print("FAILS:", fails)
sys.exit(1 if fails else 0)
