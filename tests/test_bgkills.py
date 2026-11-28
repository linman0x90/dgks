"""Our kills in battlegrounds, where PARTY_KILL hides the killer and the victim (dgks_bgkills.lua).

A hidden PARTY_KILL is our killing blow on a player when the Battleground Killing Blows statistic
rises with it and Total Honorable Kills follows; the victim is our target (or soft target) then,
recorded as likely. NPC kills, groupmates' kills, kills with nobody targeted, and anything outside
a battleground are left alone. Runs dgks.lua's retail PARTY_KILL handler with stand-ins for the game.

Needs Python 3 and lupa (pip install lupa). Run from anywhere:

    python tests/test_bgkills.py

Exits with 1 if any check fails.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from names_prelude import REPO

death_code = open(os.path.join(HERE, "test_death.py"), encoding="utf-8").read()
exec(death_code.split("fails = 0")[0])  # defines make(): dgks.lua loaded, History.Record captured

fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra if not cond else "")


L = make()
L.execute(r'''
INSTANCE = "pvp"
IsInInstance = function() return true, INSTANCE end
KB, HK = 17, 222
GetStatistic = function(id)
  if id == 1491 then return KB == 0 and "--" or tostring(KB) end
  if id == 588 then return tostring(HK) end
end
UnitName = function(u) if u == "player" then return "Me", nil end local x = UNITS[u] if x then return x.name, x.realm end end
UnitLevel = function(u) return UNITS[u] and UNITS[u].level end
UnitClass = function(u) return "x", UNITS[u] and UNITS[u].class end
dgks.db.profile.kstextM = { "a", "b", "c" }
KILLSHOTS = {}
function dgks:ProcessKillshot(chan, killer, victim) KILLSHOTS[#KILLSHOTS+1] = victim end
function dgks:SendCM() end
function dgks:Serialize() return '' end
''')
L.execute(open(os.path.join(REPO, "dgks_bgkills.lua"), encoding="utf-8").read())
L.execute("FIRE('ZONE_CHANGED_NEW_AREA')")  # entering the battleground: start from KB = 17


def kill(setup="", kb_rise=True, hk_rise=True, units=None):
    """A hidden PARTY_KILL; the statistics move as the probe saw: KB at once, HK 0.1 s later."""
    L.execute("RECORDS, KILLSHOTS = {}, {}")
    if units is not None:
        L.execute("UNITS = " + units)
    L.execute(setup)
    if kb_rise:
        L.execute("KB = KB + 1")
    L.execute("FIRE('PARTY_KILL', SECRET, SECRET)")
    if hk_rise:
        L.execute("C_Timer.After(0.1, function() HK = HK + 1 end)")
    L.execute("UNITS = {}")  # the target is gone a moment later, as in the probe
    L.execute("RUN_TIMERS(); NOW = NOW + 10")
    return [dict(r.items()) for r in L.eval("RECORDS").values()]


ENEMY = "{ target = { name = 'Sdot', realm = 'Other', player = true, enemy = true, level = 59, class = 'ROGUE' } }"

recs = kill(units=ENEMY)
check("our killing blow on a player: one kill of our target", len(recs) == 1 and recs[0]["k"] == "K" and recs[0]["o"] == "Sdot-Other", recs)
flags = recs[0]["flags"] if recs else None
check("recorded as likely, with the level and class read from the target",
      flags is not None and flags["guessed"] == 1 and flags["level"] == 59 and flags["class"] == "ROGUE", flags and dict(flags.items()))
check("no GUID is claimed", recs and recs[0].get("guid") is None)
check("announced like any killshot", list(L.eval("KILLSHOTS").values()) == ["Sdot-Other"])

recs = kill(units="{ softenemy = { name = 'Round', realm = 'Other', player = true, enemy = true, level = 60 } }")
check("no target: the soft target is the victim", len(recs) == 1 and recs[0]["o"] == "Round-Other", recs)

recs = kill(units=ENEMY, hk_rise=False)
check("killing blow without an honorable kill (an NPC): nothing recorded", recs == [], recs)

recs = kill(units=ENEMY, kb_rise=False)
check("a groupmate's kill (the statistic does not move): nothing recorded", recs == [], recs)

recs = kill(units="{ target = { name = 'Pal', realm = 'Mine', player = true, enemy = false } }")
check("our target is a friend: the victim cannot be named, nothing recorded", recs == [], recs)

recs = kill(units="{}")
check("nobody targeted: nothing recorded", recs == [], recs)

# The statistics count NPC and group kills in between: the next kill of ours is still found
recs = kill(units=ENEMY)
check("after NPC and group kills, our next player kill is found again", len(recs) == 1, recs)

# Two hidden kills in the same moment, both ours: each claims one rise
L.execute("RECORDS, KILLSHOTS = {}, {}")
L.execute("UNITS = " + ENEMY + "; KB = KB + 2")
L.execute("FIRE('PARTY_KILL', SECRET, SECRET); FIRE('PARTY_KILL', SECRET, SECRET)")
L.execute("C_Timer.After(0.1, function() HK = HK + 2 end); UNITS = {}; RUN_TIMERS(); NOW = NOW + 10")
check("two kills at once, both ours: two records", len(L.eval("RECORDS")) == 2)
L.execute("RECORDS = {}; UNITS = " + ENEMY + "; KB = KB + 1")
L.execute("FIRE('PARTY_KILL', SECRET, SECRET); FIRE('PARTY_KILL', SECRET, SECRET)")
L.execute("C_Timer.After(0.1, function() HK = HK + 2 end); UNITS = {}; RUN_TIMERS(); NOW = NOW + 10")
check("two kills at once, one ours: one record", len(L.eval("RECORDS")) == 1)

# Forever: first and last name, no realm
L.execute("RegionalUniqueNamesEnabled = function() return true end; GetNormalizedRealmName = function() return nil end")
uses = L.eval("dgks.UsesSurnames and dgks.UsesSurnames()")
recs = kill(units="{ target = { name = 'Chain', realm = 'Lightning', player = true, enemy = true, level = 60 } }")
if uses:
    check("Forever: the victim's first and last name", len(recs) == 1 and recs[0]["o"].startswith("Chain Lightning"), recs)
L.execute("RegionalUniqueNamesEnabled = nil; GetNormalizedRealmName = function() return 'Realm' end")

# Outside a battleground nothing happens (dungeons hide PARTY_KILL too)
L.execute("INSTANCE = 'party'")
recs = kill(units=ENEMY)
check("in a dungeon: nothing recorded", recs == [], recs)
L.execute("INSTANCE = 'arena'")
recs = kill(units=ENEMY)
check("in an arena (not probed): nothing recorded", recs == [], recs)

# Zoning in again resets the count; a statistic that cannot be read means no records, no errors
L.execute("INSTANCE = 'pvp'; FIRE('ZONE_CHANGED_NEW_AREA')")
recs = kill(units=ENEMY)
check("after zoning in again, kills are found", len(recs) == 1, recs)
L.execute("GetStatistic = function() return SECRET end; FIRE('ZONE_CHANGED_NEW_AREA')")
recs = kill(units=ENEMY)
recs += kill(units=ENEMY)
check("statistics hidden: nothing recorded, no error", recs == [] and not any("failed" in str(p) for p in L.eval("PRINTS").values()),
      (recs, [p for p in L.eval("PRINTS").values() if "failed" in str(p)]))

# A visible PARTY_KILL still goes the usual way (not through the statistics)
L.execute("GetStatistic = function() error('should not be read') end")
L.execute("RECORDS = {}; dgks.TargetCheck = function() return true end")
L.execute("FIRE('PARTY_KILL', 'Player-1-ME', 'Player-2-ZED'); RUN_TIMERS()")
check("a visible PARTY_KILL of ours is recorded as before, not as likely",
      len(L.eval("RECORDS")) == 1 and L.eval("RECORDS[1].flags") is None)

# ---------- Nameplates: the victim's plate vanishes dead just after the kill ----------
L.execute("""UnitIsDeadOrGhost = function(u) return UNITS[u] ~= nil and UNITS[u].dead == true end
GetStatistic = function(id)
  if id == 1491 then return KB == 0 and "--" or tostring(KB) end
  if id == 588 then return tostring(HK) end
end
FIRE('ZONE_CHANGED_NEW_AREA')""")
plate = L.eval("function(u) dgks.BGKills.OnPlateRemoved(u) end")


def plate_kill(target_units, plates, hk_rise=True, kb_rise=True):
    """A hidden kill; plates = [(delay, name, extra)] vanish after it, dead unless extra says otherwise."""
    L.execute("RECORDS, KILLSHOTS = {}, {}")
    L.execute("UNITS = " + target_units)
    if kb_rise:
        L.execute("KB = KB + 1")
    L.execute("FIRE('PARTY_KILL', SECRET, SECRET)")
    if hk_rise:
        L.execute("C_Timer.After(0.1, function() HK = HK + 1 end)")
    for i, (delay, name, extra) in enumerate(plates):
        L.execute(f"C_Timer.After({delay}, function() UNITS.nameplate{20 + i} = {{ name = '{name}', realm = 'Other', player = true, enemy = true, dead = true, level = 58 {extra} }}; "
                  f"PLATE('nameplate{20 + i}'); UNITS.nameplate{20 + i} = nil end)")
    L.execute("RUN_TIMERS(); NOW = NOW + 10")
    return [dict(r.items()) for r in L.eval("RECORDS").values()]


L.globals().PLATE = plate
TARGET = "{ target = { name = 'Ady', realm = 'Other', player = true, enemy = true, level = 60, class = 'MAGE' } }"
recs = plate_kill(TARGET, [(0.24, "Ady", "")])
check("our target's plate vanishes dead: a confirmed kill, not marked likely",
      len(recs) == 1 and recs[0]["o"] == "Ady-Other" and recs[0]["flags"]["guessed"] is None and recs[0]["flags"]["level"] == 58, recs)
recs = plate_kill(TARGET, [(0.21, "Easy", ""), (0.24, "Ady", "")])
check("several dead plates: our target among them wins", len(recs) == 1 and recs[0]["o"] == "Ady-Other" and recs[0]["flags"]["guessed"] is None, recs)
recs = plate_kill("{}", [(0.28, "Akoa", ""), (1.5, "Bloed", "")], hk_rise=False)
check("no target, no honorable kill (we had died): the dead plate names the victim, marked likely",
      len(recs) == 1 and recs[0]["o"] == "Akoa-Other" and recs[0]["flags"]["guessed"] == 1, recs)
recs = plate_kill(TARGET, [], hk_rise=False)
check("no honorable kill and no dead plate: an NPC kill, nothing recorded", recs == [], recs)
recs = plate_kill(TARGET, [(0.2, "Ady", "")], kb_rise=False)
check("a dead plate on a groupmate's kill: nothing recorded", recs == [], recs)
recs = plate_kill(TARGET, [(0.2, "Ady", ", dead = false")])
check("a plate that vanished alive (out of view) is not a death: target recorded as likely",
      len(recs) == 1 and recs[0]["flags"]["guessed"] == 1, recs)
recs = plate_kill(TARGET, [(0.2, "Ady", ", enemy = false")])
check("a friendly player's plate is ignored", len(recs) == 1 and recs[0]["flags"]["guessed"] == 1, recs)
recs = plate_kill("{}", [(1.2, "Late", "")], hk_rise=True)
check("a plate gone dead after the window does not count: nobody to name", recs == [], recs)
L.execute("INSTANCE = 'party'")
L.execute("UNITS = { nameplate1 = { name = 'X', realm = 'Y', player = true, enemy = true, dead = true } }; PLATE('nameplate1')")
L.execute("INSTANCE = 'pvp'")
recs = plate_kill("{}", [], hk_rise=True)
check("plates outside a battleground are not kept", recs == [], recs)

# ---------- Our deaths: the damage meter names the killer the Death Recap hides ----------
L.execute(open(os.path.join(REPO, "dgks_deathrecap.lua"), encoding="utf-8").read())
L.execute(r"""
dgks.db.profile.deathRecap = false; dgks.db.profile.guessKiller = false
Enum = { DamageMeterType = { Deaths = 9 }, DamageMeterSessionType = { Overall = 0, Current = 1 } }
RECAP = SECRET
RECAPS = {}
C_DeathRecap.GetRecapEvents = function(id) if id then return RECAPS[id] end return RECAP end
METER = SECRET
C_DamageMeter = { GetCombatSessionFromType = function(st, mt) if mt ~= 9 then return nil end return METER end }
function DIE() RECORDS = {}; FIRE('PLAYER_DEAD'); RUN_TIMERS() end
""")


def death(meter, recaps="{}"):
    L.execute("RECAPS = " + recaps)
    L.execute("METER = " + meter)
    L.execute("DIE(); NOW = NOW + 60")
    return [dict(r.items()) for r in L.eval("RECORDS").values()]


ME_DIED = "{ durationSeconds = 3384, combatSources = { { name = 'Civ Sr', deathTimeSeconds = 3368, deathRecapID = 387 }, { name = 'Me', isLocalPlayer = true, deathTimeSeconds = 3378, deathRecapID = 386 } } }"
CORRUPTION = "{ [386] = { { sourceName = 'Sirgoonie Dotsalot', spellName = 'Corruption', spellId = 172, amount = 359, overkill = 309 } } }"
recs = death(ME_DIED, CORRUPTION)
check("battleground death: the meter's recap names the killer", len(recs) == 1 and recs[0]["k"] == "D" and recs[0]["o"] == "Sirgoonie Dotsalot", recs)
hit = dict(recs[0]["flags"]["hit"].items()) if recs and recs[0]["flags"] and recs[0]["flags"]["hit"] else None
check("and the killing blow: Corruption, 359", hit == {"ability": "Corruption", "spellId": 172, "amount": 359}, hit)
recs = death(ME_DIED, CORRUPTION)
check("the same entry is never used for a second death: hidden as before", len(recs) == 1 and recs[0]["o"] == "Hidden by the game", recs)
recs = death("{ durationSeconds = 3500, combatSources = { { name = 'Me', isLocalPlayer = true, deathTimeSeconds = 3400, deathRecapID = 390 } } }",
             "{ [390] = { { sourceName = 'Old Death' } } }")
check("our entry from long ago is not this death", len(recs) == 1 and recs[0]["o"] == "Hidden by the game", recs)
# The meter is secret for a moment, then lists the death
L.execute("C_Timer.After(1.2, function() METER = { durationSeconds = 10, combatSources = { { isLocalPlayer = true, deathTimeSeconds = 9, deathRecapID = 391 } } } end)")
recs = death("SECRET", "{ [391] = { { sourceName = 'Late Killer', event = 'SWING_DAMAGE', amount = 80 } } }")
check("the meter readable a moment later: still found, melee killing blow",
      len(recs) == 1 and recs[0]["o"] == "Late Killer" and dict(recs[0]["flags"]["hit"].items()) == {"ability": "Melee", "amount": 80}, recs)
recs = death("{ durationSeconds = 10, combatSources = { { isLocalPlayer = true, deathTimeSeconds = 9, deathRecapID = 392 } } }",
             "{ [392] = { { sourceName = 'Sneaky', hideCaster = true, spellName = 'Ambush', amount = 900 } } }")
check("a hidden caster: no killer name, hidden as before", len(recs) == 1 and recs[0]["o"] == "Hidden by the game", recs)
L.execute("INSTANCE = 'party'")
recs = death("{ durationSeconds = 10, combatSources = { { isLocalPlayer = true, deathTimeSeconds = 9, deathRecapID = 393 } } }",
             "{ [393] = { { sourceName = 'Boss' } } }")
check("outside a battleground the meter is not used", len(recs) == 1 and recs[0]["o"] == "Hidden by the game", recs)
L.execute("INSTANCE = 'pvp'")

print("FAILS:", fails)
sys.exit(1 if fails else 0)
