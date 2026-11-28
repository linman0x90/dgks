"""The killing blow's ability and damage in history, where the game reports them.

Deaths: from the death recap (Blizzard's Death Recap on retail and Forever, our own combat log on
Classic), the newest row being the blow that killed us. Kills: from Classic's combat log, our (or our
pet's) last hit on the victim. Retail and Forever kills have no source, so they get none. Runs
dgks.lua and dgks_deathrecap.lua with stand-ins for the game; History.Record is captured.

Needs Python 3 and lupa (pip install lupa). Run from anywhere:

    python tests/test_killing_blow.py

Exits with 1 if any check fails.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from names_prelude import REPO

death_src = open(os.path.join(HERE, "test_death.py"), encoding="utf-8").read().split("fails = 0")[0]

fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra if not cond else "")


RECAP_FILE = open(os.path.join(REPO, "dgks_deathrecap.lua"), encoding="utf-8").read()


def runtime(source):
    ns = {}
    exec(source, ns)
    L = ns["make"]()
    L.execute(RECAP_FILE)
    L.execute("dgks.db.profile.deathRecap = false; dgks.db.profile.historyPve = true")
    return L


def hit_of(L):
    recs = list(L.eval("RECORDS").values())
    if not recs or recs[0]["flags"] is None or recs[0]["flags"]["hit"] is None:
        return None
    return dict(recs[0]["flags"]["hit"].items())


# ---------- Retail / Forever deaths: Blizzard's Death Recap ----------
L = runtime(death_src)


def retail_death(recap):
    L.execute("RECORDS, TIMERS = {}, {}; NOW = NOW + 60")
    L.execute("RECAP = " + recap)
    L.execute("FIRE('PLAYER_DEAD'); RUN_TIMERS()")
    return hit_of(L)


hit = retail_death("{ { sourceName = 'Zed-Other', spellName = 'Pyroblast', spellId = 11366, amount = 4321, overkill = 120 },"
                   "  { sourceName = 'Zed-Other', spellName = 'Fireball', spellId = 133, amount = 900 } }")
check("retail death: the recap's killing blow (event 1) goes to history", hit == {"ability": "Pyroblast", "spellId": 11366, "amount": 4321}, hit)
hit = retail_death("{ { sourceName = 'Zed-Other', event = 'SWING_DAMAGE', amount = 777 } }")
check("a melee killing blow: Melee, no spell ID", hit == {"ability": "Melee", "amount": 777}, hit)
hit = retail_death("{ { sourceName = 'Zed-Other', spellName = 'Pyroblast', spellId = 11366, amount = SECRET } }")
check("hidden damage: the ability alone", hit == {"ability": "Pyroblast", "spellId": 11366}, hit)
hit = retail_death("{ { sourceName = 'Zed-Other', spellName = SECRET, spellId = SECRET, amount = SECRET } }")
check("everything hidden: no killing blow, the death is still recorded", hit is None and len(L.eval("RECORDS")) == 1, hit)
hit = retail_death("{ { environmentalType = 'FALLING', amount = 2000 } }")
check("an environmental death: Falling and the damage", hit == {"ability": "Falling", "amount": 2000}, hit)
L.execute("RECORDS, TIMERS = {}, {}; NOW = NOW + 60; RECAP = { { sourceName = 'Zed-Other', spellName = 'Pyroblast', amount = 1 } }")
L.execute("ROWS_SHOWN = nil; local show = dgks.RenderDeathRecap; dgks.db.profile.deathRecap = true; "
          "function dgks:RenderDeathRecap(r) ROWS_SHOWN = #r.rows end")
L.execute("FIRE('PLAYER_DEAD'); RUN_TIMERS()")
check("the recap window still gets the same rows", L.eval("ROWS_SHOWN") == 1, L.eval("ROWS_SHOWN"))

# A retail kill has no killing blow (the combat log is closed)
L.execute(r'''RECORDS = {}; NOW = NOW + 60
dgks.TargetCheck = function() return true end
function dgks:ProcessKillshot() end function dgks:SendCM() end function dgks:Serialize() return "" end
dgks.db.profile.kstextM = { "a", "b", "c" }
GetPlayerInfoByGUID = function() return "x", "MAGE", "x", "Human", 2, "Zed", "Other" end''')
L.execute("FIRE('PARTY_KILL', 'Player-1-ME', 'Player-2-ZED')")
check("retail kill: recorded without a killing blow", len(L.eval("RECORDS")) == 1 and hit_of(L) is None)

# ---------- Classic: the combat log ----------
C = runtime(death_src.replace("WOW_PROJECT_ID = 1\n", "WOW_PROJECT_ID = 2\n"))
C.execute(r'''
COMBATLOG_OBJECT_TYPE_PLAYER = 0x400
COMBATLOG_OBJECT_CONTROL_PLAYER = 0x100
COMBATLOG_OBJECT_AFFILIATION_MINE = 0x1
bit = { band = function(a, b) local r, p = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end }
UnitName = function() return "Me", nil end
UnitGUID = function(u) if u == "player" then return "Player-1-ME" end if u == "pet" then return PETGUID end end
UnitHealth = function() return 1 end UnitHealthMax = function() return 100 end
dgks:OnEnable()
function dgks:ProcessKillshot() end function dgks:SendCM() end function dgks:Serialize() return "" end
dgks.db.profile.kstextM = { "a", "b", "c" }
CUR = {}
CombatLogGetCurrentEventInfo = function() return unpack(CUR) end
function LOG(...) CUR = { ... } FIRE("COMBAT_LOG_EVENT_UNFILTERED") end
''')
classic = C.eval("dgks.CombatLogEventHandler") is not None


def classic_kill(hits, killer="Player-1-ME", killer_flags="0x511"):
    C.execute("RECORDS = {}; NOW = NOW + 60")
    for h in hits:
        C.execute(h)
    C.execute(f"LOG(NOW, 'PARTY_KILL', false, '{killer}', 'Me', {killer_flags}, 0, 'Player-2-ZED', 'Zed', 0x548, 0)")
    C.execute("LOG(NOW, 'UNIT_DIED', false, '', nil, 0, 0, 'Player-2-ZED', 'Zed', 0x548, 0)")
    return hit_of(C)


SMITE = "LOG(NOW, 'SPELL_DAMAGE', false, 'Player-1-ME', 'Me', 0x511, 0, 'Player-2-ZED', 'Zed', 0x548, 0, 585, 'Smite', 2, 628, 0)"
hit = classic_kill([SMITE])
check("Classic kill: our last hit on the victim", hit == {"ability": "Smite", "spellId": 585, "amount": 628}, hit)
hit = classic_kill(["LOG(NOW, 'SWING_DAMAGE', false, 'Player-1-ME', 'Me', 0x511, 0, 'Player-2-ZED', 'Zed', 0x548, 0, 95, 0)"])
check("Classic kill by melee: Melee and the damage", hit == {"ability": "Melee", "amount": 95}, hit)
hit = classic_kill([SMITE, "LOG(NOW, 'SPELL_DAMAGE', false, 'Player-9-BOB', 'Bob', 0x512, 0, 'Player-2-ZED', 'Zed', 0x548, 0, 133, 'Fireball', 4, 50, 0)"])
check("someone else's later hit does not replace ours", hit == {"ability": "Smite", "spellId": 585, "amount": 628}, hit)
hit = classic_kill([SMITE, "NOW = NOW + 5"])
check("a hit more than 3 seconds before the kill is not the killing blow", hit is None, hit)
C.execute("PETGUID = 'Pet-0-1-WOLF'")
hit = classic_kill(["LOG(NOW, 'SPELL_DAMAGE', false, 'Pet-0-1-WOLF', 'Wolf', 0x1111, 0, 'Player-2-ZED', 'Zed', 0x548, 0, 16827, 'Claw', 1, 40, 0)"],
                   killer="Pet-0-1-WOLF", killer_flags="0x1111")
check("our pet's killing blow: the pet's ability", hit == {"ability": "Claw", "spellId": 16827, "amount": 40}, hit)

# Classic deaths: the last hit we took
C.execute("RECORDS = {}; NOW = NOW + 60")
C.execute("LOG(NOW, 'SPELL_DAMAGE', false, 'Player-2-ZED', 'Zed', 0x548, 0, 'Player-1-ME', 'Me', 0x511, 0, 116, 'Frostbolt', 16, 345, 10)")
C.execute("LOG(NOW, 'UNIT_DIED', false, '', nil, 0, 0, 'Player-1-ME', 'Me', 0x511, 0)")
hit = hit_of(C)
check("Classic death: the hit that killed us", hit == {"ability": "Frostbolt", "spellId": 116, "amount": 345}, hit)

print("FAILS:", fails)
sys.exit(1 if fails else 0)
