import sys
from lupa import lua51

from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)
L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute(src("libs/LibStub/LibStub.lua"))
L.execute(src("libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"))
L.execute(src("libs/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua"))
L.execute(r'''
REAL_REG = LibStub("AceConfigRegistry-3.0")
NOW = 1790000000
time = function(t) if t then return os.time(t) end return NOW end
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
GetNormalizedRealmName = function() return "Realm" end
UnitName = function() return "Alice" end
IsInGuild = function() return true end
GetGuildInfo = function() return "Bloodbath", "Member", 3, nil end
C_Timer = { After = function(_, fn) fn() end }
UISpecialFrames = {}
local gui = LibStub:NewLibrary("AceGUI-3.0", 1)
function gui:RegisterWidgetType() end
CREATED = {}
local function widget(kind)
  local w = { kind = kind, callbacks = {}, children = {} }
  setmetatable(w, { __index = function() return function() end end })
  function w:SetCallback(n, fn) self.callbacks[n] = fn end
  function w:AddChild(c) self.children[#self.children+1] = c end
  function w:ReleaseChildren() self.children = {} end
  function w:SetTabs(t) self.tabs = t end
  function w:SelectTab(v) self.selected = v; self.callbacks.OnGroupSelected(self, "OnGroupSelected", v) end
  function w:SetRows(rows) ROWS = rows end
  function w:Hide() if self.callbacks.OnClose then self.callbacks.OnClose(self) end end
  w.frame = {}
  return w
end
function gui:Create(kind) local w = widget(kind); CREATED[#CREATED+1] = w; return w end
function gui:Release() RELEASED = (RELEASED or 0) + 1 end
OPENED = {}
local dialog = LibStub:NewLibrary("AceConfigDialog-3.0", 1)
function dialog:Open(app, container) OPENED[#OPENED+1] = app; container.app = app end
dgks = { db = { profile = { historyShare = true, historyRetentionDays = 90, historyTooltip = true, guessKiller = true },
  global = { history = { guilds = {} } }, char = { history = { records = {} } } } }
function dgks:Print() end
''')
L.execute(src("dgks_history.lua"))
L.execute(src("dgks_history_ui.lua"))
L.execute("dgks.History:UpdateIdentity(); dgks.History:UpdateGuild()")

fails = 0
def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)

# Validate the real Settings>History entries with AceConfigRegistry
ok, err = L.eval('''(function()
  local hist = { type = "group", name = "History", args = dgks.History:SettingsArgs(1) }
  local ok2, e2 = pcall(REAL_REG.ValidateOptionsTable, REAL_REG, hist, "h")
  return ok2, e2
end)()''')
check("real History settings entries validate", ok is True, err)
keys = sorted(L.eval("dgks.History:SettingsArgs(1)").keys())
print("  history settings:", keys)
check("history settings no longer include the old Open history button", "historyOpen" not in keys and "historyShare" in keys)
orders = sorted((v["order"], k) for k, v in L.eval("dgks.History:SettingsArgs(1)").items())
print("  orders:", orders)
check("history settings order starts at 1 and stays below the reset buttons (90+)", orders[0][0] == 1 and orders[-1][0] < 90)

print("FAILS:", fails)
sys.exit(1 if fails else 0)
