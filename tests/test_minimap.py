import sys
from lupa import lua51

from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)
L = lua51.LuaRuntime(unpack_returned_tuples=True)

chk = L.eval('function(s,n) local f,e=loadstring(s,n) return e or "OK" end')
for f in ["dgks.lua", "dgks_history.lua", "dgks_history_ui.lua", "dgks_minimap.lua"]:
    print("syntax", f, chk(src(f), f))

L.execute(r'''
local function newFrame()
  local f = { scripts = {}, shown = true, points = {} }
  local mt = { __index = function(t, k) return function() end end }
  setmetatable(f, mt)
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:SetPoint(...) self.points = { ... } end
  function f:ClearAllPoints() self.points = {} end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:CreateTexture() return newFrame() end
  return f
end
CreateFrame = function() return newFrame() end
Minimap = newFrame()
function Minimap:GetWidth() return 140 end
function Minimap:GetCenter() return 1000, 800 end
function Minimap:GetEffectiveScale() return 1 end
CURSOR = { 1000, 900 }
GetCursorPosition = function() return CURSOR[1], CURSOR[2] end
TT = {}
GameTooltip = { SetOwner = function() TT = {} end,
  AddLine = function(_, t) TT[#TT+1] = tostring(t) end,
  AddDoubleLine = function(_, l, r) TT[#TT+1] = l .. ": " .. tostring(r) end,
  Show = function() end, Hide = function() end }
CALLS = {}
dgks = { db = { profile = { minimap = { hide = false, angle = 200 }, maxstreak = 9 } } }
dgks.History = {
  PersonalRecords = function() return { { k = "K" }, { k = "K" }, { k = "K" }, { k = "D" }, { k = "W" } } end,
  ToggleWindow = function() CALLS[#CALLS+1] = "history" end }
function dgks:OpenOptions() CALLS[#CALLS+1] = "options" end
function dgks:ToggleMainWindow(t) CALLS[#CALLS+1] = (t == "settings") and "options" or "history" end
function dgks:GetStreaks() return 3, 0 end
''')
L.execute(src("dgks_minimap.lua"))
L.execute("dgks:SetupMinimapButton(); B = _G.dgksMinimapButton or nil")

# The button is local; reach it through Minimap-anchored CreateFrame result captured by a wrapper
L.execute(r'''
local orig = CreateFrame
''')
fails = 0
def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)

# Re-run with a CreateFrame that records the button
L.execute(r'''
local made = {}
local base = CreateFrame
CreateFrame = function(...) local f = base(...) made[#made+1] = f return f end
MADE = made
''')
L.execute(src("dgks_minimap.lua"))
L.execute("dgks:SetupMinimapButton(); B = MADE[1]")

pts = L.eval("B.points")
import math
x, y = pts[4], pts[5]
check("placed on the minimap edge at 200 degrees", abs(math.hypot(x, y) - 75) < 0.01 and x < 0 and y < 0, (round(x, 1), round(y, 1)))

L.execute("B.scripts.OnClick(B, 'LeftButton'); B.scripts.OnClick(B, 'RightButton')")
check("left-click opens history, right-click opens options", list(L.eval("CALLS").values()) == ["history", "options"])

L.execute("B.scripts.OnEnter(B)")
tt = list(L.eval("TT").values())
print("  tooltip:", tt)
check("tooltip shows totals and streaks", "Kills: 3" in tt and "Deaths: 1" in tt and "K/D: 3.00" in tt and "Kill streak: 3  (best 9)" in tt)

L.execute("B.scripts.OnDragStart(B); CURSOR = { 1000, 900 }; B.scripts.OnUpdate(B); B.scripts.OnDragStop(B)")
check("dragging above the minimap moves the button to 90 degrees", abs(L.eval("dgks.db.profile.minimap.angle") - 90) < 0.01)
pts = L.eval("B.points")
check("  and it is drawn there", abs(pts[4]) < 0.01 and abs(pts[5] - 75) < 0.01)

L.execute("dgks.db.profile.minimap.hide = true; dgks:UpdateMinimapButton()")
check("hide option hides the button", not L.eval("B.shown"))
L.execute("dgks.db.profile.minimap.hide = false; dgks:UpdateMinimapButton()")
check("and shows it again", L.eval("B.shown"))

L.execute("GetMinimapShape = function() return 'SQUARE' end; dgks.db.profile.minimap.angle = 45; dgks:UpdateMinimapButton()")
pts = L.eval("B.points")
check("square minimap: button sits on the corner", abs(pts[4] - 75) < 0.01 and abs(pts[5] - 75) < 0.01, (pts[4], pts[5]))

L.execute("CALLS = {}; dgks_OnAddonCompartmentClick('dgks', 'LeftButton'); dgks_OnAddonCompartmentClick('dgks', 'RightButton')")
check("addon compartment clicks", list(L.eval("CALLS").values()) == ["history", "options"])
print("FAILS:", fails)
sys.exit(1 if fails else 0)
