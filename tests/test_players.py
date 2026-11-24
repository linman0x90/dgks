import sys, re
from lupa import lua51

from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)
strip = lambda s: re.sub(r"\|T[^|]*\|t ?|\|c[0-9a-f]{8}|\|r", "", s) if isinstance(s, str) else s
L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute(src("libs/LibStub/LibStub.lua"))
L.execute(src("libs/AceSerializer-3.0/AceSerializer-3.0.lua"))
L.execute(r'''
SECRET_MT = {}
function secret(v) return setmetatable({ v = v }, SECRET_MT) end
issecretvalue = function(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end
NOW = 1790000000
CLOCK = 100
time = function(t) if t then return os.time(t) end return NOW end
GetTime = function() return CLOCK end
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
GetNormalizedRealmName = function() return "Realm" end
UnitName = function() return "Alice" end
IsInGuild = function() return true end
GetGuildInfo = function() return "Bloodbath", "Member", 3, nil end
GetRealZoneText = function() return "Arathi Highlands" end
GetSubZoneText = function() return "Refuge Pointe" end
IsInInstance = function() return false, "none" end
C_Map = { GetBestMapForUnit = function() return 1417 end }
UISpecialFrames = {}
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 } }
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", PALADIN = "Paladin", ROGUE = "Rogue" }
SPECS = { [63] = { "Fire", "MAGE" }, [65] = { "Holy", "PALADIN" } }
GetSpecializationInfoByID = function(id) local s = SPECS[id] if s then return id, s[1], "", "", "DAMAGER", s[2] end end
GetSpecialization = function() return 1 end
GetSpecializationInfo = function(i) return 65 end
-- Units
UNITS = {}
UnitExists = function(u) return UNITS[u] ~= nil end
UnitIsPlayer = function(u) return UNITS[u] and UNITS[u].player or false end
UnitIsUnit = function(a, b) return a == "player" and b == "player" end
UnitGUID = function(u) return UNITS[u] and UNITS[u].guid end
UnitFullName = function(u) return UNITS[u].name, UNITS[u].realm end
UnitClass = function(u) if u == "player" then return "Paladin", "PALADIN" end return "x", UNITS[u].class end
UnitRace = function(u) return "x", UNITS[u].race end
UnitLevel = function(u) if u == "player" then return 80 end return UNITS[u].level end
UnitCanAttack = function(_, u) return UNITS[u] and UNITS[u].enemy or false end
CanInspect = function(u) return UNITS[u] ~= nil end
INSPECTS = {}
NotifyInspect = function(u) INSPECTS[#INSPECTS+1] = u end
ClearInspectPlayer = function() CLEARED = (CLEARED or 0) + 1 end
GetInspectSpecialization = function(u) return UNITS[u] and UNITS[u].spec or 0 end
GetPlayerInfoByGUID = function(g) for _, u in pairs(UNITS) do if u.guid == g then return "x", u.class, "x", u.race, 2, u.name, u.realm end end end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function(_, fn) TICK = fn end }
FRAMES = {}
CreateFrame = function() local f = { events = {} } function f:RegisterEvent(e) self.events[e] = true end function f:SetScript(_, fn) self.onevent = fn end FRAMES[#FRAMES+1] = f return f end
function FIRE(e, ...) for _, f in ipairs(FRAMES) do if f.events[e] and f.onevent then f.onevent(f, e, ...) end end end
local gui = LibStub:NewLibrary("AceGUI-3.0", 1)
function gui:RegisterWidgetType() end
local function widget(kind)
  local w = { kind = kind, callbacks = {}, children = {}, frame = {} }
  setmetatable(w, { __index = function() return function() end end })
  function w:SetCallback(n, fn) self.callbacks[n] = fn end
  function w:AddChild(c) self.children[#self.children+1] = c end
  function w:ReleaseChildren() self.children = {} end
  function w:SetTabs(t) self.tabs = t end
  function w:SelectTab(v) self.selected = v; self.callbacks.OnGroupSelected(self, "OnGroupSelected", v) end
  function w:SetRows(rows) ROWS = rows end
  return w
end
function gui:Create(kind) local w = widget(kind) if kind == "TabGroup" then LASTTABS = w end return w end
local dialog = LibStub:NewLibrary("AceConfigDialog-3.0", 1); function dialog:Open() end
dgks = { db = { profile = { historyShare = false, historyRetentionDays = 90, historyTooltip = true, guessKiller = true, inspectSpecs = true, deathRecap = true },
  global = { history = { guilds = {} } }, char = { history = { records = {} } } } }
LibStub("AceSerializer-3.0"):Embed(dgks)
function dgks:Print(m) ERRS = m end
''')
L.execute(src("dgks_players.lua"))
L.execute(src("dgks_history.lua"))
L.execute(src("dgks_history_ui.lua"))
L.execute("dgks.History:UpdateIdentity(); dgks.History:UpdateGuild(); dgks.Players:Enable()")

fails = 0
def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)

# 1. An enemy mage appears on a nameplate: noted and inspected
L.execute("""UNITS.nameplate2 = { player = true, enemy = true, guid = 'Player-2-ZED', name = 'Zed', realm = 'Other', class = 'MAGE', race = 'Scourge', level = 80, spec = 63 }
FIRE('NAME_PLATE_UNIT_ADDED', 'nameplate2')""")
check("enemy on nameplate is inspected", list(L.eval("INSPECTS").values()) == ["nameplate2"])
L.execute("FIRE('INSPECT_READY', 'Player-2-ZED')")
check("spec cached from INSPECT_READY", L.eval("dgks.Players:SpecFor('Player-2-ZED')") == 63)
check("inspect data cleared afterwards", L.eval("CLEARED") == 1)

# 2. Throttle: another enemy right away is not inspected; after 2s it is
L.execute("""UNITS.nameplate3 = { player = true, enemy = true, guid = 'Player-1-BOB', name = 'Bob', class = 'ROGUE', race = 'Human', level = 79, spec = 0 }
FIRE('NAME_PLATE_UNIT_ADDED', 'nameplate3')""")
check("second inspect within 2s is throttled", len(list(L.eval("INSPECTS").values())) == 1)
L.execute("CLOCK = CLOCK + 3; FIRE('NAME_PLATE_UNIT_ADDED', 'nameplate3')")
check("after 2s the next enemy is inspected", list(L.eval("INSPECTS").values())[-1] == "nameplate3")
L.execute("FIRE('INSPECT_READY', 'Player-1-BOB')")
check("spec 0 (unknown) is not stored", L.eval("dgks.Players:SpecFor('Player-1-BOB')") is None)

# 3. Friendly players are noted but not inspected; Inspect window open blocks; option off blocks
L.execute("""CLOCK = CLOCK + 3; UNITS.target = { player = true, enemy = false, guid = 'Player-1-FRI', name = 'Fri', class = 'PALADIN', race = 'Human', level = 80 }
FIRE('PLAYER_TARGET_CHANGED')""")
check("friendly target noted, not inspected", L.eval("dgks.Players:Lookup('Fri').class") == "PALADIN" and list(L.eval("INSPECTS").values())[-1] == "nameplate3")
L.execute("""CLOCK = CLOCK + 3; InspectFrame = { IsShown = function() return true end }
UNITS.mouseover = { player = true, enemy = true, guid = 'Player-3-ANN', name = 'Ann', realm = 'Third', class = 'MAGE', race = 'Human', level = 80, spec = 63 }
FIRE('UPDATE_MOUSEOVER_UNIT')""")
check("no inspect while the Inspect window is open", list(L.eval("INSPECTS").values())[-1] == "nameplate3")
L.execute("InspectFrame = nil; dgks.db.profile.inspectSpecs = false; CLOCK = CLOCK + 3; FIRE('UPDATE_MOUSEOVER_UNIT')")
check("no inspect with the option off", list(L.eval("INSPECTS").values())[-1] == "nameplate3")
L.execute("dgks.db.profile.inspectSpecs = true")

# 4. Secret unit identity: nothing noted, no error
L.execute("""UNITS.nameplate9 = { player = true, enemy = true, guid = secret('g'), name = secret('n'), class = 'MAGE' }
CLOCK = CLOCK + 3; FIRE('NAME_PLATE_UNIT_ADDED', 'nameplate9')""")
check("secret identity: ignored, no inspect, no error", list(L.eval("INSPECTS").values())[-1] == "nameplate3" and L.eval("ERRS") is None)

# 5. Death named by the Recap ("Zed-Other", no GUID): class, race, level, spec resolved by name; our spec + location
L.execute("UNITS = {}")  # the killer is no longer visible
rec = L.eval("dgks.History:Record('D', 'Zed-Other', nil, nil, nil)")
check("death record resolves killer class/race/level/spec by name",
      (rec["oc"], rec["orc"], rec["ol"], rec["os"], rec["p"]) == ("MAGE", "Scourge", 80, 63, 1), (rec["oc"], rec["orc"], rec["ol"], rec["os"]))
check("death record has our spec, zone and subzone", (rec["cs"], rec["z"], rec["sz"]) == (65, "Arathi Highlands", "Refuge Pointe"))
rec2 = L.eval("dgks.History:Record('D', 'Bob', nil, nil, nil)")
check("bare name resolves too (same realm)", rec2["oc"] == "ROGUE" and rec2["os"] is None)
rec3 = L.eval("dgks.History:Record('D', 'Nobody', nil, nil, nil)")
check("unknown name: no class guessed", rec3["oc"] is None and rec3["p"] is None)
rec4 = L.eval("dgks.History:Record('D', 'Hidden by the game', nil, nil, nil, { unknown = true })")
check("unknown killer: no lookup", rec4["oc"] is None)

# 6. History rows and tooltip
L.execute("ROWS = dgks.History:ViewRows('mine')")
rows = [[strip(c) for c in r["cells"].values()] for r in L.eval("ROWS").values()]
print("  my history:", rows[0])
check("My history shows the opponent's level, spec + class and location", rows[0][3] == "80" and rows[0][4] == "Fire Mage" and rows[0][5] == "Refuge Pointe, Arathi Highlands")
tip = []
L.execute("TTL = {}")
tt = L.eval('{ AddLine = function(_, t) TTL[#TTL+1] = t end, AddDoubleLine = function(_, l, r) TTL[#TTL+1] = l .. ": " .. r end }')
list(L.eval("ROWS").values())[0]["tip"](tt)
lines = [strip(x) for x in L.eval("TTL").values()]
print("  tooltip:", lines)
check("tooltip: killer level/race/spec/class, you with spec, location",
      "Killer: Level 80 Undead Fire Mage" in lines and "Player: Alice, Level 80 Holy Paladin" in lines and "Location: Refuge Pointe, Arathi Highlands" in lines)
L.execute("ROWS = dgks.History:ViewRows('opponents')")
rows = [[strip(c) for c in r["cells"].values()] for r in L.eval("ROWS").values()]
check("My opponents shows spec + class", ["Zed-Other", "Fire Mage"] == rows[[r[0] for r in rows].index("Zed-Other")][:2], rows)

# 7. Levels of the killer and the victim
def tooltip_of(index=0):
    L.execute("TTL = {}")
    tt = L.eval('{ AddLine = function(_, t) TTL[#TTL+1] = t end, AddDoubleLine = function(_, l, r) TTL[#TTL+1] = l .. ": " .. r end }')
    list(L.eval("ROWS").values())[index]["tip"](tt)
    return [strip(x) for x in L.eval("TTL").values()]

L.execute("""dgks.db.char.history.records = {}; dgks.db.profile.recordTeamKills = true
UNITS = { nameplate5 = { player = true, enemy = true, guid = 'Player-2-ZED', name = 'Zed', realm = 'Other', class = 'MAGE', race = 'Scourge', level = 78 } }""")
rec = L.eval("dgks.History:Record('K', 'Zed-Other', 'Player-2-ZED', 1, 0)")
check("victim's level read live from a nameplate (beats the cached 80)", rec["ol"] == 78, rec["ol"])
L.execute("UNITS.nameplate5.level = -1")
rec = L.eval("dgks.History:Record('K', 'Zed-Other', 'Player-2-ZED', 2, 0)")
check("a victim shown as ?? is stored as -1", rec["ol"] == -1, rec["ol"])
L.execute("dgks.db.char.history.records = { dgks.db.char.history.records[2] }; ROWS = dgks.History:ViewRows('mine')")
row = [strip(c) for c in list(L.eval("ROWS").values())[0]["cells"].values()]
check("Level column shows ?? for -1", row[3] == "??", row)
check("kill tooltip names the victim with level", "Victim: Level ?? Undead Fire Mage" in tooltip_of(), tooltip_of())

# Team kill: the killer is a raid member we can see
L.execute("""dgks.db.char.history.records = {}
UNITS.nameplate5.level = 79
UNITS.raid3 = { player = true, guid = 'Player-1-BOB', name = 'Bob', realm = 'Realm', class = 'ROGUE', level = 70 }""")
rec = L.eval("dgks.History:RecordTeamKill('Player-1-BOB', 'Player-2-ZED')")
check("team kill stores the killer's and the victim's level", (rec["kl"], rec["ol"]) == (70, 79), (rec["kl"], rec["ol"]))
L.execute("ROWS = dgks.History:ViewRows('mine')")
lines = tooltip_of()
check("team kill tooltip: victim and killing blow with levels",
      "Victim: Level 79 Undead Fire Mage" in lines and "Killing blow: Bob, Level 70 Rogue" in lines, lines)

# Killer no longer visible: the level comes from the player cache
L.execute("""UNITS.mouseover = { player = true, guid = 'Player-1-CARA', name = 'Cara', realm = 'Realm', class = 'MAGE', race = 'Gnome', level = 75 }
FIRE('UPDATE_MOUSEOVER_UNIT')
UNITS.elsewhere = UNITS.mouseover; UNITS.mouseover = nil""")
rec = L.eval("dgks.History:RecordTeamKill('Player-1-CARA', 'Player-2-ZED')")
check("killer out of sight: level from the player cache", rec["kl"] == 75, rec["kl"])
L.execute("UNITS.elsewhere2 = { player = true, guid = 'Player-1-NEW', name = 'Newt', realm = 'Realm', class = 'MAGE' }")
rec = L.eval("dgks.History:RecordTeamKill('Player-1-NEW', 'Player-2-ZED')")
check("killer never seen: no level", rec["kl"] is None and rec["kn"] == "Newt-Realm", rec["kl"])

print("FAILS:", fails)
sys.exit(1 if fails else 0)
