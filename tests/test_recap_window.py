import sys
from lupa import lua51
import lupa
is_t = lambda r, k: lua51.lua_type(r[k]) == "table"

from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)


def make():
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.execute(r'''
SECRET_MT = { __tostring = function() return "SECRET" end }
function secret(v) return setmetatable({ v = v }, SECRET_MT) end
issecretvalue = function(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
NOW = 1000
GetTime = function() return NOW end
UISpecialFrames = {}
BreakUpLargeNumbers = function(n) return tostring(math.floor(n)) end
HP, HPMAX = 10000, 10000
UnitHealth = function() return HP end
UnitHealthMax = function() return HPMAX end
UnitGUID = function() return "Player-ME" end
C_Spell = { GetSpellTexture = function(id) return "icon" .. id end }
local function newObj(kind)
  local o = { kind = kind, shown = true, text = nil }
  setmetatable(o, { __index = function() return function() end end })
  function o:SetText(t)
    if issecretvalue(t) then self.text = "<secret:" .. tostring(t.v) .. ">" else self.text = t end
  end
  function o:GetText() return self.text end
  function o:Show() self.shown = true end
  function o:Hide() self.shown = false end
  function o:IsShown() return self.shown end
  function o:CreateFontString() return newObj("fs") end
  function o:CreateTexture() local t = newObj("tex"); function t:SetTexture(x) self.tex = x end return t end
  function o:SetValue(v) self.value = v end
  function o:SetHeight(h) self.height = h end
  function o:SetShown(v) if v then self:Show() else self:Hide() end end
  function o:SetTextColor(r, g, b) self.color = { r, g, b } end
  function o:SetStatusBarColor(r, g, b) self.barColor = { r, g, b } end
  function o:CreateAnimationGroup()
    local g = { scripts = {} }
    function g:CreateAnimation() return setmetatable({}, { __index = function() return function() end end }) end
    function g:SetToFinalAlpha() end
    function g:SetScript(n, fn) self.scripts[n] = fn end
    function g:Stop() end
    function g:Play() PLAYED = (PLAYED or 0) + 1; if self.scripts.OnFinished then self.scripts.OnFinished(self) end end
    return g
  end
  return o
end
CreateFrame = function(kind, name) local f = newObj(kind); if name then _G[name] = f end; return f end
UIParent = newObj("Frame")
GameTooltip = newObj("tt")
dgks = { db = { profile = { deathRecap = true } } }
function dgks:Print(m) print("PRINT", m) end
''')
    L.execute(src("dgks_deathrecap.lua"))
    return L


def rows(L):
    out = []
    f = L.eval("dgksDeathRecapFrame")
    # rows are created in order; walk via the local by reading frame children isn't possible, so read globals
    return out


fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)


# Capture rows: wrap CreateFrame to keep row frames
def make_capturing():
    L = make()
    return L


L = lua51.LuaRuntime(unpack_returned_tuples=True)
L = make()
L.execute(r'''
ROWS = {}
local base = CreateFrame
CreateFrame = function(kind, name, parent, tmpl)
  local f = base(kind, name, parent, tmpl)
  if kind == "Frame" and parent ~= UIParent and name == nil and parent and parent == dgksDeathRecapFrame then ROWS[#ROWS+1] = f end
  return f
end
''')
# Classic: feed combat log hits. Args: timestamp, event, hideCaster, srcGUID, srcName, srcFlags, srcFlags2, dstGUID, dstName, dstFlags, dstFlags2, ...
L.execute(r'''
local function hit(dt, ...) NOW = NOW + dt; dgks:TrackDamageTaken(...) end
-- 15 seconds ago, outside the window
hit(0, 0, "SPELL_DAMAGE", false, "G", "Old-Realm", 0, 0, "Player-ME", "Me", 0, 0, 1, "Old Spell", 1, 500, -1, 1, 0, 0, 0, false)
NOW = NOW + 7
HP = 9000; hit(0, 0, "SWING_DAMAGE", false, "G", "Zed-Other", 0, 0, "Player-ME", "Me", 0, 0, 1000, -1, 1, 0, 0, 0, false)
HP = 5000; hit(2, 0, "SPELL_DAMAGE", false, "G", "Zed-Other", 0, 0, "Player-ME", "Me", 0, 0, 1752, "Sinister Strike", 1, 4000, -1, 1, 0, 0, 200, true)
HP = 4900; hit(1, 0, "SPELL_DAMAGE", false, "G", "Bob", 0, 0, "Player-OTHER", "Other", 0, 0, 1, "Not me", 1, 99, -1, 1, 0, 0, 0, false)
HP = 0; hit(1.5, 0, "SPELL_DAMAGE", false, "G", "Zed-Other", 0, 0, "Player-ME", "Me", 0, 0, 2098, "Eviscerate", 1, 6000, 1000, 1, 0, 0, 0, true)
NOW = NOW + 0.2
dgks:ShowDeathRecap("killed by Zed-Other")
''')
f = L.eval("dgksDeathRecapFrame")
rs = [r for r in L.eval("ROWS").values() if r["shown"] and is_t(r, "time")]
lines = [(r["time"]["text"], r["ability"]["text"], r["source"]["text"], r["amount"]["text"], r["hpText"]["text"], r["icon"]["tex"]) for r in rs]
for l in lines:
    print("   ", l)
print("   title:", f["title"]["text"], "|", f["subtitle"]["text"], "|", f["footer"]["text"])
check("classic: 3 hits in window, oldest first, other-target hit and 15s-old hit excluded", [l[1] for l in lines] == ["Melee", "Sinister Strike", "Eviscerate"])
check("classic: times count down to death", [l[0] for l in lines] == ["-4.7s", "-2.7s", "-0.2s"], [l[0] for l in lines])
check("classic: crits marked, amounts shortened", [l[3] for l in lines] == ["-1000", "-4000*", "-6000*"], [l[3] for l in lines])
check("classic: health after hit", [l[4] for l in lines] == ["90%", "50%", "0%"])
check("classic: icons (melee, spells)", lines[0][5].endswith("INV_Sword_04") and lines[1][5] == "icon1752")
check("title and summary", f["title"]["text"] == "|cffff4040You died|r - killed by Zed-Other" and f["subtitle"]["text"] == "3 hits, 11K damage in the last 10 seconds")
check("window shown, faded in", f["shown"] and L.eval("PLAYED") == 1)
kb = [r for r in rs if r["kbWash"]["shown"]]
check("killing blow row highlighted with a skull (last row only)", len(kb) == 1 and kb[0]["ability"]["text"] == "Eviscerate" and kb[0]["skull"]["shown"] and not rs[0]["skull"]["shown"])
check("physical damage in the default red", list(rs[1]["amount"]["color"].values()) == [1, 0.35, 0.35])
check("health bars coloured by health left: green 90%, yellow 50%... ", list(rs[0]["hp"]["barColor"].values()) == [0.2, 0.75, 0.25] and list(rs[1]["hp"]["barColor"].values()) == [0.9, 0.7, 0.1])

# Compact view: killing blow, then the attackers who did the most damage
L.execute("dgks.db.profile.deathRecapCompact = true; dgks:ToggleDeathRecap(); dgks:ToggleDeathRecap()")
shown = [r for r in L.eval("ROWS").values() if r["shown"]]
hits = [r for r in shown if is_t(r, "time")]
srcs = [r for r in shown if is_t(r, "total")]
print("    compact:", [r["ability"]["text"] for r in hits], [(r["name"]["text"], r["hits"]["text"], r["total"]["text"]) for r in srcs], f["sourceTitle"]["text"])
check("compact: just the killing blow, highlighted", [r["ability"]["text"] for r in hits] == ["Eviscerate"] and hits[0]["kbWash"]["shown"])
check("compact: top attackers with hits and totals", [(r["name"]["text"], r["hits"]["text"], r["total"]["text"]) for r in srcs] == [("Zed-Other", "3 hits", "11K")] and f["sourceTitle"]["text"] == "Most damage")
check("compact: switch button offers the full list", f["mode"]["label"]["text"] == "Full list")
L.execute("dgks.db.profile.deathRecapCompact = false; dgks:ToggleDeathRecap(); dgks:ToggleDeathRecap()")
rs = [r for r in L.eval("ROWS").values() if r["shown"] and is_t(r, "time")]

# Retail: Blizzard recap, newest first, some secret values, one hidden caster, environment
L.execute(r'''
C_DeathRecap = {
  GetRecapMaxHealth = function() return 20000 end,
  GetRecapEvents = function() return {
    { timestamp = 500.0, event = "SPELL_DAMAGE", spellName = "Pyroblast", spellId = 11366, sourceName = secret("Mia"), amount = secret(9000), currentHP = secret(0), critical = false, school = 4 },
    { timestamp = 498.5, event = "ENVIRONMENTAL_DAMAGE", environmentalType = "Falling", amount = 3000, currentHP = 9000 },
    { timestamp = 497.0, event = "SWING_DAMAGE", sourceName = "Hidden-Guy", hideCaster = true, amount = 2000, currentHP = 12000 },
    { timestamp = 480.0, event = "SPELL_DAMAGE", spellName = "Too Old", spellId = 1, sourceName = "X", amount = 1, currentHP = 20000 },
  } end,
}
dgks:ShowDeathRecap("killer unknown (Hidden by the game)")
''')
rs = [r for r in L.eval("ROWS").values() if r["shown"] and is_t(r, "time")]
lines = [(r["time"]["text"], r["ability"]["text"], r["source"]["text"], r["amount"]["text"], r["hpText"]["text"]) for r in rs]
for l in lines:
    print("   ", l)
print("   title:", f["title"]["text"], "|", f["subtitle"]["text"], "|", f["footer"]["text"])
check("retail: rows oldest first, >10s event dropped", [l[1] for l in lines] == ["Melee", "Falling", "Pyroblast"], [l[1] for l in lines])
check("retail: hideCaster shows Hidden; env has no attacker; secret name passed through", [l[2] for l in lines] == ["|cff9d9d9dHidden|r", "", "<secret:Mia>"], [l[2] for l in lines])
check("retail: secret amount passed through untouched", lines[2][3] == "<secret:9000>")
check("retail: readable health shown as % of recap max", [l[4] for l in lines[:2]] == ["60%", "45%"])
check("retail: total skipped when an amount is secret", f["subtitle"]["text"] == "3 hits in the last 10 seconds")
check("retail: footer notes Blizzard source", "Blizzard's Death Recap" in f["footer"]["text"])
check("retail: fire damage coloured orange", list(rs[2]["amount"]["color"].values()) == [1, 0.5, 0])
L.execute("dgks.db.profile.deathRecapCompact = true; dgks:ToggleDeathRecap(); dgks:ToggleDeathRecap()")
shown = [r for r in L.eval("ROWS").values() if r["shown"]]
print("    compact secret:", [r["ability"]["text"] for r in shown if is_t(r, "time")], f["sourceTitle"]["text"])
check("compact with secret amounts: killing blow then the hits before it",
      [r["ability"]["text"] for r in shown if is_t(r, "time")] == ["Pyroblast", "Melee", "Falling"] and not [r for r in shown if is_t(r, "total")] and f["sourceTitle"]["text"] == "Hits before the killing blow")
L.execute("dgks.db.profile.deathRecapCompact = false")

# Option off: no window, but /dgks deathrecap reopens
L.execute("dgksDeathRecapFrame:Hide(); dgks.db.profile.deathRecap = false; dgks:ShowDeathRecap('x')")
check("option off: window stays closed", not L.eval("dgksDeathRecapFrame.shown"))
L.execute("dgks:ToggleDeathRecap()")
check("/dgks deathrecap reopens it", L.eval("dgksDeathRecapFrame.shown"))
L.execute("dgks:ToggleDeathRecap()")
check("/dgks deathrecap again closes it", not L.eval("dgksDeathRecapFrame.shown"))

# No data at all
L.execute("C_DeathRecap = nil; dgks.db.profile.deathRecap = true; dgks:ShowDeathRecap(nil)")
check("no damage recorded: friendly message", f["subtitle"]["text"] == "No damage was recorded before this death." and f["title"]["text"] == "|cffff4040You died|r")
print("FAILS:", fails)
sys.exit(1 if fails else 0)
