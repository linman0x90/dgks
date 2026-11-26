import os
import sys, re
from lupa import lua51

from names_prelude import REPO
HERE = os.path.dirname(os.path.abspath(__file__))
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)
strip = lambda s: re.sub(r"\|T[^|]*\|t ?|\|c[0-9a-f]{8}|\|r", "", s) if isinstance(s, str) else s
fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)


# ---------- Part 1: detection through dgks.lua's retail PARTY_KILL handler ----------
death_code = open(HERE + "/test_death.py").read()
exec(death_code.split("fails = 0")[0])  # defines make()
L = make()
L.execute(r'''
TEAM = {}
dgks.History.RecordTeamKill = function(_, a, t) TEAM[#TEAM+1] = a .. ">" .. t end
IsInRaid = function() return true end
UNITS = { raid3 = { guid = "Player-1-BOB" }, raid7 = { guid = "Player-1-CARA" } }
dgks.TargetCheck = function(_, g) return g:find("Player", 1, true) ~= nil end
''')
L.execute("FIRE('PARTY_KILL', 'Player-1-BOB', 'Player-2-ZED')")
L.execute("FIRE('PARTY_KILL', 'Creature-0-1', 'Player-2-ZED')")        # NPC killer: not a group member
L.execute("FIRE('PARTY_KILL', 'Player-1-CARA', 'Creature-0-99')")      # NPC victim
L.execute("FIRE('PARTY_KILL', 'Player-1-CARA', 'Player-1-BOB')")       # victim in our group
L.execute("FIRE('PARTY_KILL', 'Player-9-STRANGER', 'Player-2-ZED')")   # killer not in our group
L.execute("FIRE('PARTY_KILL', SECRET, 'Player-2-ZED')")                # hidden GUID
team = list(L.eval("TEAM").values())
check("raid member's kill on an enemy player becomes a team kill; NPCs, strangers, own group and secrets ignored",
      team == ["Player-1-BOB>Player-2-ZED"], team)

# A raid member's pet landing the killing blow counts as that member's team kill
L.execute("TEAM = {}; UNITS.raidpet3 = { guid = 'Pet-0-1-BOBWOLF' }")
L.execute("FIRE('PARTY_KILL', 'Pet-0-1-BOBWOLF', 'Player-2-ZED')")
L.execute("FIRE('PARTY_KILL', 'Pet-0-9-STRAYCAT', 'Player-2-ZED')")  # a pet outside the raid
team = list(L.eval("TEAM").values())
check("raid member's pet's kill is credited to the member; other pets ignored", team == ["Player-1-BOB>Player-2-ZED"], team)
L.execute("TEAM = {}; IsInRaid = function() return false end; UNITS = { party2 = { guid = 'Player-1-DAN' }, partypet2 = { guid = 'Pet-0-1-DANIMP' } }")
L.execute("FIRE('PARTY_KILL', 'Pet-0-1-DANIMP', 'Player-2-ZED')")
team = list(L.eval("TEAM").values())
check("party member's pet's kill is credited to the member", team == ["Player-1-DAN>Player-2-ZED"], team)
L.execute("IsInRaid = function() return true end; UNITS = { raid3 = { guid = 'Player-1-BOB' }, raid7 = { guid = 'Player-1-CARA' } }")

# ---------- Part 2: history ----------
sim_code = open(HERE + "/test_sync.py").read()
exec(sim_code.split("clock = Clock()")[0])  # Client, Network, Clock, STUBS, POST
clock = Clock()
net = Network()

EXTRA = r'''
issecretvalue = function(v) return false end
GUIDS = {
  ["Player-1-BOB"] = { "PALADIN", "Bob", "" },
  ["Player-1-DAN"] = { "WARRIOR", "Dan", "" },
  ["Player-9-PUG"] = { "ROGUE", "Pug", "Elsewhere" },
  ["Player-2-ZED"] = { "MAGE", "Zed", "Other" },
}
GetPlayerInfoByGUID = function(g) local i = GUIDS[g] if i then return "x", i[1], "x", "Human", 2, i[2], i[3] end end
dgks.db.profile.recordTeamKills = true
'''


def client(name):
    c = Client(name, net, clock)
    c.run(EXTRA)
    return c


A = net.clients["Alice"] = client("Alice")
C = net.clients["Cara"] = client("Cara")
# Bob (guild member, no dgks) kills Zed; Alice and Cara both see it
A.run("dgks.History:RecordTeamKill('Player-1-BOB', 'Player-2-ZED')")
clock.now += 2
C.run("dgks.History:RecordTeamKill('Player-1-BOB', 'Player-2-ZED')")
# A pug (not in guild) kills Zed: Alice records it, but it is not shared
A.run("dgks.History:RecordTeamKill('Player-9-PUG', 'Player-2-ZED')")
A.tick(); C.tick(); net.deliver()
rec = list(A.L.eval("dgks.History:PersonalRecords()").values())[0]
check("team kill record: victim, killer name and class", (rec["k"], rec["o"], rec["kn"], rec["kc"], rec["oc"]) == ("X", "Zed-Other", "Bob-Realm", "PALADIN", "MAGE"),
      (rec["k"], rec["o"], rec["kn"], rec["kc"]))
check("both witnesses keep it in personal history (pug kill too for Alice)", A.personal_count() == 2 and C.personal_count() == 1)
raw = A.L.eval("(function() local n = 0 for _, st in pairs(dgks.db.global.history.guilds['Bloodbath-Realm'].streams) do for _ in pairs(st.r) do n = n + 1 end end return n end)()")
check("guild store has both guild-member reports, not the pug kill", raw == 2, raw)
check("guild view counts Bob's kill once (duplicate reports merged)", A.guild_count() == 1)

# Bob installs dgks and records a kill himself; a witness report of the same kill must not double it
B = net.clients["Bob"] = client("Bob")
clock.now += 60
B.run("dgks.History:Record('K', 'Zed-Other', 'Player-2-ZED', 1, 0)")
clock.now += 3
A.run("dgks.History:RecordTeamKill('Player-1-BOB', 'Player-2-ZED')")
for c in (A, B, C):
    c.tick()
net.deliver()
check("own kill + witness report of the same kill count once", A.guild_count() == 2, A.guild_count())

# Leaderboard and guild opponents through the UI: team kills are Bob's kills
A.run(r'''
local gui = LibStub:NewLibrary("AceGUI-3.0", 1)
function gui:RegisterWidgetType() end
local function widget(kind)
  local w = { kind = kind, callbacks = {}, children = {}, frame = {} }
  setmetatable(w, { __index = function() return function() end end })
  function w:SetCallback(n, fn) self.callbacks[n] = fn end
  function w:AddChild(c) self.children[#self.children+1] = c end
  function w:ReleaseChildren() self.children = {} end
  function w:SetTabs(t) self.tabs = t end
  function w:SelectTab(v) self.callbacks.OnGroupSelected(self, "OnGroupSelected", v) end
  function w:SetRows(rows) ROWS = rows end
  return w
end
function gui:Create(kind) local w = widget(kind) if kind == "TabGroup" then LASTTABS = w end return w end
local dialog = LibStub:NewLibrary("AceConfigDialog-3.0", 1); function dialog:Open() end
UISpecialFrames = {}
RAID_CLASS_COLORS = {}
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", PALADIN = "Paladin" }
''')
A.L.execute(src("dgks_history_ui.lua"))
A.run("ROWS = dgks.History:ViewRows('leaders')")
rows = {strip(r["cells"][1]): [strip(c) for c in r["cells"].values()] for r in A.L.eval("ROWS").values()}
print("  leaderboard:", rows)
check("leaderboard: Bob has 2 kills (one witnessed, one his own), witnesses get nothing",
      "Bob" in rows and rows["Bob"][1] == "2" and "Alice" not in rows and "Cara" not in rows)
A.run("ROWS = dgks.History:ViewRows('guildopponents')")
rows = [[strip(c) for c in r["cells"].values()] for r in A.L.eval("ROWS").values()]
print("  guild opponents:", rows)
check("guild opponents: Zed killed twice by the guild, top killer Bob", rows and rows[0][1] == "2" and rows[0][5] == "Bob (2)")
A.run("ROWS = dgks.History:ViewRows('opponents')")
rows = [[strip(c) for c in r["cells"].values()] for r in A.L.eval("ROWS").values()]
check("My opponents ignores team kills", rows == [], rows)
A.run("ROWS = dgks.History:ViewRows('mine')")
rows = [[strip(c) for c in r["cells"].values()] for r in A.L.eval("ROWS").values()]
print("  my history:", [r[1:3] for r in rows])
check("My history lists team kills with the killer", any(r[1] == "Team kill" and r[2] == "Zed-Other (by Bob)" for r in rows))
mine, guild = A.L.eval("dgks.History:CountsFor('Zed-Other')")
check("player tooltip: guild 2 kills on Zed, personal 0", (guild["K"], mine["K"]) == (2, 0), (guild["K"], mine["K"]))
A.run("dgks.db.profile.recordTeamKills = false")
before = A.personal_count()
A.run("dgks.History:RecordTeamKill('Player-1-BOB', 'Player-2-ZED')")
check("option off: no team kill recorded", A.personal_count() == before)

# ---------- Sync gate ----------
def sends(setup):
    D = Client("Dora", net, clock)
    D.run("issecretvalue = function(v) return false end; SENT_OUT = 0; local s = dgks.SendCommMessage; function dgks:SendCommMessage(...) SENT_OUT = SENT_OUT + 1 end")
    D.run(setup)
    D.run("dgks.History:Record('K', 'Zed-Other', nil, 1, 0)")
    D.tick()
    return D.L.eval("SENT_OUT") > 0

check("battleground: sync sends", sends("IsInInstance = function() return true, 'pvp' end; InCombatLockdown = function() return true end"))
check("arena: sync sends", sends("IsInInstance = function() return true, 'arena' end"))
check("dungeon: sync waits", not sends("IsInInstance = function() return true, 'party' end"))
check("chat lockdown: sync waits", not sends("C_ChatInfo = { InChatMessagingLockdown = function() return true end }"))
check("open world in combat: sync sends", sends("InCombatLockdown = function() return true end"))
print("FAILS:", fails)
sys.exit(1 if fails else 0)
