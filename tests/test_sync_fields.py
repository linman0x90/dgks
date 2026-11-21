"""Guild history sync: every record field reaches other guild members unchanged.

One member records a kill, a death to an unknown killer, a death to a guessed killer, a duel win,
a duel loss and a team kill, which together fill every shared record field. The test then checks
that the copies another member gets live (R messages) and a member who joins later gets through
catch-up sync (S/Q/B/E messages) match the author's records field for field.

Runs on retail names and on Forever names ("First Surname"), with the sender given both as
"First Surname" and as "First Surname-Realm".

dgks_history.lua runs in a Lua 5.1 sandbox with stand-ins for the game API, and messages go through
the real AceSerializer. Needs Python 3 and lupa (pip install lupa). Run from anywhere:

    python tests/test_sync_fields.py

Exits with 1 if any check fails.
"""
import os
import re
import sys

from lupa import lua51

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULES = {"dgks_history.lua"}


def read(path):
    with open(os.path.join(REPO, path), encoding="utf-8") as f:
        return f.read().replace("\r\n", "\n")


def name_helpers():
    """dgks.lua's real name helpers (dgks.SplitName, dgks.PlayerFullName, dgks.UsesSurnames)."""
    s = read("dgks.lua")
    i = s.index("-- Forever: characters have a first name")
    j = s.index("function dgks.PlayerFullName()")
    j = s.index("\nend\n", j) + 5
    return ("local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end\n"
            + s[i:j])


def source(path):
    text = read(path)
    if path in MODULES:
        text = name_helpers() + "\n" + text
    return text


# Game API stand-ins. ... = this client's name, the shared clock
STUBS = r'''
local name, clock = ...
time = function(t) if t then return os.time(t) end return clock.now end
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
issecretvalue = nil
UNKNOWNOBJECT = "Unknown"
GetNormalizedRealmName = function() return "Realm" end
UnitName = function() return name end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitLevel = function() return 80 end
UnitGUID = function() return nil end
GetRealZoneText = function() return "Arathi Highlands" end
GetSubZoneText = function() return "" end
IsInInstance = function() return false, "none" end
InCombatLockdown = function() return false end
IsInGuild = function() return true end
GetGuildInfo = function() return "Bloodbath", "Member", 3, nil end
ROSTER = {}
GetNumGuildMembers = function() return #ROSTER end
GetGuildRosterInfo = function(i) return ROSTER[i], "Member", 3, 80, "Warrior", "", "", "", true end
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
ChatFrame_AddMessageEventFilter = function() end
C_GuildInfo = { GuildRoster = function() end }
TICKERS = {}
C_Timer = { After = function(_, fn) fn() end, NewTicker = function(_, fn) TICKERS[#TICKERS+1] = fn end }
FRAMES = {}
CreateFrame = function()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript(_, fn) self.onevent = fn end
  FRAMES[#FRAMES+1] = f
  return f
end
math.randomseed(#name * 7919 + name:byte(1))
'''

# The addon object. ... = this client's name, the network's send function
ADDON = r'''
local name, net = ...
local AceSerializer = LibStub("AceSerializer-3.0")
dgks = { db = { profile = { historyShare = true, historyRetentionDays = 90 }, global = {}, char = {} } }
AceSerializer:Embed(dgks)
function dgks:Print(...) print("  [" .. name .. "]", ...) end
function dgks:RegisterComm() end
function dgks:SendCommMessage(prefix, msg, dist, target, prio)
  net(name, prefix, msg, dist, target)
end
'''

# Everything a real kill or death can fill in: opponent class, race, level and spec, our spec,
# subzone, map, and a guild member's spec for team kills
RICH = r'''
dgks.db.profile.recordTeamKills = true
dgks.Players = {
  Lookup = function(_, name) return { class = "MAGE", race = "Gnome", level = 79, spec = 63 } end,
  MySpec = function() return 71 end,
  SpecFor = function() return 250 end,
}
GetPlayerInfoByGUID = function(g)
  if g == "Player-1-ZED" then return "Mage", "MAGE", "Gnome", "Gnome", 2, ZEDNAME, ZEDSECOND end
  if g == "Player-1-MATE" then return "Death Knight", "DEATHKNIGHT", "Human", "Human", 2, MATENAME, MATESECOND end
end
UnitGUID = function(u) if u == "target" then return "Player-1-ZED" end end
UnitLevel = function() return 80 end
GetSubZoneText = function() return "Refuge Pointe" end
C_Map = { GetBestMapForUnit = function() return 14 end }
'''

RECORD_ALL = r'''
dgks.History:Record('K', 'Zed', 'Player-1-ZED', 3, 2)
dgks.History:Record('D', 'Hidden by the game', nil, 0, 0, { unknown = true })
dgks.History:Record('D', 'Zed', 'Player-1-ZED', 0, 0, { guessed = 3 })
dgks.History:Record('W', 'Zed', 'Player-1-ZED', 0, 0)
dgks.History:Record('L', 'Zed', 'Player-1-ZED', 0, 0)
dgks.History:RecordTeamKill('Player-1-MATE', 'Player-1-ZED')
'''

# Records as sorted "key=value" lines. personal: only the shared ones (they have a stream epoch).
DUMP = r'''(function(which)
  local out = {}
  local list = which == "personal" and dgks.History:PersonalRecords() or dgks.History:GuildRecords()
  for _, r in ipairs(list) do
    if which ~= "personal" or r.e then
      local keys = {}
      for k, v in pairs(r) do if type(k) == "string" and k:sub(1, 1) ~= "_" then keys[#keys+1] = k .. "=" .. tostring(v) end end
      table.sort(keys)
      out[#out+1] = table.concat(keys, " ")
    end
  end
  table.sort(out)
  return table.concat(out, "\n")
end)'''


class Clock:
    now = 1790000000


class Network:
    """Delivers GUILD messages to everyone else and WHISPERs to their target.
    sender_style: how the game hands receivers the sender's name, "bare" or "realm"."""

    def __init__(self, sender_style="bare"):
        self.clients, self.inbox, self.sender_style = {}, [], sender_style

    def send(self, sender, prefix, msg, dist, target):
        self.inbox.append((sender, msg, dist, target))

    def deliver(self):
        while self.inbox:
            batch, self.inbox = self.inbox, []
            for sender, msg, dist, target in batch:
                shown = sender if self.sender_style == "bare" else sender + "-Realm"
                if dist == "GUILD":
                    for n, c in list(self.clients.items()):
                        if n != sender:
                            c.receive(msg, dist, shown)
                elif dist == "WHISPER":
                    to = target.rsplit("-", 1)[0]
                    if to in self.clients:
                        self.clients[to].receive(msg, dist, shown)


class Client:
    def __init__(self, name, net, clock, setup):
        self.name = name
        L = self.L = lua51.LuaRuntime(unpack_returned_tuples=True)
        L.execute(STUBS, name, clock)
        L.execute(source("libs/LibStub/LibStub.lua"))
        L.execute(source("libs/AceSerializer-3.0/AceSerializer-3.0.lua"))
        L.execute(ADDON, name, net.send)
        L.execute(source("dgks_history.lua"))
        L.execute("dgks.History.InstallTooltip = function() end")
        L.execute(setup)
        L.execute("dgks.History:Initialize()")
        L.execute("dgks.History:Enable()")
        L.execute("for _, f in ipairs(FRAMES) do if f.onevent then f.onevent(f, 'GUILD_ROSTER_UPDATE') end end")
        L.execute("dgks.History:UpdateIdentity(); dgks.History:UpdateRoster()")
        self._recv = L.eval("function(m, d, s) dgks:OnHistoryComm('dgksH', m, d, s) end")
        net.clients[name] = self

    def receive(self, msg, dist, sender):
        self._recv(msg, dist, sender)

    def tick(self):
        self.L.execute("for _, fn in ipairs(TICKERS) do fn() end")

    def records(self, which):
        return self.L.eval(DUMP)(which)


def settle(net, clock, clients):
    for _ in range(4):
        clock.now += 20
        for c in clients:
            c.tick()
        net.deliver()


def shared_fields():
    block = read("dgks_history.lua")
    block = block[block.index("local FIELDS = {"):block.index("local REQUIRED")]
    return sorted(re.findall(r"^\s*(\w+) = \{", block, re.M))


FIELDS = shared_fields()
fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra if not cond else "")


def setup_for(me, mate, names, forever):
    roster = ", ".join(f'"{n}-Realm"' for n in names)
    code = RICH + f"ROSTER = {{ {roster} }}\n"
    if forever:
        first, last = me.split(" ")
        mfirst, mlast = mate.split(" ")
        code += f'''
RegionalUniqueNamesEnabled = function() return true end
UnitName = function(u) if u == "player" then return "{first}", "{last}" end end
ZEDNAME, ZEDSECOND = "Zed", "Stone"
MATENAME, MATESECOND = "{mfirst}", "{mlast}"
'''
    else:
        code += f'''
ZEDNAME, ZEDSECOND = "Zed", "Other"
MATENAME, MATESECOND = "{mate}", ""
'''
    return code


def scenario(label, names, forever=False, sender_style="bare"):
    clock, net = Clock(), Network(sender_style)
    author, mate, late = names
    A = Client(author, net, clock, setup_for(author, mate, names, forever))
    B = Client(mate, net, clock, setup_for(mate, mate, names, forever))

    A.L.execute(RECORD_ALL)
    A.tick(); B.tick(); net.deliver()
    mine = A.records("personal")
    live = B.records("guild")

    # A member who logs in later gets the records through catch-up sync
    C = Client(late, net, clock, setup_for(late, mate, names, forever))
    settle(net, clock, [A, B, C])
    caught_up = C.records("guild")

    used = sorted(set(re.findall(r"(?:^| )([a-z]+)=", mine, re.M)))
    print(f"\n== {label}")
    check("6 records shared (kill, death to unknown, death to guess, duel win, duel loss, team kill)",
          mine.count("\n") == 5, mine)
    # lg marks imports from the old kill/death lists, which stay in personal history
    check("every shared field is filled in", sorted(set(FIELDS) - {"lg"}) == used, sorted(set(FIELDS) - {"lg"} - set(used)))
    check("live copy matches field for field", live == mine, "\n" + live + "\n--- expected\n" + mine)
    check("caught-up copy matches field for field", caught_up == mine, "\n" + caught_up + "\n--- expected\n" + mine)


scenario("retail", ("Alice", "Bob", "Cara"))
scenario("Forever, sender as 'First Surname'", ("Ann Smith", "Bo Reed", "Cy Ward"), forever=True)
scenario("Forever, sender as 'First Surname-Realm'", ("Ann Smith", "Bo Reed", "Cy Ward"), forever=True, sender_style="realm")
print("\nFailures:", fails)
sys.exit(1 if fails else 0)
