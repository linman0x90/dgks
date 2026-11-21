import sys, re
from lupa import lua51
from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)
L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute(r'''
NOW = 1790000000
time = function(t) if t then return os.time(t) end return NOW end
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
GetNormalizedRealmName = function() return "Realm" end
UnitName = function() return "Alice" end
IsInGuild = function() return true end
GetGuildInfo = function() return "Bloodbath", "Member", 3, nil end
C_Timer = { After = function(_, fn) fn() end }
UNITS = {}
UnitIsPlayer = function(u) return UNITS[u] ~= nil and UNITS[u].player end
UnitIsUnit = function(u, o) return UNITS[u] and UNITS[u].me or false end
UnitFullName = function(u) return UNITS[u].name, UNITS[u].realm end
LINES = {}
GameTooltip = { GetUnit = function(self) return "x", CUR end,
  AddDoubleLine = function(self, l, r) LINES[#LINES+1] = l .. " = " .. r end }
POST = nil
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) POST = fn end }
Enum = { TooltipDataType = { Unit = 2 } }
''')
L.execute(src("libs/LibStub/LibStub.lua"))
L.execute(r'''
local gui = LibStub:NewLibrary("AceGUI-3.0", 1); function gui:RegisterWidgetType() end
local reg = LibStub:NewLibrary("AceConfigRegistry-3.0", 1); function reg:NotifyChange() end
dgks = { db = { profile = { historyShare = true, historyRetentionDays = 90, historyTooltip = true },
  global = { history = { guilds = {} } }, char = { history = { records = {} } } } }
''')
L.execute(src("dgks_history.lua"))
L.execute(src("dgks_history_ui.lua"))
L.execute(r'''
local H = dgks.History
H:UpdateIdentity(); H:UpdateGuild(); H:InstallTooltip()
local r = dgks.db.char.history.records
-- personal: Zed on Other realm killed 3x (once without realm in death), Bob same realm
r[#r+1] = { k = "K", o = "Zed-Other", t = NOW, a = "Alice-Realm" }
r[#r+1] = { k = "K", o = "Zed-Other", t = NOW, a = "Alice-Realm" }
r[#r+1] = { k = "D", o = "Zed-Other", t = NOW, a = "Alice-Realm" }
r[#r+1] = { k = "D", o = "Bob", t = NOW, a = "Alice-Realm" }
r[#r+1] = { k = "W", o = "Bob", t = NOW, a = "Alice-Realm" }
-- guild: Cara on Other realm killed "Zed" (no realm -> Cara's realm Other); Dan on Azjol-Nerub
local g = { streams = {} }
dgks.db.global.history.guilds["Bloodbath-Realm"] = g
g.streams["Cara-Other#1"] = { h = 2, r = { { k = "K", o = "Zed", t = NOW, a = "Cara-Other", e = 1, s = 1 },
                                           { k = "K", o = "Zed-Other", t = NOW, a = "Cara-Other", e = 1, s = 2 } } }
g.streams["Dan-AzjolNerub#1"] = { h = 1, r = { { k = "D", o = "Eve-Azjol-Nerub", t = NOW, a = "Dan-AzjolNerub", e = 1, s = 1 } } }
H:NotifyChanged()
''')
def hover(unit, info):
    L.execute("LINES = {}")
    L.globals().CUR = unit
    if info is not None:
        t = L.table_from(info)
        L.globals().UNITS[unit] = t
    L.eval("POST")(L.globals().GameTooltip, None)
    lines = [re.sub(r"\|c[0-9a-f]{8}|\|r", "", l) for l in L.globals().LINES.values()]
    return lines
fails = 0
def check(label, got, want):
    global fails
    ok = got == want
    fails += not ok
    print(("PASS " if ok else "FAIL ") + label, got)
check("cross-realm enemy, you and guild", hover("mouseover", {"player": True, "name": "Zed", "realm": "Other"}),
      ["KillShot - you = Killed 2   Killed by 1", "KillShot - guild = Killed 2   Killed by 0"])
check("same-realm enemy, realm nil; duel win not counted", hover("target", {"player": True, "name": "Bob"}),
      ["KillShot - you = Killed 0   Killed by 1", "KillShot - guild = Killed 0   Killed by 0"])
check("hyphenated realm matches normalized", hover("u3", {"player": True, "name": "Eve", "realm": "AzjolNerub"}),
      ["KillShot - you = Killed 0   Killed by 0", "KillShot - guild = Killed 0   Killed by 1"])
check("unknown player: no lines", hover("u4", {"player": True, "name": "Nobody", "realm": "Other"}), [])
check("NPC: no lines", hover("u5", {"player": False, "name": "Zed", "realm": "Other"}), [])
check("yourself: no lines", hover("u6", {"player": True, "me": True, "name": "Zed", "realm": "Other"}), [])
L.execute("dgks.db.profile.historyTooltip = false")
check("option off: no lines", hover("mouseover", None), [])
L.execute("dgks.db.profile.historyTooltip = true; issecretvalue = function(v) return v == 'Zed' end")
check("secret name: no lines, no error", hover("mouseover", None), [])
print("FAILS:", fails)
sys.exit(1 if fails else 0)
