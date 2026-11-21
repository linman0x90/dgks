import os
import sys, json
from lupa import lua51

from names_prelude import REPO
W = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
targ = json.load(open(W + "/targetable_emotes.json"))
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)
fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)


def load(version, saved):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.execute(src("libs/LibStub/LibStub.lua"))
    L.execute(src("libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"))
    L.execute(src("libs/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua"))
    L.execute(r'''
local version, saved = ...
REAL_REG = LibStub("AceConfigRegistry-3.0")
GetBuildInfo = function() return version, "1", "Nov 20 2026", 0 end
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
REGISTERED = {}
local function deepcopy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = deepcopy(v) end return o end
local stubs = {
  ["AceAddon-3.0"] = { NewAddon = function() return {} end },
  ["AceDB-3.0"] = { New = function(_, name, defaults)
      local p = deepcopy(defaults.profile)
      for k, v in pairs(saved) do p[k] = v end
      return { profile = p, defaults = defaults, ResetProfile = function() end } end },
  ["AceConfigRegistry-3.0"] = { RegisterOptionsTable = function(_, name, fn) REGISTERED[name] = fn end, NotifyChange = function() end },
  ["AceConfigDialog-3.0"] = { AddToBlizOptions = function() end, Open = function() end },
}
LibStub = setmetatable({}, { __call = function(_, name) return stubs[name] or {} end })
''', version, L.table_from(saved))
    L.execute(src("dgks.lua"))
    L.execute(src("dgks_emotelist.lua"))
    L.execute(r'''
function dgks:SetSinkStorage() end
function dgks:RegisterComm() end
function dgks:Print() end
function dgks:GetSinkAce3OptionsDataTable() return { type = "group", name = "Output", args = { x = { type = "toggle", name = "x", get = function() end, set = function() end } } } end
dgks.History = { Initialize = function() end,
  Tile = function(order, label, value) return { type = "description", order = order, name = label } end,
  MainOptionArgs = function() return {} end, SettingsArgs = function() return {} end }
dgks:OnInitialize()
''')
    return L


def selects(L):
    settings = L.eval('REGISTERED["dG KillShot Settings"]()')
    ok, err = L.eval("function(t) local ok, err = pcall(REAL_REG.ValidateOptionsTable, REAL_REG, t, 's') return ok, err or '' end")(settings)
    out = {}
    def walk(g):
        for k, v in g["args"].items():
            if v["type"] == "select" and k in ("doemote", "duelemotewin", "duelemoteloss"):
                vals = dict(v["values"]().items())
                order = list(v["sorting"]().values())
                out[k] = (vals, order)
            elif v["type"] == "group":
                walk(v)
    walk(settings)
    return ok, err, out


for version, prod, name in [("1.60.1", "wowf", "Forever"), ("12.1.5", "wow", "retail"), ("1.15.9", "wow_classic_era", "Classic Era")]:
    L = load(version, {"doemote": "BELCH", "duelemotewin": "DOOM", "duelemoteloss": "QUACK"})
    ok, err, sel = selects(L)
    check(f"{name}: Settings table validates", ok, err)
    want = set(targ[prod])
    for key, (vals, order) in sel.items():
        keys = set(vals) - {"none"}
        check(f"{name}: {key} offers exactly the {len(want)} targetable emotes + None",
              keys == want and "none" in vals, f"missing {sorted(want - keys)[:5]} extra {sorted(keys - want)[:5]}")
        check(f"{name}: {key} sorting lists every value once, None first",
              order[0] == "none" and sorted(order) == sorted(vals) and len(order) == len(set(order)))
    p = L.eval("dgks.db.profile")
    quack = "QUACK" if prod == "wow" else "BOW"
    check(f"{name}: saved BELCH->BURP, DOOM->THREATEN, QUACK kept on retail else reset to BOW",
          (p["doemote"], p["duelemotewin"], p["duelemoteloss"]) == ("BURP", "THREATEN", quack),
          (p["doemote"], p["duelemotewin"], p["duelemoteloss"]))
    labels = sel["doemote"][0]
    print(f"  {name}: e.g.", [labels[k] for k in ["APPLAUD", "ATTACKMYTARGET", "YW", "FACEPALM"]])

L = load("1.60.1", {"doemote": "none", "duelemotewin": "garbage", "duelemoteloss": "KISS"})
p = L.eval("dgks.db.profile")
check("none stays none, unknown resets to default, valid choice kept",
      (p["doemote"], p["duelemotewin"], p["duelemoteloss"]) == ("none", "BOW", "KISS"))
print("FAILS:", fails)
sys.exit(1 if fails else 0)
