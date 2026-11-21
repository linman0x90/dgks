import os
import sys
from lupa import lua51

from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)
HERE = os.path.dirname(os.path.abspath(__file__))
death_src = open(HERE + "/test_death.py").read().split("fails = 0")[0]
exec(death_src)  # make(): dgks.lua with retail stubs (historyPve = true there)

fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)


def setup(L):
    L.execute(r'''
dgks.db.profile.historyPve = nil  -- the default: PvP only
SEEN = { ["Zed-Other"] = true }
dgks.Players.Lookup = function(_, name) if SEEN[name] then return { guid = "Player-2-ZED" } end end
INSTANCE = "none"
IsInInstance = function() return INSTANCE ~= "none", INSTANCE end
''')


def die(L, setup_code):
    L.execute("RECORDS, PRINTS, TIMERS = {}, {}, {}")
    L.execute(setup_code)
    L.execute("FIRE('PLAYER_DEAD'); RUN_TIMERS()")
    return [r["o"] for r in L.eval("RECORDS").values()]


L = make()
setup(L)
check("default: PvE logging is off", L.eval("dgks.db.profile.historyPve") is None and L.eval("dgks:LogsPvE()") is False)

# ---------- Deaths (retail: Death Recap names only) ----------
check("killed by an NPC in the open world: not logged", die(L, "RECAP = { { sourceName = 'Kobold Miner' } }") == [])
check("killed by a player we saw nearby: logged", die(L, "RECAP = { { sourceName = 'Zed-Other' } }") == ["Zed-Other"])
check("likely killer (an enemy player targeting us): logged",
      die(L, "RECAP = { { sourceName = SECRET } }; UNITS = { nameplate1 = { player = true, enemy = true, targetsMe = true, name = 'Ann', realm = 'Other', guid = 'Player-4-ANN' } }") == ["Ann-Other"])
L.execute("UNITS = {}")
check("environment (falling): not logged", die(L, "RECAP = { { amount = 5000 } }") == [])
check("killer hidden in a dungeon: not logged", die(L, "INSTANCE = 'party'; RECAP = { { sourceName = SECRET } }") == [])
check("killer hidden in a battleground: logged", die(L, "INSTANCE = 'pvp'; RECAP = { { sourceName = SECRET } }") == ["Hidden by the game"])
check("unseen killer name in an arena: logged", die(L, "INSTANCE = 'arena'; RECAP = { { sourceName = 'Rex-Far' } }") == ["Rex-Far"])
L.execute("INSTANCE = 'none'")
check("death recap still opens for an unlogged death", L.eval("(function() LASTRECAP = nil; dgks:PlayerDeath('Kobold Miner') return LASTRECAP end)()") is not None)

# With PvE logging on, everything is logged
L.execute("dgks.db.profile.historyPve = true")
check("PvE on: NPC death logged", die(L, "RECAP = { { sourceName = 'Kobold Miner' } }") == ["Kobold Miner"])
check("PvE on: environment logged", die(L, "RECAP = { { amount = 5000 } }") == ["Environment"])
L.execute("dgks.db.profile.historyPve = nil")

# ---------- Kills ----------
L.execute(r'''
TX = {}
REAL_TX = dgks.KillshotTX
function dgks:KillshotTX(v, t, g) TX[#TX+1] = v; REAL_TX(self, v, t, g) end
function dgks:ProcessKillshot() end
function dgks:Serialize() return "x" end
function dgks:SendCM() end
dgks.db.profile.kstextM = { "a", "b", "c" }
GetPlayerInfoByGUID = function(g)
  if g == "Player-2-ZED" then return "Mage", "MAGE", "Human", "Human", 2, "Zed", "Other" end
  if g == "Player-1-ME" then return "Warrior", "WARRIOR", "Human", "Human", 2, "Me", "Realm" end
end
UnitNameFromGUID = function(g) if g == "Creature-0-1-2-3-4-5" then return "Kobold Miner" end end
''')


def kill(target, setup_code=""):
    L.execute("RECORDS, TX = {}, {}")
    L.execute(setup_code)
    L.execute(f"FIRE('PARTY_KILL', 'Player-1-ME', '{target}')")
    return [r["o"] for r in L.eval("RECORDS").values()], list(L.eval("TX").values())


check("player kill: announced and logged", kill("Player-2-ZED") == (["Zed"], ["Zed"]))
check("NPC kill, defaults: neither announced nor logged", kill("Creature-0-1-2-3-4-5") == ([], []))
check("NPC kill, PvE logging on: logged quietly (no announcement)",
      kill("Creature-0-1-2-3-4-5", "dgks.db.profile.historyPve = true; NOW = NOW + 5") == (["Kobold Miner"], []))
check("NPC kill, NPC killshots on but PvE logging off: announced, not logged",
      kill("Creature-0-1-2-3-4-5", "dgks.db.profile.historyPve = nil; dgks.db.profile.dopve = true; NOW = NOW + 5") == ([], ["Kobold Miner"]))
check("NPC kill, both on: announced and logged",
      kill("Creature-0-1-2-3-4-5", "dgks.db.profile.historyPve = true; NOW = NOW + 5") == (["Kobold Miner"], ["Kobold Miner"]))

# ---------- Classic: the combat log says whether the killer was player-controlled ----------
C = lua51.LuaRuntime(unpack_returned_tuples=True)
classic_src = death_src.replace("WOW_PROJECT_ID = 1\n", "WOW_PROJECT_ID = 2\n")
ns = {"lua51": lua51, "src": src}
exec(classic_src, ns)
C = ns["make"]()
setup(C)
C.execute(r'''
COMBATLOG_OBJECT_TYPE_PLAYER = 0x400
COMBATLOG_OBJECT_CONTROL_PLAYER = 0x100
COMBATLOG_OBJECT_AFFILIATION_MINE = 0x1
bit = { band = function(a, b) local r, p = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end }
dgks.TrackDamageTaken = function() end
UnitName = function() return "Me", nil end
UnitGUID = function(u) if u == "player" then return "Player-1-ME" end end
dgks:OnEnable()
''')
classic = C.eval("dgks.CombatLogEventHandler") is not None


def classic_death(src_name, src_flags, setup_code=""):
    C.execute("RECORDS = {}")
    C.execute(setup_code)
    C.execute(f"dgks:CombatLogEventHandler(nil, 1, 'SWING_DAMAGE', false, 'X', '{src_name}', {src_flags}, 0, 'Player-1-ME', 'Me', 0x511, 0, 100)")
    C.execute("dgks:CombatLogEventHandler(nil, 2, 'UNIT_DIED', false, '', nil, 0, 0, 'Player-1-ME', 'Me', 0x511, 0)")
    return [r["o"] for r in C.eval("RECORDS").values()]


check("Classic: killed by a player: logged", classic_death("Zed", 0x548) == ["Zed"], classic_death("Zed", 0x548))
check("Classic: killed by a player's pet: logged", classic_death("Wolf", 0x1148) == ["Wolf"])
check("Classic: killed by an NPC: not logged", classic_death("Kobold Miner", 0xa48) == [])
check("Classic: killed by an NPC, PvE logging on: logged", classic_death("Kobold Miner", 0xa48, "dgks.db.profile.historyPve = true") == ["Kobold Miner"])
print("FAILS:", fails)
sys.exit(1 if fails else 0)
