import sys, re
from lupa import lua51

from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)
L = lua51.LuaRuntime(unpack_returned_tuples=True)

# Real LibStub + CallbackHandler + AceConfigRegistry, for its validator
L.execute(src("libs/LibStub/LibStub.lua"))
L.execute(src("libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"))
L.execute(src("libs/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua"))
L.execute(r'''
REAL_REG = LibStub("AceConfigRegistry-3.0")
REAL_LIBSTUB = LibStub
issecretvalue = nil
WOW_PROJECT_ID = 1
WOW_PROJECT_CLASSIC = 2
date = os.date
tinsert, tremove = table.insert, table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
GetTime = function() return 0 end
CreateFrame = function() local f = {} function f:SetScript() end function f:RegisterEvent() end return f end
C_Timer = { After = function() end }
IsInInstance = function() return false, "none" end
SlashCmdList = {}
REGISTERED, BLIZ = {}, {}
local function deepcopy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = deepcopy(v) end return o end
local stubs = {
  ["AceAddon-3.0"] = { NewAddon = function() return {} end },
  ["AceDB-3.0"] = { New = function(_, name, defaults) return { profile = deepcopy(defaults.profile), defaults = defaults, ResetProfile = function() end } end },
  ["AceConfigRegistry-3.0"] = { RegisterOptionsTable = function(_, name, fn) REGISTERED[name] = fn end, NotifyChange = function() end },
  ["AceConfigDialog-3.0"] = { AddToBlizOptions = function(_, app, name, parent) BLIZ[#BLIZ+1] = app .. " -> " .. name .. (parent and (" under " .. parent) or "") end, Open = function() end },
}
LibStub = setmetatable({}, { __call = function(_, name) return stubs[name] or {} end })
''')
L.execute(src("dgks.lua"))
L.execute(src("dgks_emotelist.lua"))
L.execute("GetBuildInfo = function() return '1.60.1' end")
L.execute(r'''
function dgks:SetSinkStorage() end
function dgks:RegisterComm() end
function dgks:Print() end
function dgks:GetSinkAce3OptionsDataTable() return { type = "group", name = "Output", args = { x = { type = "toggle", name = "x", get = function() end, set = function() end } } } end
dgks.History = {
  Initialize = function() end,
  SettingsArgs = function(_, base) return { historyShare = { type = "toggle", order = base, name = "Share", get = function() end, set = function() end } } end,
}
dgks:OnInitialize()
''')
reg = L.eval("REGISTERED")
fails = 0
def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)

print("  registered:", sorted(reg.keys()))
print("  blizzard panel:", list(L.eval("BLIZ").values()))
check("only Settings, File Setup and the launcher are registered (Overview is drawn by the window)",
      sorted(reg.keys()) == ["dG KillShot", "dG KillShot File Setup", "dG KillShot Settings"])
check("Blizzard panel has a single page", list(L.eval("BLIZ").values()) == ["dG KillShot -> dG KillShot"])

validate = L.eval("function(name) local t = REGISTERED[name]() local ok, err = pcall(REAL_REG.ValidateOptionsTable, REAL_REG, t, name) return ok, err, t end")
for name in ["dG KillShot Settings", "dG KillShot"]:
    ok, err, t = validate(name)
    check(f"AceConfig validates '{name}'", ok, "" if ok else err)

_, _, settings = validate("dG KillShot Settings")
tabs = sorted(((g["order"], k, g["name"]) for k, g in settings["args"].items()))
print("  settings tabs:", [(k, n) for _, k, n in tabs])
check("settings shown as tabs in the right order",
      settings["childGroups"] == "tab" and [k for _, k, _ in tabs] == ["general", "broadcasts", "duels", "screenshots", "ranks", "output", "history"])
hist = settings["args"]["history"]["args"]
check("Settings > History has history options and the reset buttons",
      "historyShare" in hist and "resetmaxks" in hist and "resetdgks" in hist and "resetHeader" in hist)
check("version exposed for the window", L.eval("dgks.version") is not None)

# Slash command routing
L.execute(r'''
CALLS = {}
function dgks:ShowMainWindow(t) CALLS[#CALLS+1] = "show:" .. tostring(t) end
function dgks:ToggleMainWindow(t) CALLS[#CALLS+1] = "toggle:" .. tostring(t) end
function dgks:ToggleDeathRecap() CALLS[#CALLS+1] = "deathrecap" end
function dgks:DumpRecap() CALLS[#CALLS+1] = "recap" end
for _, m in ipairs({ "", "  ", "history", "Settings", "options", "config", "deathrecap", "recap", "whatever" }) do SlashCmdList.DGKS(m) end
''')
calls = list(L.eval("CALLS").values())
print("  slash:", calls)
check("slash routing", calls == ["toggle:nil", "toggle:nil", "show:history", "show:settings", "show:settings", "show:settings", "deathrecap", "recap", "toggle:nil"])

# Version check: replies are listed in Settings > Broadcasts, not printed in chat
L.execute(r'''
time = os.time
PRINTS, SENT, REFRESHES = {}, {}, 0
function dgks:Print(...) PRINTS[#PRINTS+1] = table.concat({ ... }, " ") end
function dgks:SendCM(c, m) SENT[#SENT+1] = c .. ":" .. tostring(m) end
function dgks:RefreshSettingsTab() REFRESHES = REFRESHES + 1 end
''')
bc = lambda: validate("dG KillShot Settings")[2]["args"]["broadcasts"]["args"]
args = bc()
check("results line sits right under the version check button",
      args["versionresults"]["type"] == "description" and args["versionresults"]["order"] == args["versioncheck"]["order"] + 1)
check("results hidden before a check", L.eval("dgks.versionCheck") is None and args["versionresults"]["hidden"]() is True)
L.execute("dgks.db.profile.dobroadcasts = false")
check("button disabled with broadcasts off", bc()["versioncheck"]["disabled"]() is True)
L.execute("dgks.db.profile.dobroadcasts = true")
check("button enabled with broadcasts on", bc()["versioncheck"]["disabled"]() is False)

L.execute("dgks:VersionCheck()")
args = bc()
text = args["versionresults"]["name"]()
print("  waiting:", repr(text))
check("check sends the version ping", list(L.eval("SENT").values()) == ["dgksV:@project-version@"])
check("results shown once checked", args["versionresults"]["hidden"]() is False)
check("waiting text before replies", "Waiting for replies" in text and "Your version:" in text)
check("window settings tab redrawn on check", L.eval("REFRESHES") == 1)

for who, v in [("zed-Otherrealm", "12.0.009"), ("Amy", "12.0.010"), ("Bo", "12.0.011")]:
    L.eval("function(s, v) dgks:OnCommReceived('dgksVR', v, 'WHISPER', s) end")(who, v)
text = bc()["versionresults"]["name"]()
print("  replies:", repr(text))
lines = text.split("\n")
check("reply count shown", "Replies (3)" in text)
check("replies sorted by name", [l.strip().split(":")[0] for l in lines[2:]] == ["Amy", "Bo", "zed-Otherrealm"], lines)
# "OnCommReceived: ..." lines come from a --@debug@ block, which the release package comments out
chat = [p for p in L.eval("PRINTS").values() if not p.startswith("OnCommReceived:")]
check("nothing printed in chat", chat == [], chat)
check("window redrawn per reply", L.eval("REFRESHES") == 4)
L.eval("function() dgks:OnCommReceived('dgksVR', '12.0.001', 'WHISPER', 'Late') end")()
check("a new check clears old replies", (L.execute("dgks:VersionCheck()") or True) and "Late" not in bc()["versionresults"]["name"]())

cmp = L.eval("dgks.CompareVersions")
check("older, newer and same versions compared by number",
      (cmp("12.0.009", "12.0.010"), cmp("12.0.011", "12.0.010"), cmp("12.0.010", "12.0.010"), cmp("12.1.0", "12.0.99")) == (-1, 1, 0, 1))
check("unreadable versions compare as equal (no note)", cmp("@project-version@", "12.0.010") == 0 and cmp("12.0.010", None) == 0)
print("FAILS:", fails)
sys.exit(1 if fails else 0)
