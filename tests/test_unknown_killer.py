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
tinsert = table.insert
GetNormalizedRealmName = function() return "Realm" end
UnitName = function() return "Alice" end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitLevel = function() return 80 end
UnitGUID = function() return nil end
GetRealZoneText = function() return "Z" end
GetSubZoneText = function() return "" end
IsInInstance = function() return false, "none" end
IsInGuild = function() return true end
GetGuildInfo = function() return "Bloodbath", "Member", 3, nil end
C_Timer = { After = function(_, fn) fn() end }
UISpecialFrames = {}
SENT = {}
''')
L.execute(src("libs/LibStub/LibStub.lua"))
L.execute(src("libs/AceSerializer-3.0/AceSerializer-3.0.lua"))
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
  function w:SelectTab(v) self.callbacks.OnGroupSelected(self, "OnGroupSelected", v) end
  return w
end
function gui:Create(kind) local w = widget(); if kind == "TabGroup" then TABSW = w end; return w end
local reg = LibStub:NewLibrary("AceConfigRegistry-3.0", 1); function reg:NotifyChange() end
dgks = { db = { profile = { historyShare = true, historyRetentionDays = 90, historyTooltip = true },
  global = { history = { guilds = {} } }, char = { history = { records = {} } } } }
LibStub("AceSerializer-3.0"):Embed(dgks)
function dgks:Print() end
''')
L.execute(src("dgks_history.lua"))
L.execute(src("dgks_history_ui.lua"))
L.execute(r'''
local H = dgks.History
H:UpdateIdentity(); H:UpdateGuild()
H:Record("D", "Zed-Other", nil, nil, nil)
H:Record("D", "Zed-Other", nil, nil, nil, { guessed = 2 })
H:Record("D", "Hidden by the game", nil, nil, nil, { unknown = true })
H:Record("D", "Hidden by the game", nil, nil, nil, { unknown = true })
H:Record("D", "Hidden by the game", nil, nil, nil, { unknown = true })
H:Record("D", "Unknown because of retail", nil, nil, nil)
H:Record("K", "Zed-Other", nil, 1, 0)
''')
strip = lambda s: re.sub(r"\|T[^|]*\|t ?|\|c[0-9a-f]{8}|\|r", "", s)
fails = 0
def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)

recs = list(L.eval("dgks.History:PersonalRecords()").values())
flags = [(r["o"], r["u"], r["g"], r["gn"]) for r in recs]
check("flags stored (u for unknown + legacy text, g/gn for guess)",
      flags[1] == ("Zed-Other", None, 1, 2) and flags[2][1] == 1 and flags[5] == ("Unknown because of retail", 1, None, None), flags)

st = L.eval("dgks.History:OverviewStats()")
pred = [(o["name"], o["count"]) for o in st["predators"].values()]
print("  ", pred)
check("Top predators lists only Zed (2 incl. likely), not the unknowns", pred == [("Zed-Other", 2)])
check("Deaths total still counts every death (6)", st["totals"]["D"] == 6, st["totals"]["D"])

L.execute("ROWS = dgks.History:ViewRows('mine')")
rows = [[strip(c) for c in r["cells"].values()] for r in L.eval("ROWS").values()]
opp = sorted(r[2] for r in rows)
print("   my history opponents:", opp)
check("My history shows likely label and unknown reasons", "Zed-Other (likely)" in opp and opp.count("Hidden by the game") == 3)
L.execute("ROWS = dgks.History:ViewRows('opponents')")
rows = [[strip(c) for c in r["cells"].values()] for r in L.eval("ROWS").values()]
check("My opponents excludes unknowns", [r[0] for r in rows] == ["Zed-Other"], rows)
L.execute("ROWS = dgks.History:ViewRows('guildopponents')")
rows = [[strip(c) for c in r["cells"].values()] for r in L.eval("ROWS").values()]
check("Guild opponents excludes unknowns", [r[0] for r in rows] == ["Zed-Other"], rows)

mine, guild = L.eval("dgks.History:CountsFor('Zed-Other')")
check("tooltip counts for Zed: 1 kill, 2 deaths", (mine["K"], mine["D"]) == (1, 2))
mine, guild = L.eval("dgks.History:CountsFor('Hidden by the game-Realm')")
check("no tooltip counts for the unknown reason text", (mine["K"], mine["D"]) == (0, 0))

# Guessed + unknown flags survive the sync validation
ok = L.eval('''(function()
  local raw = { a = "Bob-Realm", e = 1, s = 1, t = NOW, k = "D", o = "Zed", g = 1, gn = 3 }
  local raw2 = { a = "Bob-Realm", e = 1, s = 2, t = NOW, k = "D", o = "Hidden by the game", u = 1 }
  local bad = { a = "Bob-Realm", e = 1, s = 3, t = NOW, k = "D", o = "X", gn = 99 }
  local m1 = dgks:Serialize("R", "Bloodbath-Realm", raw)
  local m2 = dgks:Serialize("R", "Bloodbath-Realm", raw2)
  local m3 = dgks:Serialize("R", "Bloodbath-Realm", bad)
  dgks:OnHistoryComm("dgksH", m1, "GUILD", "Bob")
  dgks:OnHistoryComm("dgksH", m2, "GUILD", "Bob")
  dgks:OnHistoryComm("dgksH", m3, "GUILD", "Bob")
  local st = dgks.db.global.history.guilds["Bloodbath-Realm"].streams["Bob-Realm#1"]
  return st.r[1] and st.r[1].g == 1 and st.r[1].gn == 3 and st.r[2] and st.r[2].u == 1 and st.r[3] == nil
end)()''')
check("guessed/unknown flags survive sync; bad gn rejected", ok is True)
print("FAILS:", fails)
sys.exit(1 if fails else 0)
