"""The battleground probe (dgks_bgprobe.lua, development copies only): for each PARTY_KILL with secret
GUIDs it decides from the Battleground Killing Blows statistic whether the kill was ours, follows the
enemy players around us to see which one died, logs only in battlegrounds and arenas, and never stops
on an error.

Needs Python 3 and lupa (pip install lupa). Run from anywhere:

    python tests/test_bgprobe.py

Exits with 1 if any check fails.
"""
import os
import sys
from lupa import lua51

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra if not cond else "")


L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute(r'''
SECRET = setmetatable({}, { __tostring = function() return "secret" end })
issecretvalue = function(v) return v == SECRET end
NOW = 100
GetTime = function() return NOW end
date = function() return "12:00:00" end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
PRINTED = {}
print = function(m) PRINTED[#PRINTED + 1] = m end
FRAMES = {}
CreateFrame = function()
  local f = { events = {} }
  -- Touching the combat log's registration is a protected action in game (ADDON_ACTION_FORBIDDEN)
  function f:RegisterEvent(e)
    if e == "COMBAT_LOG_EVENT_UNFILTERED" then FORBIDDEN = (FORBIDDEN or 0) + 1 end
    self.events[e] = true
  end
  function f:UnregisterEvent(e)
    if e == "COMBAT_LOG_EVENT_UNFILTERED" then FORBIDDEN = (FORBIDDEN or 0) + 1 end
    self.events[e] = nil
  end
  function f:SetScript(_, fn) self.onEvent = fn end
  FRAMES[#FRAMES + 1] = f
  return f
end
function FIRE(event, ...) for _, f in ipairs(FRAMES) do if f.events[event] and f.onEvent then f.onEvent(f, event, ...) end end end
TIMERS = {}
C_Timer = {
  NewTicker = function(_, fn) TICK = fn return {} end,
  After = function(d, fn) TIMERS[#TIMERS + 1] = { d = d, fn = fn } end,
}
-- Runs the timers due by `upto` seconds, in order
function RUN_TIMERS(upto)
  table.sort(TIMERS, function(a, b) return a.d < b.d end)
  local left = {}
  for _, t in ipairs(TIMERS) do if t.d <= upto then t.fn() else left[#left + 1] = t end end
  TIMERS = left
end
INSTANCE = "pvp"
IsInInstance = function() return INSTANCE ~= "none", INSTANCE end
GetRealZoneText = function() return "Alterac Valley" end
C_PvP = { IsBattleground = function() return true end,
  GetScoreInfoByPlayerGuid = function() return { killingBlows = SECRET, honorableKills = SECRET, deaths = SECRET, name = "Me" } end }
GetNumBattlefieldScores = function() return 0 end
GetBattlefieldScore = function() end
REQUESTS = 0
RequestBattlefieldScoreData = function() REQUESTS = REQUESTS + 1 end
UnitGUID = function(u) if u == "player" then return "Player-1-ME" end return SECRET end
-- Enemy players by unit; dead ones have dead = true
UNITS = {}
local function U(u) return UNITS[u] end
UnitExists = function(u) return U(u) ~= nil end
UnitIsPlayer = function(u) return U(u) ~= nil end
UnitCanAttack = function(_, u) return U(u) ~= nil and not U(u).friend end
UnitName = function(u) if u == "player" then return "Me" end return U(u) and U(u).name end
UnitLevel = function(u) return U(u) and U(u).level end
UnitIsDeadOrGhost = function(u) return U(u) ~= nil and U(u).dead == true end
UnitIsDead = UnitIsDeadOrGhost
UnitHealth = function() return SECRET end
UnitHealthMax = function() return SECRET end
UnitIsUnit = function() return SECRET end
BGKB = 0
GetStatistic = function(id) if id == 1491 then return BGKB == 0 and "--" or tostring(BGKB) end return "7" end
GetPVPSessionStats = function() return 0, 0 end
GetBuildInfo = function() return "1.15.8" end
SlashCmdList = {}
dgks = { db = { global = {} }, BGKills = {} }
''')
L.execute(open(os.path.join(REPO, "dgks_bgprobe.lua"), encoding="utf-8").read())
L.execute('FIRE("PLAYER_LOGIN")')
probe = L.eval("SlashCmdList.DGKSPROBE")
state = lambda: L.eval("dgks.db.global.bgprobe")
lines = lambda: list(state()["log"].values())
text = lambda: "\n".join(lines())

check("off by default, nothing logged", state()["on"] is False and len(lines()) == 0)
L.execute('FIRE("PARTY_KILL", SECRET, SECRET)')
check("events are ignored while off", len(lines()) == 0)

probe("on")
check("on: build and where we are logged", "PROBE ON (1.15.8" in text() and "instance=pvp zone=Alterac Valley" in text(), text())
check("the combat log's registration is never touched (a protected action)", L.eval("FORBIDDEN") is None)
L.execute('dgks.BGKills.trace("kill #1: ours")')
check("the battleground kill code's steps are logged while on", lines()[-1].endswith("BGKILLS kill #1: ours"), lines()[-1])
check("entering: the statistics are read ('--' counts as 0)", "BG KB=0" in text(), text())

# 1. Our kill: the statistic rises with PARTY_KILL, and our target dies a moment later
L.execute('''UNITS = { target = { name = "Moocifer Mooningstar", level = 60 }, nameplate2 = { name = "Big Jub", level = 58 },
  nameplate3 = { name = "Friend Ly", level = 60, friend = true } }
BGKB = 1; FIRE("PARTY_KILL", SECRET, SECRET)''')
t = text()
check("PARTY_KILL lists the enemy players around us with levels, not friends",
      "PARTY_KILL #1 attacker=SECRET victim=SECRET | BG KB now 1 | enemies: 60 Moocifer Mooningstar (target), 58 Big Jub (nameplate2)" in t
      and "Friend Ly" not in t, t)
L.execute('RUN_TIMERS(0.25)')
check("+0.25s: still alive, already known to be ours", "+0.25s kill #1: BG KB 0 -> 1 (OURS) | Moocifer Mooningstar=alive(false), Big Jub=alive(false)" in text(), lines()[-1])
L.execute('UNITS.target.dead = true; RUN_TIMERS(2)')
t = text()
check("+0.5s on: the victim shows dead", "+0.50s kill #1: BG KB 0 -> 1 (OURS) | Moocifer Mooningstar=DEAD, Big Jub=alive(false)" in t, t)
check("verdict: ours, victim named", "VERDICT kill #1: OURS, victim Moocifer Mooningstar" in t, t)
check("the player is told", any("your kill #1: Moocifer Mooningstar" in str(p) for p in L.eval("PRINTED").values()))

# 2. A groupmate's kill: the statistic does not move; the victim was a nameplate that changed
L.execute('''UNITS = { target = { name = "Saint Grissom", level = 60 } }
FIRE("PARTY_KILL", SECRET, SECRET)
UNITS.target = { name = "Someone Else", level = 60 }
UNITS.nameplate4 = { name = "Zagg Brokenbow", level = 60, dead = true }
RUN_TIMERS(2)''')
t = text()
check("not ours when the statistic does not rise", "+2.00s kill #2: BG KB 1 -> 1 (not ours)" in t, t)
check("a target that changed is 'gone'; a new dead enemy is noticed", "Saint Grissom=gone" in t and "Zagg Brokenbow=DEAD(new, nameplate4)" in t, t)
check("verdict: a groupmate's", "VERDICT kill #2: a groupmate's, victim Zagg Brokenbow" in t, t)

# 3. The statistic rose just before PARTY_KILL arrived (CRITERIA_UPDATE handled first): still ours
L.execute('''UNITS = { target = { name = "Chain Lightning", level = 60 } }
NOW = 200; BGKB = 2; FIRE("CRITERIA_UPDATE"); FIRE("PARTY_KILL", SECRET, SECRET); RUN_TIMERS(2)''')
check("a rise seen just before PARTY_KILL still counts as ours", "VERDICT kill #3: OURS, victim not seen dead" in text(), text())

# 4. Nobody around
L.execute('UNITS = {}; NOW = 300; BGKB = 3; FIRE("PARTY_KILL", SECRET, SECRET); RUN_TIMERS(2)')
check("no enemies around: logged as such", "enemies: none" in text() and "kill #4: BG KB 2 -> 3 (OURS) | no enemy players around" in text(), text())

# 6. Nameplates: a dead enemy's plate going away names the victim, even with nobody targeted
L.execute('''UNITS = { nameplate7 = { name = "Sdot", level = 59 } }
NOW = 350; BGKB = 4; FIRE("PARTY_KILL", SECRET, SECRET)
NOW = 350.1; UNITS.nameplate7.dead = true; FIRE("NAME_PLATE_UNIT_REMOVED", "nameplate7"); UNITS.nameplate7 = nil
UNITS.nameplate8 = { name = "Walker", level = 60 }; FIRE("NAME_PLATE_UNIT_REMOVED", "nameplate8"); UNITS.nameplate8 = nil
UNITS.nameplate9 = { name = "Ally", level = 60, friend = true, dead = true }; FIRE("NAME_PLATE_UNIT_REMOVED", "nameplate9")
NOW = 350; RUN_TIMERS(2)''')
t = text()
check("a player plate going away is logged with dead or alive",
      "PLATE GONE nameplate7 name=Sdot player=true enemy=true dead=true" in t and "PLATE GONE nameplate8 name=Walker player=true enemy=true dead=false" in t, t)
check("verdict lists only enemy plates that vanished dead, timed from the kill", "VERDICT kill #5: OURS" in t and "plates gone dead: Sdot(+0.10s)" in t
      and "Walker(" not in t.split("VERDICT kill #5")[1] and "Ally(" not in t.split("VERDICT kill #5")[1], t.split("VERDICT kill #5")[1][:200])
check("the player is told the victim from the plate", any("your kill #5: Sdot (plate)" in str(p) for p in L.eval("PRINTED").values()))
L.execute('UNITS = { nameplate2 = { name = "Npc" } }; UnitIsPlayer = function(u) return false end; FIRE("NAME_PLATE_UNIT_REMOVED", "nameplate2")')
check("NPC plates are not logged", "name=Npc" not in text())
L.execute('UnitIsPlayer = function(u) return UNITS[u] ~= nil end; FIRE("NAME_PLATE_UNIT_REMOVED", SECRET)')
check("a secret unit token is logged, not raised", lines()[-1].endswith("PLATE GONE unit=SECRET"), lines()[-1])

# 6b. The damage meter, dumped when we leave combat
L.execute(r'''
Enum = { DamageMeterType = { DamageDone = 0, DamageTaken = 7, Deaths = 9, EnemyDamageTaken = 10 },
  DamageMeterSessionType = { Overall = 0, Current = 1 } }
IN_COMBAT = false
InCombatLockdown = function() return IN_COMBAT end
local ME = { name = "Me", classFilename = "PALADIN", totalAmount = 500, isLocalPlayer = true, sourceGUID = "Player-1-ME" }
SESSIONS = {
  [1] = {
    [9] = { combatSources = { { name = "Bob", classFilename = "ROGUE", deathTimeSeconds = 12, deathRecapID = 7 } } },
    [10] = { combatSources = { { name = "Sdot", classFilename = "ROGUE", totalAmount = 900, deathTimeSeconds = 30, deathRecapID = 8, sourceDisplayType = 2, sourceGUID = SECRET } } },
    [0] = { combatSources = { { name = "Ally", isLocalPlayer = false }, ME } },
    [7] = { combatSources = { ME } },
  },
  [0] = { [9] = { combatSources = { { name = "Old1", deathTimeSeconds = 1 }, { name = "Old2", deathTimeSeconds = 2 } } } },
}
C_DamageMeter = {
  IsDamageMeterAvailable = function() return true end,
  GetAvailableCombatSessions = function() return { 1, 2 } end,
  GetCombatSessionFromType = function(st, mt)
    if IN_COMBAT then return SECRET end
    return SESSIONS[st] and SESSIONS[st][mt]
  end,
  GetCombatSessionSourceFromType = function(st, mt, guid)
    if mt == 0 then return { combatSpells = { { spellID = 35395, totalAmount = 300, overkillAmount = 120, isDeadly = true,
      combatSpellDetails = { { unitName = "Sdot", unitClassFilename = "ROGUE", amount = 300 } } } } } end
    return { combatSpells = { { spellID = 1752, totalAmount = 200, combatSpellDetails = { unitName = "Sdot", amount = 200 } } } }
  end,
}
C_DeathRecap = { GetRecapEvents = function(id)
  if id == 8 then return { { sourceName = "Me", spellName = "Crusader Strike", amount = 300, overkill = 120 } } end
  return SECRET
end }
''')
L.execute('NOW = 380; FIRE("PLAYER_REGEN_ENABLED")')
t = text().split("METER DUMP (left combat)")[-1]
check("leaving combat dumps the meter", "inCombat=false" in t and "sessions=2" in t, t[:200])
check("Deaths: the entry with its death time and recap ID; a secret recap shown as SECRET",
      "Bob class=ROGUE" in t and "deathTime=12 recapID=7" in t and "recap: SECRET" in t, t)
check("EnemyDamageTaken: the enemy, secret GUID shown, and the recap's killing blow",
      "Sdot class=ROGUE total=900" in t and "display=2 deathTime=30 recapID=8 guid=SECRET" in t
      and "recap: 1 events; killing blow: source=Me spell=Crusader Strike amount=300 overkill=120" in t, t)
check("Deaths/overall: the count only", "METER Deaths/overall: 2 entries" in t and "Old2" not in t, t)
check("DamageDone and DamageTaken: counts only, no entries or spells", "METER DamageDone/current: 2 entries" in t
      and "Ally" not in t and "current spells" not in t, t)

n = len(lines())
L.execute('NOW = 381; FIRE("PLAYER_REGEN_ENABLED")')
check("dumps are at most every 3 seconds", len(lines()) == n)
L.execute('NOW = 390; FIRE("PLAYER_REGEN_ENABLED")')
t = text().split("METER DUMP (left combat)")[-1]
check("a death is logged once: not again in the next dump", "Bob class=ROGUE" not in t and "METER Deaths/current: 1 entries" in t, t)
L.execute('SESSIONS[1][9].combatSources[2] = { name = "Me", isLocalPlayer = true, deathTimeSeconds = 40, deathRecapID = 8 }')
L.execute('NOW = 400; FIRE("PLAYER_DEAD"); RUN_TIMERS(2)')
t = text().split("METER DUMP (we died)")[-1] if "METER DUMP (we died)" in text() else ""
check("our death: the meter is dumped a moment later, with the new death and its recap",
      "Me class=nil total=nil local=true" in t and "recap: 1 events; killing blow: source=Me spell=Crusader Strike" in t, t)

L.execute('NOW = 410; probe = SlashCmdList.DGKSPROBE; probe("snap")')
t = text().split("METER DUMP (manual)")[-1]
check("snap: the full dump, with our spell breakdowns", "spell=35395 creature=nil total=300 overkill=120 deadly=true units: Sdot(ROGUE, 300)" in t
      and "spell=1752" in t and "units: Sdot(nil, 200)" in t and "Ally" not in t, t)

L.execute('IN_COMBAT = true; NOW = 420; FIRE("PLAYER_REGEN_ENABLED")')
check("a secret session is shown as SECRET", "METER Deaths/current: SECRET" in text(), lines()[-3:])
L.execute('IN_COMBAT = false')
n = len(lines())
L.execute('NOW = 421; for i = 1, 50 do FIRE("DAMAGE_METER_CURRENT_SESSION_UPDATED"); FIRE("DAMAGE_METER_COMBAT_SESSION_UPDATED", 1, 0) end')
L.execute('NOW = 460; FIRE("DAMAGE_METER_CURRENT_SESSION_UPDATED")')
ev = [l for l in lines()[n:] if "METER EVENTS" in l]
check("meter update events are only counted, logged every 30 seconds without dumping",
      len(ev) == 2 and "DAMAGE_METER_COMBAT_SESSION_UPDATED x50, DAMAGE_METER_CURRENT_SESSION_UPDATED x50" in ev[1]
      and not any("METER DUMP" in l for l in lines()[n:]), ev)
L.execute('C_DamageMeter.GetCombatSessionFromType = function() error("nope") end; NOW = 470; FIRE("PLAYER_REGEN_ENABLED")')
check("a failing meter call is logged, not raised", "METER Deaths/current: error: " in text(), lines()[-3:])
L.execute('C_DamageMeter = nil; NOW = 480; FIRE("PLAYER_REGEN_ENABLED")')
check("no damage meter: said once per dump", lines()[-1].endswith("METER (left combat): C_DamageMeter missing"), lines()[-1])

# 5. Errors and secrets never stop the probe
L.execute('UNITS = { target = { name = "X Y", level = 60 } }; UnitIsDeadOrGhost = function() error("boom") end')
L.execute('NOW = 400; FIRE("PARTY_KILL", SECRET, SECRET); RUN_TIMERS(2)')
check("a failing check is shown, not raised", "X Y=alive(error: " in text(), lines()[-2:])
L.execute('TICK()')
check("the ticker asks for scoreboard data in a battleground", L.eval("REQUESTS") >= 1)
L.execute('FIRE("UPDATE_BATTLEFIELD_SCORE")')
check("a secret scoreboard is shown as SECRET", "kb=SECRET" in text(), text())
L.execute('FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 15 Honor.")')
check("honor chat logged", lines()[-1].endswith("CHAT_MSG_COMBAT_HONOR_GAIN You have been awarded 15 Honor."), lines()[-1])

# 7. Outside battlegrounds and arenas only where we are is logged
L.execute('INSTANCE = "party"')
n = len(lines())
L.execute('FIRE("PARTY_KILL", SECRET, SECRET); FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", "x"); FIRE("PLAYER_DEAD")')
check("a dungeon's kills and deaths are not logged", len(lines()) == n, lines()[n:])
L.execute('FIRE("ZONE_CHANGED_NEW_AREA")')
check("but where we are still is", len(lines()) == n + 1 and "WHERE (zone change) instance=party" in lines()[-1], lines()[-1])
L.execute('INSTANCE = "pvp"')

for i in range(5100):
    L.execute('FIRE("CHAT_MSG_BG_SYSTEM_NEUTRAL", "x")')
check("the log is capped", len(lines()) == 5000, len(lines()))

probe("off")
n = len(lines())
L.execute('FIRE("PARTY_KILL", SECRET, SECRET)')
check("off: logging stops", len(lines()) == n and state()["on"] is False)
check("off: the trace hook is removed", L.eval("dgks.BGKills.trace") is None)
probe("clear")
check("clear empties the log", len(lines()) == 0)

print("FAILS:", fails)
sys.exit(1 if fails else 0)
