"""The battleground probe (dgks_bgprobe.lua, development copies only): it loads, logs PARTY_KILL with
secret GUIDs, notices a rise in the scoreboard's killing blows, snapshots the units around us, and
never stops on an error.

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
C_Timer = { NewTicker = function(_, fn) TICK = fn return {} end }
IsInInstance = function() return true, "pvp" end
GetRealZoneText = function() return "Warsong Gulch" end
C_PvP = { IsBattleground = function() return true end }
KB = 0
C_PvP.GetScoreInfoByPlayerGuid = function() return { killingBlows = KB, honorableKills = KB, deaths = 0, name = "Me" } end
GetNumBattlefieldScores = function() return 1 end
GetBattlefieldScore = function() return "Me", KB, KB, 0 end
REQUESTS = 0
RequestBattlefieldScoreData = function() REQUESTS = REQUESTS + 1 end
UnitGUID = function(u) if u == "player" then return "Player-1-ME" end return SECRET end
UnitName = function(u) if u == "player" then return "Me" end return SECRET end
UNITS = { target = true, nameplate3 = true }
UnitExists = function(u) return UNITS[u] == true end
UnitIsPlayer = function(u) return true end
UnitCanAttack = function() return true end
UnitLevel = function() return 80 end
UnitIsDead = function() return SECRET end
UnitIsDeadOrGhost = function() return true end
UnitHealth = function() error("no health for you") end
UnitHealthMax = function() return 1000 end
UnitIsUnit = function() return SECRET end
UnitNameFromGUID = function() return SECRET end
GetPlayerInfoByGUID = function() error("secret argument") end
GetStatisticsCategoryList = function() return { 1 } end
GetCategoryNumAchievements = function() return 2 end
GetAchievementInfo = function(_, i) if i == 1 then return 1491, "Total Killing Blows" end return 9, "Fish caught" end
GetStatistic = function(id) return tostring(KB) end
GetPVPSessionStats = function() return KB, 0 end
GetBuildInfo = function() return "12.0.1" end
SlashCmdList = {}
dgks = { db = { global = {} } }
''')
L.execute(open(os.path.join(REPO, "dgks_bgprobe.lua"), encoding="utf-8").read())
L.execute('FIRE("PLAYER_LOGIN")')
probe = L.eval("SlashCmdList.DGKSPROBE")
state = lambda: L.eval("dgks.db.global.bgprobe")
lines = lambda: list(state()["log"].values())

check("off by default, nothing logged", state()["on"] is False and len(lines()) == 0)
L.execute('FIRE("PARTY_KILL", SECRET, SECRET)')
check("events are ignored while off", len(lines()) == 0)

probe("on")
text = "\n".join(lines())
check("on: build and where we are logged", "PROBE ON (12.0.1" in text and "instance=pvp zone=Warsong Gulch" in text, text)
check("the combat log's registration is never touched (a protected action)", L.eval("FORBIDDEN") is None)
check("the Killing blows statistic is found by name", "Total Killing Blows [1491]=0" in text and "Fish" not in text, text)

L.execute('FIRE("PARTY_KILL", SECRET, SECRET)')
text = "\n".join(lines())
check("PARTY_KILL with secret GUIDs logged, with what each lookup returned",
      "PARTY_KILL attacker=SECRET victim=SECRET" in text and "UnitNameFromGUID(victim)=SECRET" in text
      and "GetPlayerInfoByGUID(victim)=error" in text, text)
check("snapshot lists the player units with secret and failing checks shown",
      "target: exists=true" in text and "nameplate3:" in text and "dead=SECRET" in text
      and "health=error" in text and "2 player units" in text, text)

L.execute('TICK()')
check("the ticker asks for scoreboard data in a battleground", L.eval("REQUESTS") >= 1)
L.execute('FIRE("UPDATE_BATTLEFIELD_SCORE"); KB = 1; FIRE("UPDATE_BATTLEFIELD_SCORE")')
text = "\n".join(lines())
check("a rise in the scoreboard's killing blows is logged with a snapshot",
      "KILLING BLOW: scoreboard kb 0 -> 1" in text and "SNAP scoreboard kb up" in text, text)
check("the old scoreboard API row is shown", "old API: row 1 of 1: kb=1" in text, text)

L.execute('NOW = 200; FIRE("CRITERIA_UPDATE")')
check("statistics changes are logged", "Total Killing Blows [1491]=1" in "\n".join(lines()))

L.execute('C_PvP.GetScoreInfoByPlayerGuid = function() error("boom") end; FIRE("UPDATE_BATTLEFIELD_SCORE")')
check("a failing API is logged, not raised", "error: " in lines()[-1], lines()[-1])

L.execute('FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", SECRET)')
check("honor chat logged, secret text shown as SECRET", any("CHAT_MSG_COMBAT_HONOR_GAIN SECRET" in l for l in lines()))

for i in range(2100):
    L.execute('FIRE("CHAT_MSG_BG_SYSTEM_NEUTRAL", "x")')
check("the log is capped", len(lines()) == 2000, len(lines()))

probe("off")
n = len(lines())
L.execute('FIRE("PARTY_KILL", SECRET, SECRET)')
check("off: logging stops", len(lines()) == n and state()["on"] is False)
probe("clear")
check("clear empties the log", len(lines()) == 0)

print("FAILS:", fails)
sys.exit(1 if fails else 0)
