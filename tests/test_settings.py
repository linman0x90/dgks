"""Settings do what they say, and nothing goes ahead when its setting is off.

- Screenshot on duel win: used for duel wins, which no longer take the killshot screenshot options
- Broadcast to/from Battleground: decides whether battleground and arena broadcasts are heard
- Execute sound: the player and NPC options each cover only their own targets; hidden where the
  combat log is closed to addons (retail, Forever)
- Sound Channel: sounds play when game sound and the chosen channel are on, whatever Sound Effects is
- Reset to default files: a copy, so it keeps working and later edits are saved
- Option labels that described something the addon doesn't do

dgks.lua runs in a Lua 5.1 sandbox with stand-ins for the game API. Needs Python 3 and lupa
(pip install lupa). Run from anywhere:

    python tests/test_settings.py

Exits with 1 if any check fails.
"""
import os
import sys
from lupa import lua51

from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)
HERE = os.path.dirname(os.path.abspath(__file__))
death_src = open(HERE + "/test_death.py").read().split("fails = 0")[0]

fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)


STUBS = r'''
time = time or os.time
SHOTS, SOUNDS = 0, {}
Screenshot = function() SHOTS = SHOTS + 1 end
PlaySoundFile = function(f, ch) SOUNDS[#SOUNDS+1] = f .. "|" .. tostring(ch) return true end
CVARS = { Sound_EnableAllSound = "1", Sound_EnableSFX = "1", Sound_EnableMusic = "1", Sound_EnableAmbience = "1" }
GetCVar = function(k) return CVARS[k] end
dgks.History.Record = function() end
function dgks:ScrollText() end
function dgks:SendCM() end
function dgks:Serialize() return "x" end
function dgks:EmoteAt() end
dgks.TargetCheck = function() return true end
local p = dgks.db.profile
for k, v in pairs({ kstextS = {}, kstext = "$k killed $v", kstextM = { "a", "b" }, dueltext = "$k beat $v",
  doemote = "none", dotxtemote = false, dueltxtemote = false, duelemotewin = "none", dobroadcasts = true,
  killList = {}, killlog = {}, maxstreak = 0, style = "dota", ksrank = { 1, 2, 4, 6, 8, 10, 12 },
  kssound = { "a.ogg", "b.ogg", "c.ogg", "d.ogg", "e.ogg", "f.ogg", "g.ogg" }, kssoundM = { "m1.ogg", "m2.ogg" },
  soundpath = "S/", dosound = true, soundchannel = "Master", kssoundE = "finishhim.ogg" }) do p[k] = v end
'''


def runtime(classic=False):
    ns = {"lua51": lua51, "src": src}
    exec(death_src.replace("WOW_PROJECT_ID = 1\n", "WOW_PROJECT_ID = 2\n") if classic else death_src, ns)
    L = ns["make"]()
    L.execute(STUBS)
    return L


# ---------- Screenshots ----------
L = runtime()


def shots(code):
    L.execute("SHOTS = 0; NOW = NOW + 30")
    L.execute(code)
    return L.eval("SHOTS")


L.execute("dgks.db.profile.doscreenshotonkill = true; dgks.db.profile.doscreenshotonduelwin = false")
check("duel win: no screenshot with only 'on Killshot' on", shots("dgks:DuelTX('Bob', NOW)") == 0)
L.execute("dgks.db.profile.doscreenshotonduelwin = true")
check("duel win: screenshot with 'on duel win' on", shots("dgks:DuelTX('Bob', NOW)") == 1)
L.execute("dgks.db.profile.doscreenshotonkill = false; dgks.db.profile.doscreenshotonstreak = true; dgks.db.profile.maxstreak = 0")
L.execute("dgks.db.profile.doscreenshotonduelwin = false")
check("duel win: no screenshot from 'on new max killing streak'", shots("dgks:DuelTX('Bob', NOW)") == 0)
L.execute("dgks.db.profile.doscreenshotonkill = true")
check("kill: screenshot with 'on Killshot' on", shots("dgks:KillshotTX('Zed', NOW, 'Player-2-ZED')") == 1)

# ---------- Broadcasts heard in battlegrounds, arenas and group finder instances ----------
L.execute(r'''
HEARD = 0
function dgks:ProcessKillshot() HEARD = HEARD + 1 end
function dgks:Deserialize() return true, "Bob", "Zed", 1, 1, 0 end
''')


def heard(instance_type, dobg, doraid):
    L.execute(f"IsInInstance = function() return true, '{instance_type}' end; FIRE('PLAYER_ENTERING_WORLD')")
    L.execute(f"HEARD = 0; dgks.db.profile.dobg = {str(dobg).lower()}; dgks.db.profile.doraid = {str(doraid).lower()}")
    L.execute("dgks:OnCommReceived('dgks', 'x', 'INSTANCE_CHAT', 'Bob')")
    return L.eval("HEARD") == 1


check("battleground: ignored with 'Battleground' off (Party/Raid on)", heard("pvp", False, True) is False)
check("battleground: heard with 'Battleground' on (Party/Raid off)", heard("pvp", True, False) is True)
check("arena: follows 'Battleground' too", heard("arena", False, True) is False and heard("arena", True, False) is True)
check("group finder dungeon: follows 'Party/Raid'", heard("party", True, False) is False and heard("party", False, True) is True)
L.execute("IsInInstance = function() return false, 'none' end; FIRE('PLAYER_ENTERING_WORLD')")

# ---------- Sound channel ----------


def played(channel, **cvars):
    L.execute("SOUNDS = {}; CVARS = { Sound_EnableAllSound = '1', Sound_EnableSFX = '1', Sound_EnableMusic = '1', Sound_EnableAmbience = '1' }")
    for k, v in cvars.items():
        L.execute(f"CVARS.{k} = '{v}'")
    L.execute(f"dgks.db.profile.soundchannel = '{channel}'; dgks:SoundEventHandler(nil, 'x.ogg')")
    return list(L.eval("SOUNDS").values())


check("Master channel plays with Sound Effects off", played("Master", Sound_EnableSFX=0) == ["x.ogg|Master"], played("Master", Sound_EnableSFX=0))
check("Music channel plays with Sound Effects off", played("Music", Sound_EnableSFX=0) == ["x.ogg|Music"])
check("SFX channel silent with Sound Effects off", played("SFX", Sound_EnableSFX=0) == [])
check("Music channel silent with Music off", played("Music", Sound_EnableMusic=0) == [])
check("nothing with all game sound off", played("Master", Sound_EnableAllSound=0) == [])
L.execute("dgks.db.profile.dosound = false")
check("nothing with 'Play Sounds' off", played("Master") == [])
L.execute("dgks.db.profile.dosound = true; dgks.db.profile.soundchannel = 'Master'")

# ---------- Execute sound (Classic: the combat log) ----------
C = runtime(classic=True)
C.execute(r'''
COMBATLOG_OBJECT_TYPE_PLAYER = 0x400
COMBATLOG_OBJECT_CONTROL_PLAYER = 0x100
COMBATLOG_OBJECT_AFFILIATION_MINE = 0x1
bit = { band = function(a, b) local r, p = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end }
floor = math.floor
TARGET = nil
GetUnitName = function(u) if u == "target" then return TARGET end end
UnitIsEnemy = function() return true end
UnitHealth = function() return 20 end
UnitHealthMax = function() return 100 end
dgks.db.profile.doexecutepercent = 25
''')
n = 0


def execute_sound(player_target, doexecutesound, doexecutesoundpve):
    global n
    n += 1  # a new target each time, so the "already under the threshold" memory doesn't interfere
    flags = "0x548" if player_target else "0xa48"
    C.execute(f"SOUNDS = {{}}; TARGET = 'T{n}'; dgks.db.profile.doexecutesound = {str(doexecutesound).lower()}; dgks.db.profile.doexecutesoundpve = {str(doexecutesoundpve).lower()}")
    C.execute(f"dgks:CombatLogEventHandler(nil, 1, 'SPELL_DAMAGE', false, 'Player-1-ME', 'Me', 0x511, 0, 'G{n}', 'T{n}', {flags}, 0, 1, 'x', 1, 50)")
    return len(C.eval("SOUNDS")) > 0


check("execute: player target, player option on", execute_sound(True, True, False) is True)
check("execute: player target, only the NPC option on: silent", execute_sound(True, False, True) is False)
check("execute: NPC target, NPC option on", execute_sound(False, False, True) is True)
check("execute: NPC target, only the player option on: silent", execute_sound(False, True, False) is False)

# ---------- Options: what is shown, labels, and the sound file reset ----------
OPTIONS_SETUP = r'''
issecretvalue = nil
WOW_PROJECT_CLASSIC = 2
date = os.date
tinsert, tremove = table.insert, table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
GetTime = function() return 0 end
CreateFrame = function() local f = {} function f:SetScript() end function f:RegisterEvent() end return f end
C_Timer = { After = function() end }
IsInInstance = function() return false, "none" end
SlashCmdList = {}
REGISTERED = {}
local function deepcopy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = deepcopy(v) end return o end
local stubs = {
  ["AceAddon-3.0"] = { NewAddon = function() return {} end },
  ["AceDB-3.0"] = { New = function(_, name, defaults) return { profile = deepcopy(defaults.profile), defaults = defaults, ResetProfile = function() end } end },
  ["AceConfigRegistry-3.0"] = { RegisterOptionsTable = function(_, name, fn) REGISTERED[name] = fn end, NotifyChange = function() end },
  ["AceConfigDialog-3.0"] = { AddToBlizOptions = function() end, Open = function() end },
}
LibStub = setmetatable({}, { __call = function(_, name) return stubs[name] or {} end })
'''
OPTIONS_INIT = r'''
GetBuildInfo = function() return '1.60.1' end
function dgks:SetSinkStorage() end
function dgks:RegisterComm() end
function dgks:Print() end
function dgks:GetSinkAce3OptionsDataTable() return { type = "group", name = "Output", args = {} } end
dgks.History = { Initialize = function() end, SettingsArgs = function() return {} end }
dgks:OnInitialize()
'''


def options(project_id):
    O = lua51.LuaRuntime(unpack_returned_tuples=True)
    O.execute(f"WOW_PROJECT_ID = {project_id}")
    O.execute(OPTIONS_SETUP)
    O.execute(src("dgks.lua"))
    O.execute(src("dgks_emotelist.lua"))
    O.execute(OPTIONS_INIT)
    return O


R, K = options(1), options(2)
general = lambda O: O.eval("REGISTERED['dG KillShot Settings']()")["args"]["general"]["args"]
for key in ("doexecutesound", "doexecutesoundpve", "doexecutepercent"):
    check(f"retail: '{key}' hidden (no combat log)", general(R)[key]["hidden"]() is True)
    check(f"Classic: '{key}' shown", general(K)[key]["hidden"]() is False)
check("prepare sound label names duels as well as battlegrounds", "duel" in general(R)["dopreparesound"]["name"])
check("chat option no longer mentions a /dgks log", "/dgks" not in general(R)["dochatbox"]["name"], general(R)["dochatbox"]["name"])

files = R.eval("REGISTERED['dG KillShot File Setup']()")["args"]
reset = files["resetkssound"]["func"]
reset()
files["kssound1"]["set"](None, "custom.ogg")
check("an edit after a reset leaves the defaults alone", R.eval("dgks.db.defaults.profile.kssound[1]") == "ownage.ogg")
check("an edit after a reset is not the defaults table (so it is saved)", R.eval("dgks.db.profile.kssound ~= dgks.db.defaults.profile.kssound") is True)
reset()
check("reset again: back to the default file", R.eval("dgks.db.profile.kssound[1]") == "ownage.ogg")

print("FAILS:", fails)
sys.exit(1 if fails else 0)
