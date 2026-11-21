import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
code = open(HERE + "/test_recap_window.py").read().split("def rows(L):")[0]
# Record event registrations and OnEvent scripts before the recap file loads
code = code.replace('    L.execute(src("dgks_deathrecap.lua"))', '''    L.execute(r"""
WATCH = {}
local base = CreateFrame
CreateFrame = function(...)
  local f = base(...)
  f.events = {}
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(n, fn) if n == "OnEvent" and next(self.events) then WATCH[#WATCH+1] = { f = self, fn = fn } end end
  return f
end
DEAD, GHOST = true, false
UnitIsDeadOrGhost = function() return DEAD or GHOST end
function FIRE(e) for _, w in ipairs(WATCH) do if w.f.events[e] then w.fn(w.f, e) end end end
""")
    L.execute(src("dgks_deathrecap.lua"))''')
exec(code)

fails = 0
def check(label, cond):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label)

L = make()
L.execute("dgks:ShowDeathRecap('Zed')")
f = L.eval("dgksDeathRecapFrame")
check("recap open after death", f["shown"])
L.execute("DEAD, GHOST = false, true; FIRE('PLAYER_ALIVE')")
check("released to a ghost: recap stays open", f["shown"])
L.execute("GHOST = false; FIRE('PLAYER_UNGHOST')")
check("back to life after corpse run / spirit healer: closed", not f["shown"])
L.execute("DEAD = true; dgks:ShowDeathRecap('Zed')")
check("recap open after second death", f["shown"])
L.execute("DEAD = false; FIRE('PLAYER_ALIVE')")
check("accepted a resurrection: closed", not f["shown"])
L.execute("FIRE('PLAYER_ALIVE')")
check("alive with the recap already closed: no error", not f["shown"])
print("FAILS:", fails)
sys.exit(1 if fails else 0)
