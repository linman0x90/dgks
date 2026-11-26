import sys, re
from lupa import lua51

from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)
strip = lambda s: re.sub(r"\|T[^|]*\|t ?|\|c[0-9a-f]{8}|\|r", "", s) if isinstance(s, str) else s
fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)


L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute(src("libs/LibStub/LibStub.lua"))
L.execute(r'''
NOW = 1790000000
time = function(t) if t then return os.time(t) end return NOW end
date = function(f, t) return os.date(f, t or NOW) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
GetNormalizedRealmName = function() return "Realm" end
UnitName = function() return "Alice" end
UnitClass = function() return "Warrior", "WARRIOR" end
IsInGuild = function() return true end
GetGuildInfo = function() return "Bloodbath", "Member", 3, nil end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() end }
UISpecialFrames = {}
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, ROGUE = { r = 1, g = 0.96, b = 0.41 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", ROGUE = "Rogue", WARRIOR = "Warrior" }
GetSpecializationInfoByID = function(id) if id == 63 then return 63, "Fire", "", 135810, "DAMAGER", "MAGE" end end
SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 1, IG_CHARACTER_INFO_CLOSE = 2, IG_CHARACTER_INFO_TAB = 3, U_CHAT_SCROLL_BUTTON = 4 }
SOUNDS = {}
PlaySound = function(k) SOUNDS[#SOUNDS+1] = k end
ERRORS = {}

-- Generic frame stub: any unknown method is a no-op; Show/Hide fire OnShow/OnHide like the game
local Frame = {}
local function new(kind, parent, name)
  local f = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, hooks = {}, children = {},
    w = 0, h = 0, text = "", points = 0 }, Frame)
  if parent then parent.children[#parent.children+1] = f end
  if name then _G[name] = f; f.name = name end
  return f
end
Frame.__index = function(t, k)
  local m = rawget(Frame, k)
  if m then return m end
  if type(k) == "string" and k:match("^%u") then return function() end end
  return nil
end
function Frame:visible() local f = self while f do if not rawget(f, "shown") then return false end f = rawget(f, "parent") end return true end
local function fire(f, script)
  if f.scripts[script] then f.scripts[script](f) end
  for _, h in ipairs(f.hooks[script] or {}) do h(f) end
  for _, c in ipairs(f.children) do if c.shown then fire(c, script) end end
end
function Frame:Show() if self.shown then return end self.shown = true if self:visible() then fire(self, "OnShow") end end
function Frame:Hide() if not self.shown then return end local v = self:visible() self.shown = false if v then fire(self, "OnHide") end end
function Frame:SetShown(on) if on then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self:visible() end
function Frame:SetScript(s, fn) self.scripts[s] = fn end
function Frame:GetScript(s) return self.scripts[s] end
function Frame:HookScript(s, fn) self.hooks[s] = self.hooks[s] or {} table.insert(self.hooks[s], fn) end
function Frame:SetText(t) self.text = t if self.kind == "EditBox" then local f = self.scripts.OnTextChanged if f then f(self) end for _, h in ipairs(self.hooks.OnTextChanged or {}) do h(self) end end end
function Frame:GetText() return self.text end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:GetWidth() if self.w > 0 then return self.w end if rawget(self, "parent") then return self.parent:GetWidth() end return 0 end
function Frame:GetHeight() if self.h > 0 then return self.h end if rawget(self, "parent") then return self.parent:GetHeight() end return 0 end
function Frame:GetStringWidth() return #tostring(self.text) * 6 end
function Frame:SetID(i) self.id = i end
function Frame:GetID() return self.id end
function Frame:SetParent(p) self.parent = p p.children[#p.children+1] = self end
function Frame:GetFrameStrata() return "HIGH" end
function Frame:GetFrameLevel() return 1 end
function Frame:NumLines() return rawget(self, "lines") or 0 end
function Frame:AddLine() self.lines = (rawget(self, "lines") or 0) + 1 end
function Frame:AddDoubleLine() self.lines = (rawget(self, "lines") or 0) + 1 end
function Frame:SetOwner() self.lines = 0 end
function Frame:CreateTexture() return new("Texture", self) end
function Frame:CreateFontString() local fs = new("FontString", self) return fs end
function Frame:SetDataProvider(dp, retain)
  self.data = dp.rows
  self.retained = retain
  -- draw the first rows through the view's initializer, reusing row frames like a ScrollBox
  if not rawget(self, "rowFrames") then self.rowFrames = {} end
  for i = 1, math.min(25, #dp.rows) do
    local row = self.rowFrames[i] or new("Button", self)
    self.rowFrames[i] = row
    self.view.init(row, dp.rows[i])
  end
end

CreateFrame = function(kind, name, parent, template)
  local f = new(kind, parent, name)
  f.template = template
  if template == "ButtonFrameTemplate" then
    f.Inset = new("Frame", f)
    function f:SetTitle(t) self.title = t end
    function f:SetPortraitToAsset(t) self.portraitAsset = t end
  elseif template == "SearchBoxTemplate" then
    f.Instructions = new("FontString", f)
  elseif template == "PanelTabButtonTemplate" then
    if not rawget(parent, "Tabs") then parent.Tabs = {} end
    table.insert(parent.Tabs, f)
  end
  return f
end
UIParent = new("Frame", nil)
UIParent.w, UIParent.h = 1920, 1080
GameTooltip = new("GameTooltip", UIParent)
CreateScrollBoxListLinearView = function()
  return { SetElementExtent = function() end, SetElementInitializer = function(self, kind, fn) self.init = fn end }
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, bar, view) box.view = view end }
CreateDataProvider = function(rows) return { rows = rows } end
ScrollBoxConstants = { RetainScrollPosition = "retain" }
PanelTemplates_SetNumTabs = function(f, n) f.numTabs = n end
PanelTemplates_SetTab = function(f, i) f.selectedTab = i end

-- AceGUI / AceConfigDialog stubs
local gui = LibStub:NewLibrary("AceGUI-3.0", 1)
RELEASED_CHILDREN = 0
function gui:Create(kind)
  local w = { kind = kind, frame = new("Frame", UIParent) }
  setmetatable(w, { __index = function() return function() end end })
  function w:ReleaseChildren() RELEASED_CHILDREN = RELEASED_CHILDREN + 1 end
  function w:SetWidth(v) self.width = v end
  function w:SetHeight(v) self.height = v end
  function w:DoLayout() LAYOUTS = (LAYOUTS or 0) + 1 end
  GROUPS = (GROUPS or 0) + 1
  return w
end
OPENED = {}
local dialog = LibStub:NewLibrary("AceConfigDialog-3.0", 1)
function dialog:Open(app, container) OPENED[#OPENED+1] = app; container.app = app end

dgks = { version = "9.9.9", db = { profile = { historyShare = true, historyRetentionDays = 90, historyTooltip = true, guessKiller = true,
  maxstreak = 7, maxdeathstreak = 3 }, global = { history = { guilds = {} } }, char = { history = { records = {} } } } }
function dgks:Print() end
function dgks:GetStreaks() return 2, 0 end
''')
for f in ["dgks_history.lua", "dgks_players.lua", "dgks_history_ui.lua", "dgks_window.lua"]:
    L.execute(src(f))
L.execute(r'''
local H = dgks.History
H:UpdateIdentity(); H:UpdateGuild()
local recs = dgks.db.char.history.records
local function add(k, o, ago, extra)
  local r = { k = k, o = o, t = NOW - ago, a = "Alice-Realm", c = "WARRIOR", z = "Arathi Highlands", sz = "Refuge Pointe" }
  for key, v in pairs(extra or {}) do r[key] = v end
  recs[#recs+1] = r
end
add("K", "Zed-Other", 3 * 86400, { oc = "MAGE", os = 63 })
add("K", "Zed-Other", 86400, { oc = "MAGE" })
add("K", "Mia-Realm", 3600, { oc = "ROGUE" })
add("D", "Zed-Other", 1800, { oc = "MAGE" })
add("W", "Bob-Realm", 600)
add("K", "Zed-Other", 60, { oc = "MAGE", st = 2 })
add("D", "Unknown", 30, { u = "unavailable" })
add("K", "Old-Realm", 40 * 86400, { oc = "ROGUE" })
''')

# --- Overview numbers ---
s = L.eval("dgks.History:OverviewStats(6)")
t = s["totals"]
check("totals", (t["K"], t["D"], t["W"], t["L"]) == (5, 2, 1, 0), dict(t.items()))
days = list(s["days"].values())
check("14 days, oldest first, today last", len(days) == 14 and days[-1]["start"] <= 1790000000 < days[-1]["start"] + 86400 + 3600)
print("  last days K/D:", [(d["K"], d["D"]) for d in days[-5:]])
check("activity counts kills and deaths per day, ignoring older than 14 days and duels",
      sum(d["K"] for d in days) == 4 and sum(d["D"] for d in days) == 2)
prey = list(s["prey"].values())
check("top prey: Zed 3, then Mia, Old", [(o["name"], o["count"]) for o in prey] == [("Zed-Other", 3), ("Mia", 1), ("Old", 1)],
      [(o["name"], o["count"]) for o in prey])
check("top predators skip the unknown killer", [o["name"] for o in s["predators"].values()] == ["Zed-Other"])
recent = list(s["recent"].values())
check("recent: newest first, 6 entries", len(recent) == 6 and recent[0]["o"] == "Unknown" and recent[1]["k"] == "K")

# --- Window ---
L.execute("dgks:ToggleMainWindow()")
f = L.eval("dgksMainFrame")
check("window opens on Overview", f["shown"] and f["selectedTab"] == 1 and f["title"] == "dG KillShot" and f["portraitAsset"])
check("three bottom tabs", [t["text"] for t in f["Tabs"].values()] == ["Overview", "History", "Settings"] and f["numTabs"] == 3)
check("Escape closes it", "dgksMainFrame" in list(L.eval("UISpecialFrames").values()))
check("status line", "8 personal records" in f["status"]["text"], f["status"]["text"])
check("subtitle shows the character and guild", "Alice" in strip(f["subtitle"]["text"]) and "Bloodbath" in f["subtitle"]["text"])

def find_text(frame, pred, depth=0):
    out = []
    for c in frame["children"].values():
        if c["kind"] == "FontString" and isinstance(c["text"], str) and pred(c["text"]):
            out.append(c)
        out += find_text(c, pred, depth + 1)
    return out

def shown_texts(frame):
    out = []
    def walk(fr):
        if not fr["shown"]:
            return
        for c in fr["children"].values():
            if c["kind"] == "FontString" and c["shown"] and isinstance(c["text"], (str, int, float)):
                out.append(strip(str(c["text"])))
            walk(c)
    walk(frame)
    return out

texts = shown_texts(f)
check("overview cards show kills, deaths, K/D, duels and streaks",
      all(x in texts for x in ["KILLS", "DEATHS", "K/D", "5", "2", "2.50", "1-0", "BEST STREAK", "7", "3", "100% won"]), texts[:40])
check("top prey list shows Zed with 3", "Zed-Other" in texts and "3" in texts)
check("recent shows killer line and time ago", any(x.startswith("Killed Zed") for x in texts) and "1m ago" in texts)
check("chart labels today", "Today" in texts)
check("no Lua errors on overview", True)

L.execute("dgks:ShowMainWindow('history')")
hist = L.eval("dgksMainFrame.Inset.children[2]")
check("History tab shows, Overview hides", f["selectedTab"] == 2 and hist["shown"] and not L.eval("dgksMainFrame.Inset.children[1]")["shown"])
check("subtitle hidden on History (view picker there)", not f["subtitle"]["shown"])
box = hist["scrollBox"]
rows = list(box["data"].values())
check("My history lists all 8, newest first", len(rows) == 8 and strip(rows[0]["cells"][3]).startswith("Unknown"), strip(rows[0]["cells"][3]))
cells = [strip(c["text"]) for c in box["rowFrames"][1]["cells"].values()]
print("  first row:", cells)
check("rows drawn through the ScrollBox initializer", cells[1] == "Death" and len(cells) == 8)
check("opponent cells carry class icons (question mark for unknown)", all("|T" in r["cells"][3] for r in rows) and "QuestionMark" in rows[0]["cells"][3])
fire_row = rows[-1]["cells"][3]
check("spec icon used when the spec is known", "|T135810:" in fire_row or any("|T135810:" in r["cells"][3] for r in rows), fire_row)

# Kind filter chips
kinds = hist["kinds"]
chips = list(kinds["chips"].values())
check("type chips: All, Kills, Deaths, Duels, Team kills", [strip(c["label"]["text"]) for c in chips] == ["All", "Kills", "Deaths", "Duels", "Team kills"])
chips[2]["scripts"]["OnClick"](chips[2])
rows = list(box["data"].values())
check("Deaths chip filters to deaths", len(rows) == 2 and all(strip(r["cells"][2]) == "Death" for r in rows) and box["retained"] is None)
check("selected chip shows its underline", chips[2]["line"]["shown"] and not chips[0]["line"]["shown"])
chips[0]["scripts"]["OnClick"](chips[0])

# Search
hist["search"]["SetText"](hist["search"], "Mia")
rows = list(box["data"].values())
check("search narrows to Mia", len(rows) == 1 and "Mia" in strip(rows[0]["cells"][3]))
hist["search"]["SetText"](hist["search"], "")

# Sorting by header
hdr = list(hist["headers"].values())
check("headers for My history", [strip(h["label"]["text"]) for h in hdr if h["shown"]] == ["When", "Type", "Opponent", "Class", "Killer lvl", "Victim lvl", "Location", "Streak"])
check("sort arrow on When only", hdr[0]["arrow"]["shown"] and not hdr[2]["arrow"]["shown"])
hdr[2]["scripts"]["OnClick"](hdr[2])
rows = list(box["data"].values())
names = [strip(r["cells"][3]) for r in rows]
print("  by opponent:", names)
check("clicking Opponent sorts A-Z, arrow moves, scroll kept", names[0].startswith("Bob") and hdr[2]["arrow"]["shown"] and not hdr[0]["arrow"]["shown"] and box["retained"] == "retain")
hdr[2]["scripts"]["OnClick"](hdr[2])
names = [strip(r["cells"][3]) for r in box["data"].values()]
check("clicking again reverses", names[0].startswith("Zed"), names[0])

# View chips
views = list(hist["views"]["chips"].values())
check("view chips", [strip(c["label"]["text"]) for c in views] == ["My history", "Guild history", "My opponents", "Guild opponents", "Guild leaderboard"])
views[2]["scripts"]["OnClick"](views[2])
rows = list(box["data"].values())
check("My opponents view: type chips hidden, Zed first by kills", not kinds["shown"] and strip(rows[0]["cells"][1]) == "Zed-Other" and rows[0]["cells"][3] == "3",
      [strip(r["cells"][1]) for r in rows])
check("headers switched", [strip(h["label"]["text"]) for h in hist["headers"].values() if h["shown"]][:3] == ["Opponent", "Class", "Kills"])
for v in views:
    v["scripts"]["OnClick"](v)
check("every view draws", True)
views[0]["scripts"]["OnClick"](views[0])
check("back on My history: type chips shown", kinds["shown"])

# Tooltip from a row
row = box["rowFrames"][1]
row["scripts"]["OnEnter"](row)
check("row tooltip shows", L.eval("GameTooltip")["lines"] > 0)

# History change refreshes the list
L.execute("table.insert(dgks.db.char.history.records, { k = 'K', o = 'New-Realm', t = NOW, a = 'Alice-Realm' }); dgks.History:NotifyChanged()")
check("new record appears while the list shows, scroll kept", len(box["data"]) == 9 and box["retained"] == "retain")

# Settings
L.execute("dgks:ShowMainWindow('settings')")
check("Settings opens the AceConfig table in the tab", list(L.eval("OPENED").values())[-1] == "dG KillShot Settings" and f["selectedTab"] == 3)
L.execute("dgks:ShowMainWindow('overview')")
check("leaving Settings releases its widgets", L.eval("RELEASED_CHILDREN") >= 1)
L.execute("dgks:ShowMainWindow('settings')")
check("Settings reuses one AceGUI group", L.eval("GROUPS") == 1)
L.execute("dgksMainFrame.Inset.w, dgksMainFrame.Inset.h = 880, 520; LAYOUTS = 0; dgks:ShowMainWindow('overview'); dgks:ShowMainWindow('settings')")
g = L.eval("dgksMainFrame.Inset.children[3].group")
check("Settings group gets the panel's size and is laid out (now and next frame)", g["width"] == 868 and g["height"] == 508 and L.eval("LAYOUTS") == 2, (g["width"], g["height"], L.eval("LAYOUTS")))

# Toggle behaviour
L.execute("dgks:ToggleMainWindow('history')")
check("toggle with another tab switches", f["shown"] and f["selectedTab"] == 2)
L.execute("dgks:ToggleMainWindow('history')")
check("toggle with the current tab closes", not f["shown"])
L.execute("dgks:ToggleMainWindow()")
check("reopens on the last tab", f["shown"] and f["selectedTab"] == 2)
L.execute("dgks:ToggleMainWindow(); dgks.History:ToggleWindow()")
check("old History entry point", f["shown"] and f["selectedTab"] == 2)
check("open/close sounds", 1 in list(L.eval("SOUNDS").values()) and 2 in list(L.eval("SOUNDS").values()))
print("FAILS:", fails)
sys.exit(1 if fails else 0)
