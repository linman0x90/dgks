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
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, ROGUE = { r = 1, g = 0.96, b = 0.41 } }
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", ROGUE = "Rogue", WARRIOR = "Warrior" }
UISpecialFrames = {}
tinsert = table.insert
''')
L.execute(src("libs/LibStub/LibStub.lua"))
L.execute(r'''
local gui = LibStub:NewLibrary("AceGUI-3.0", 1)
function gui:RegisterWidgetType() end
local function widget()
  local w = { callbacks = {}, children = {} }
  setmetatable(w, { __index = function() return function() end end })
  function w:SetCallback(n, fn) self.callbacks[n] = fn end
  function w:AddChild(c) self.children[#self.children+1] = c end
  function w:ReleaseChildren() self.children = {} end
  function w:SetRows(rows) ROWS = rows end
  function w:SetTabs(t) TABLIST = t end
  function w:SelectTab(v) self.callbacks.OnGroupSelected(self, "OnGroupSelected", v) end
  return w
end
function gui:Create(kind) local w = widget(); w.kind = kind; if kind == "TabGroup" then TABS_WIDGET = w end; return w end
local reg = LibStub:NewLibrary("AceConfigRegistry-3.0", 1); function reg:NotifyChange() end
dgks = { db = { profile = { historyShare = true, historyRetentionDays = 90 },
  global = { history = { guilds = {} } }, char = { history = { records = {} } } } }
''')
L.execute(src("dgks_history.lua"))
L.execute(src("dgks_history_ui.lua"))
L.execute(r'''
local H = dgks.History
H:UpdateIdentity(); H:UpdateGuild()
local g = { streams = {} }
dgks.db.global.history.guilds["Bloodbath-Realm"] = g
local function stream(author, class, recs)
  local st = { h = #recs, r = {} }
  for i, r in ipairs(recs) do r.a = author; r.c = class; r.e = 1; r.s = i; r.t = r.t or (NOW - i * 60); st.r[i] = r end
  g.streams[author .. "#1"] = st
end
-- Zed (Other realm, rogue): Alice 3 kills 1 death, Bob 1 kill 2 deaths + duel win, Cara (on Other) 2 kills naming "Zed" without realm
stream("Alice-Realm", "WARRIOR", { {k="K",o="Zed-Other",oc="ROGUE"}, {k="K",o="Zed-Other"}, {k="K",o="Zed-Other"}, {k="D",o="Zed-Other"},
                                   {k="K",o="Mia",oc="MAGE"} })
stream("Bob-Realm", "MAGE", { {k="K",o="Zed-Other"}, {k="D",o="Zed-Other"}, {k="D",o="Zed-Other"}, {k="W",o="Zed-Other"}, {k="D",o="Mia"} })
stream("Cara-Other", "ROGUE", { {k="K",o="Zed"}, {k="K",o="Zed", t = NOW + 5} })
''')
strip = lambda s: re.sub(r"\|T[^|]*\|t ?|\|c[0-9a-f]{8}|\|r", "", s)
tabs = [t["text"] for t in L.eval("dgks.History.VIEW_ORDER").values()]
print("tabs:", tabs)
L.execute('ROWS = dgks.History:ViewRows("guildopponents")')
rows = L.eval("ROWS")
out = {}
for r in rows.values():
    cells = [strip(c) for c in r["cells"].values()]
    out[cells[0]] = cells
    print(" ", cells)
fails = 0
def check(label, cond):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label)
check("tab listed between My opponents and Guild leaderboard", tabs == ["My history", "Guild history", "My opponents", "Guild opponents", "Guild leaderboard"])
z = out.get("Zed-Other")
check("Zed merged across realm spellings: 6 kills, 3 deaths, duel 1-0, 3 members", z and z[2:6] == ["6", "3", "1-0", "3"])
check("Zed top killer is Alice (3)", z and z[6] == "Alice (3)")
check("Zed class from records", z and z[1] == "Rogue")
m = out.get("Mia")
check("Mia (same realm): 1 kill, 1 death, 2 members", m and m[2:6] == ["1", "1", "0-0", "2"])
tip = []
L.globals().TT = L.table()
z_row = [r for r in rows.values() if strip(r["cells"][1]) == "Zed-Other"][0]
tt = L.eval('{ AddLine = function(self, t) TTL[#TTL+1] = t end, AddDoubleLine = function(self, l, r) TTL[#TTL+1] = l .. " | " .. r end }')
L.execute("TTL = {}")
z_row["tip"](tt)
lines = [strip(x) for x in L.eval("TTL").values()]
print("  tooltip:", lines)
check("row tooltip lists members by kills", lines[3:6] == ["Alice | 3 / 1", "Cara-Other | 2 / 0", "Bob | 1 / 2   duels 1-0"])
L.execute('ROWS = dgks.History:ViewRows("guildopponents")')
# search by member name narrows to that member's fights
L.execute('dgks.History.Filter.search = "bob"; ROWS = dgks.History:ViewRows("guildopponents")')
rows = L.eval("ROWS")
res = sorted(strip(r["cells"][1]) + ":" + strip(r["cells"][3]) for r in rows.values())
print("  search 'bob':", res)
check("search by member shows only that member's fights", res == ["Mia:0", "Zed-Other:1"])
print("FAILS:", fails)
sys.exit(1 if fails else 0)
