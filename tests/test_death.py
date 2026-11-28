import sys
from lupa import lua51

from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)


def make():
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.execute(r'''
SECRET = setmetatable({}, { __tostring = function() return "SECRET" end })
issecretvalue = function(v) return v == SECRET end
WOW_PROJECT_ID = 1
WOW_PROJECT_CLASSIC = 2
date = os.date
tinsert, tremove = table.insert, table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
NOW = 100
GetTime = function() return NOW end
TIMERS = {}
C_Timer = { After = function(d, fn) TIMERS[#TIMERS+1] = { at = NOW + d, fn = fn } end }
function RUN_TIMERS()
  local guard = 0
  while #TIMERS > 0 and guard < 100 do
    guard = guard + 1
    table.sort(TIMERS, function(a, b) return a.at < b.at end)
    local t = table.remove(TIMERS, 1)
    NOW = t.at
    t.fn()
  end
end
FRAME = nil
CreateFrame = function()
  local f = { events = {} }
  function f:SetScript(n, fn) self[n] = fn end
  function f:RegisterEvent(e) self.events[e] = true end
  FRAME = FRAME or f
  return f
end
IsInInstance = function() return false, "none" end
GetRealZoneText = function() return "Arathi Highlands" end
GetNormalizedRealmName = function() return "Realm" end
UnitGUID = function(u)
  if u == "player" then return "Player-1-ME" end
  local base = u:match("^(.-)target$")
  if base and base ~= "" and UNITS[base] then
    if COMPARE_SECRET then return SECRET end
    return UNITS[base].targetsMe and "Player-1-ME" or "Player-9-SOMEONE"
  end
  return UNITS[u] and UNITS[u].guid
end
GetPlayerInfoByGUID = function() return "Warrior", "WARRIOR", "Human", "Human", 2, "Me", "Realm" end
UnitName = function() return "Me", nil end
UNITS = {}
UnitExists = function(u) return UNITS[u] ~= nil end
UnitIsPlayer = function(u) return UNITS[u] and UNITS[u].player or false end
UnitCanAttack = function(_, u) return UNITS[u] and UNITS[u].enemy or false end
-- Compound-token comparisons are always secret on retail: the addon must not rely on them
UnitIsUnit = function(a, b) if a:match("target$") then return SECRET end return a == b end
UnitFullName = function(u) return UNITS[u].name, UNITS[u].realm end
Screenshot = function() end
RECAP = nil
HAS = true
C_DeathRecap = {
  HasRecapEvents = function() return HAS end,
  GetRecapEvents = function() return RECAP end,
}
-- Fake LibStub / Ace: only what dgks.lua touches at load and in OnEnable
LibStub = setmetatable({}, { __call = function(_, name)
  return { NewAddon = function(_, n) local a = {} return a end,
           RegisterOptionsTable = function() end, AddToBlizOptions = function() end,
           New = function() return {} end }
end })
''')
    L.execute(src("dgks.lua"))
    L.execute(r'''
dgks.db = { profile = { dochatbox = true, maxdeathstreak = 0, maxstreak = 0,
  doscreenshotondeath = false, guessKiller = true, historyPve = true } }
PRINTS, RECORDS = {}, {}
function dgks:Print(m) PRINTS[#PRINTS+1] = m end
dgks.History = { Enable = function() end,
  Record = function(_, kind, o, guid, st, mk, flags) RECORDS[#RECORDS+1] = { k = kind, o = o, guid = guid, flags = flags } return { o = o } end }
function dgks:SetupMinimapButton() end
dgks.Players = { Enable = function() end, NoteCombatant = function() end }
function dgks:ShowDeathRecap(k) LASTRECAP = k end
dgks:OnEnable()
function FIRE(e, ...) FRAME.OnEvent(FRAME, e, ...) end
''')
    return L


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
    flags = r["flags"]
    return (r["o"], dict(flags.items()) if flags else None, r["guid"])


L = make()
check("events registered on retail path", L.eval("FRAME.events.PLAYER_DEAD and FRAME.events.UNIT_TARGET") is True)

r = die(L, "RECAP = { { sourceName = 'Zed-Other', hideCaster = false }, { sourceName = 'Old' } }")
check("recap names killer from entry 1", r == ("Zed-Other", None, None), r)

r = die(L, "RECAP = { { sourceName = SECRET } }")
check("secret name, nobody around -> Hidden by the game (unknown)", r == ("Hidden by the game", {"unknown": True}, None), r)

r = die(L, "RECAP = { { hideCaster = true, sourceName = 'X' } }")
check("hideCaster -> Hidden attacker", r == ("Hidden attacker", {"unknown": True}, None), r)

r = die(L, "RECAP = { { amount = 5000 } }")
check("no caster -> Environment", r == ("Environment", {"unknown": True}, None), r)

L.execute("HAS = false")
t0 = L.eval("NOW")
r = die(L, "RECAP = {}")
waited = L.eval("NOW") - t0
check("empty recap waits ~5s then No death recap", r == ("No death recap", {"unknown": True}, None) and 4.9 <= waited <= 5.1, (r, waited))

# recap fills in after 1.5 seconds
L.execute("HAS = false")
L.execute("RECORDS, TIMERS = {}, {}; RECAP = {}; FIRE('PLAYER_DEAD')")
L.execute("C_Timer.After(1.2, function() HAS = true; RECAP = { { sourceName = 'Late-Realm' } } end)")
L.execute("RUN_TIMERS()")
recs = list(L.eval("RECORDS").values())
check("late recap is picked up", recs and recs[0]["o"] == "Late-Realm", recs and recs[0]["o"])
L.execute("HAS = true")

# Guess: one enemy targeting me on a nameplate, recap hidden
r = die(L, """RECAP = { { sourceName = SECRET } }
UNITS = { nameplate3 = { player = true, enemy = true, targetsMe = true, name = 'Zed', realm = 'Other', guid = 'Player-2-ZED' },
          nameplate4 = { player = true, enemy = false, targetsMe = true, name = 'Friend', realm = nil } }""")
check("hidden recap + one enemy targeting me -> likely Zed", r == ("Zed-Other", {"guessed": 1}, "Player-2-ZED"), r)

# Two enemies: one still targeting me, one switched to me recently then away
L.execute("""UNITS = { arena2 = { player = true, enemy = true, targetsMe = true, name = 'Rex', realm = nil, guid = 'Player-1-REX' } }
NOW = NOW + 1; FIRE('UNIT_TARGET', 'arena2')
UNITS.arena2.targetsMe = false
UNITS.nameplate1 = { player = true, enemy = true, targetsMe = true, name = 'Ann', realm = 'Other', guid = 'Player-2-ANN' }
NOW = NOW + 1""")
r = die(L, "RECAP = { { sourceName = SECRET } }")
check("prefers the enemy still targeting me, counts both", r == ("Ann-Other", {"guessed": 2}, "Player-2-ANN"), r)

# Recent targeter only (switched away), within window
L.execute("""UNITS = { arena1 = { player = true, enemy = true, targetsMe = true, name = 'Rex', guid = 'Player-1-REX' } }
NOW = NOW + 1; FIRE('UNIT_TARGET', 'arena1'); UNITS.arena1.targetsMe = false; NOW = NOW + 3""")
r = die(L, "RECAP = { { sourceName = SECRET } }")
check("recent targeter within 8s is used", r == ("Rex-Realm", {"guessed": 1}, "Player-1-REX"), r)

# Older than window
L.execute("""UNITS = { arena1 = { player = true, enemy = true, targetsMe = true, name = 'Rex', guid = 'Player-1-REX' } }
NOW = NOW + 1; FIRE('UNIT_TARGET', 'arena1'); UNITS.arena1.targetsMe = false; NOW = NOW + 20""")
r = die(L, "RECAP = { { sourceName = SECRET } }")
check("targeter older than 8s is ignored", r == ("Hidden by the game", {"unknown": True}, None), r)

# Environment death never guesses
r = die(L, "RECAP = { { amount = 1 } }; UNITS = { nameplate1 = { player = true, enemy = true, targetsMe = true, name = 'Ann', realm = 'Other' } }")
check("environment death does not guess", r == ("Environment", {"unknown": True}, None), r)

# Recap that names someone wins over a guess
r = die(L, "RECAP = { { sourceName = 'Real-Killer' } }; UNITS = { nameplate1 = { player = true, enemy = true, targetsMe = true, name = 'Ann', realm = 'Other' } }")
check("named recap beats guess", r == ("Real-Killer", None, None), r)

# Comparisons hidden (dungeon): no guess, no error
r = die(L, "COMPARE_SECRET = true; RECAP = { { sourceName = SECRET } }; UNITS = { nameplate1 = { player = true, enemy = true, targetsMe = true, name = 'Ann' } }")
check("hidden unit comparisons: no guess, no error", r == ("Hidden by the game", {"unknown": True}, None), r)
L.execute("COMPARE_SECRET = false")

# Option off
L.execute("dgks.db.profile.guessKiller = false")
r = die(L, "RECAP = { { sourceName = SECRET } }; UNITS = { nameplate1 = { player = true, enemy = true, targetsMe = true, name = 'Ann', realm = 'Other' } }")
check("option off: no guess", r == ("Hidden by the game", {"unknown": True}, None), r)
L.execute("dgks.db.profile.guessKiller = true")

prints = list(L.eval("PRINTS").values())
check("chat says killer unknown", prints[-1] == "You died. Killer unknown: Hidden by the game.", prints[-1])

# /dgks recap dump
L.execute("PRINTS = {}; RECAP = { { sourceName = SECRET, amount = 1234, hideCaster = false, spellId = 133 }, { sourceName = 'Bob', amount = 10 } }")
L.execute("dgks:DumpRecap()")
dump = list(L.eval("PRINTS").values())
for line in dump:
    print("   ", line)
check("dump shows fields and hidden values safely", any('sourceName=<hidden by the game>' in l and "caused death" in l for l in dump) and any('sourceName="Bob"' in l for l in dump) and dump[-1] == "dgks reads this as: Hidden by the game (secret)")
print("FAILS:", fails)
sys.exit(1 if fails else 0)
