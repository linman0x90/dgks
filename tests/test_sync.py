import sys
from lupa import lua51

from names_prelude import REPO


def src(f):
    return open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)


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
ROSTER = { "Alice-Realm", "Bob-Realm", "Cara-Realm" }
GetNumGuildMembers = function() return #ROSTER end
ONLINE = {}
GetGuildRosterInfo = function(i) local n = ROSTER[i] return n, "Member", 3, 80, "Warrior", "", "", "", ONLINE[n] ~= false end
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
ChatFrame_AddMessageEventFilter = function(event, fn) FILTERS = FILTERS or {} FILTERS[event] = fn end
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

POST = r'''
local name, net, legacy = ...
local AceSerializer = LibStub("AceSerializer-3.0")
dgks = { db = { profile = { historyShare = true, historyRetentionDays = 90 }, global = {}, char = {} } }
if legacy then
  dgks.db.profile.killList = { Victim = { "01/02/24 10:11:12", "03/04/24 05:06:07" } }
  dgks.db.profile.deathList = { Killer = { "02/02/24 10:11:12" } }
end
AceSerializer:Embed(dgks)
function dgks:Print(...) print("  [" .. name .. "]", ...) end
function dgks:RegisterComm() end
function dgks:SendCommMessage(prefix, msg, dist, target, prio)
  net(name, prefix, msg, dist, target)
end
'''


class Client:
    def __init__(self, name, network, clock, legacy=False, patch=None):
        self.name = name
        L = self.L = lua51.LuaRuntime(unpack_returned_tuples=True)
        L.execute(STUBS, name, clock)
        L.execute(src("libs/LibStub/LibStub.lua"))
        L.execute(src("libs/AceSerializer-3.0/AceSerializer-3.0.lua"))
        L.execute(POST, name, network.send, legacy)
        self.load(patch)
        self._recv = L.eval("function(m, d, s) dgks:OnHistoryComm('dgksH', m, d, s) end")

    def load(self, patch=None):
        """Load dgks_history.lua, or load it again over the same saved data (an addon update).
        patch: a function that edits the source first (a newer version)."""
        code = src("dgks_history.lua")
        if patch:
            code = patch(code)
        L = self.L
        L.execute("TICKERS = {} FRAMES = {}")
        L.execute(code)
        L.execute("dgks.History.InstallTooltip = function() end")
        L.execute("dgks.History:Initialize()")
        L.execute("dgks.History:Enable()")
        L.execute("for _, f in ipairs(FRAMES) do if f.onevent then f.onevent(f, 'GUILD_ROSTER_UPDATE') end end")

    def run(self, code):
        self.L.execute(code)

    def tick(self):
        self.L.execute("for _, fn in ipairs(TICKERS) do fn() end")

    def receive(self, msg, dist, sender):
        self._recv(msg, dist, sender)

    def guild_count(self):
        return self.L.eval("#dgks.History:GuildRecords()")

    def personal_count(self):
        return self.L.eval("#dgks.History:PersonalRecords()")

    def heads(self):
        t = self.L.eval("(function() local out = {} local s = dgks.db.global.history.guilds['Bloodbath-Realm'] if s then for k, st in pairs(s.streams) do out[k] = st.h end end return out end)()")
        return {k: v for k, v in t.items()}

    def live_heads(self):
        """Heads of the streams we still hold records in (the ones listed in our summaries)."""
        t = self.L.eval("(function() local out = {} local s = dgks.db.global.history.guilds['Bloodbath-Realm'] if s then for k, st in pairs(s.streams) do if next(st.r) then out[k] = st.h end end end return out end)()")
        return {k: v for k, v in t.items()}

    def stream(self, key):
        """(head, first unread sequence number) of one stream, or None."""
        return self.L.eval(f"(function() local s = dgks.db.global.history.guilds['Bloodbath-Realm'] local st = s and s.streams['{key}'] if st then return {{st.h, st.u}} end end)()")

    def my_stream(self):
        return self.L.eval("dgks.db.char.historyStream.a .. '#' .. dgks.db.char.historyStream.e")


class Network:
    def __init__(self):
        self.clients, self.inbox, self.count = {}, [], {}
        self.drop = None  # drop(sender, msg, dist, target) -> True loses the message

    def send(self, sender, prefix, msg, dist, target):
        self.inbox.append((sender, msg, dist, target))
        self.sent = getattr(self, "sent", [])
        self.sent.append((sender, dist, target))
        self.count[dist] = self.count.get(dist, 0) + 1

    def deliver(self):
        while self.inbox:
            batch, self.inbox = self.inbox, []
            for sender, msg, dist, target in batch:
                if self.drop and self.drop(sender, msg, dist, target):
                    continue
                if dist == "GUILD":
                    for n, c in list(self.clients.items()):
                        if n != sender:
                            c.receive(msg, dist, sender)  # same realm: bare name, like the game
                elif dist == "WHISPER":
                    tn = target.split("-")[0]
                    if tn in self.clients:
                        self.clients[tn].receive(msg, dist, sender)


class Clock:
    now = 1790000000


clock = Clock()
net = Network()
fails = 0


def settle(clients):
    for _ in range(4):
        clock.now += 20
        for c in clients:
            c.tick()
        net.deliver()


def run_for(seconds, clients):
    for _ in range(seconds // 2):
        clock.now += 2
        for c in clients:
            c.tick()
        net.deliver()


def check(label, cond, extra=""):
    global fails
    print(("PASS " if cond else "FAIL ") + label)
    if not cond:
        fails += 1


A = net.clients["Alice"] = Client("Alice", net, clock, legacy=True)
check("legacy lists imported into personal history (3)", A.personal_count() == 3)
B = net.clients["Bob"] = Client("Bob", net, clock)

for i in range(5):
    A.run(f"dgks.History:Record('K', 'Enemy{i}-Other', nil, {i+1}, 0)")
for i in range(3):
    B.run(f"dgks.History:Record('D', 'Killer{i}', nil, 0, 0)")
A.tick(); B.tick(); net.deliver()
check("Alice holds 8 guild records after live sends", A.guild_count() == 8)
check("Bob holds 8 guild records after live sends", B.guild_count() == 8)
check("personal counts 8/3", A.personal_count() == 8 and B.personal_count() == 3)

clock.now += 100 * 86400
A.run("dgks.History:Record('K', 'Fresh-Other', nil, 6, 0)")
A.tick(); B.tick(); net.deliver()
A.run("dgks.History:Prune()"); B.run("dgks.History:Prune()")
check("old guild records pruned, fresh kept (1)", A.guild_count() == 1 and B.guild_count() == 1)
check("personal history is not pruned (9)", A.personal_count() == 9)

C = net.clients["Cara"] = Client("Cara", net, clock)
clock.now += 31
settle((A, B, C))
print("  counts", A.guild_count(), B.guild_count(), C.guild_count(), A.heads(), C.heads())
check("late joiner Cara synced the 1 non-expired record", C.guild_count() == 1)
check("Cara's heads match Alice's (pruned records skipped)", C.live_heads() == A.live_heads())
check("Bob's stream, all expired, is kept by Alice but not listed to Cara",
      "Bob-Realm#1790000000" in A.heads() and "Bob-Realm#1790000000" not in C.heads(), (A.heads(), C.heads()))

del net.clients["Bob"]
for i in range(40):
    A.run(f"dgks.History:Record('K', 'Mass{i}', nil, {i}, 0)")
A.tick(); net.deliver()
net.clients["Bob"] = B
clock.now += 16 * 60
settle((A, B, C))
check("Bob caught up after being offline (41)", B.guild_count() == 41)
check("all heads equal", A.live_heads() == B.live_heads() == C.live_heads())

run_for(20 * 60, (A, B, C))
net.count = {}
run_for(20 * 60, (A, B, C))
print("  messages in a quiet round:", net.count)
check("quiet round sends no whispers", net.count.get("WHISPER", 0) == 0)
check("quiet 20 minutes: summaries suppressed to about one per interval", 1 <= net.count.get("GUILD", 0) <= 2)

forged = B.L.eval("dgks:Serialize('R', 'Bloodbath-Realm', {a='Alice-Realm', e=1, s=1, t=time(), k='K', o='X'})")
C.receive(forged, "GUILD", "Bob")
check("forged live record (sender is not author) rejected", C.guild_count() == 41)
bad = B.L.eval("dgks:Serialize('R', 'Bloodbath-Realm', {a='Bob-Realm', e=1, s=1.5, t=time(), k='Z', o='X'})")
C.receive(bad, "GUILD", "Bob")
check("malformed record rejected", C.guild_count() == 41)
unsol = B.L.eval("dgks:Serialize('B', 'Bloodbath-Realm', 'Bob-Realm#1', {{a='Bob-Realm', e=1, s=1, t=time(), k='K', o='X'}})")
C.receive(unsol, "WHISPER", "Bob")
check("unsolicited batch rejected", C.guild_count() == 41)
other = B.L.eval("dgks:Serialize('R', 'OtherGuild-Realm', {a='Bob-Realm', e=1, s=1, t=time(), k='K', o='X'})")
C.receive(other, "GUILD", "Bob")
check("record for another guild ignored", C.guild_count() == 41)

# Big backlog: more than one answer's worth (300) for a stream
del net.clients["Cara"]
for i in range(350):
    A.run(f"dgks.History:Record('K', 'Big{i}', nil, 1, 0)")
A.tick(); net.deliver()
net.clients["Cara"] = C
for rnd in range(3):
    clock.now += 16 * 60
    settle((A, B, C))
check("backlog over 300 arrives across rounds (391)", C.guild_count() == 391)
check("all heads equal after backlog", A.live_heads() == B.live_heads() == C.live_heads())

# Saved-variable wipe: Alice restarts with nothing, new stream, no reuse of old numbers
A2 = Client("Alice", net, clock)
net.clients["Alice"] = A2
clock.now += 5
A2.run("dgks.History:Record('K', 'AfterWipe', nil, 1, 0)")
A2.tick(); net.deliver()
check("record from wiped client accepted as new stream (392)", C.guild_count() == 392)
run_for(20 * 60, (A2, B, C))
print("  wiped:", A2.guild_count(), A2.heads(), C.heads())
check("wiped client re-syncs guild history from others (392)", A2.guild_count() == 392)

# A member who logs off is not whispered: Cara misses records, hears Alice's summary, and queues a
# request to Alice; Alice logs off before Cara's next tick
del net.clients["Cara"]
for i in range(5):
    A2.run(f"dgks.History:Record('K', 'Off{i}', nil, 1, 0)")
A2.tick(); B.tick(); net.deliver()
net.clients["Cara"] = C
net.sent = []
A2.run("dgks.History:SendSummary()"); A2.tick(); net.deliver()
del net.clients["Alice"]
C.run("ONLINE['Alice-Realm'] = false; dgks.History:UpdateRoster()")
C.tick(); net.deliver()
to_alice = [x for x in net.sent if x[0] == "Cara" and x[1] == "WHISPER" and x[2].startswith("Alice")]
check("no sync whisper to a member who logged off", to_alice == [], to_alice)
# Alice comes back: her guild messages mark her online again, and sync completes
net.clients["Alice"] = A2
C.run("ONLINE['Alice-Realm'] = nil")
f = C.L.eval("FILTERS.CHAT_MSG_SYSTEM")
net.sent, who, hidden = [], None, None
for _ in range(600):
    clock.now += 2
    for c in (A2, B, C):
        c.tick()
    mine = [x for x in net.sent if x[0] == "Cara" and x[1] == "WHISPER"]
    if mine and who is None:
        who = mine[0][2]
        # the target logs off with our message in flight: the game's error line is hidden
        hidden = f(None, "CHAT_MSG_SYSTEM", f"No player named '{who}' is currently playing.")
    net.deliver()
check("sync completes once she is back", C.heads() == A2.heads(), (C.heads(), A2.heads()))
cara_w = sorted(set(x[2] for x in net.sent if x[0] == "Cara" and x[1] == "WHISPER"))
print("  Cara whispered:", cara_w)
check("whispers use the roster spelling (Name-Realm)", cara_w and all(t.endswith("-Realm") for t in cara_w), cara_w)
check("player-not-found hidden for a member just whispered", hidden is True, (who, hidden))
check("player-not-found shown for other names", f(None, "CHAT_MSG_SYSTEM", "No player named 'Stranger' is currently playing.") is False)
check("other system messages untouched", f(None, "CHAT_MSG_SYSTEM", "Alice has come online.") is False)
clock.now += 120
check("hidden only for a minute after the whisper", f(None, "CHAT_MSG_SYSTEM", f"No player named '{who}' is currently playing.") is False)

# Whispers outside sync (kill and version messages to friends, version replies) go through the
# same dgks:SendCommMessage, so the game's error line for them is hidden too
nf = lambda n: f(None, "CHAT_MSG_SYSTEM", f"No player named '{n}' is currently playing.")
check("player-not-found shown before a friend is whispered", nf("Fred") is False)
C.run("dgks:SendCommMessage('dgks', 'x', 'WHISPER', 'Fred')")
check("player-not-found hidden after a kill whisper to a friend", nf("Fred") is True)
check("matched without regard to case", nf("fred") is True)
C.run("dgks:SendCommMessage('dgksVR', 'x', 'WHISPER', 'Bea-Otherrealm')")
check("hidden for a Name-Realm whisper", nf("Bea-Otherrealm") is True)
check("hidden when the line drops the realm", nf("Bea") is True)
C.run("dgks:SendCommMessage('dgks', 'x', 'GUILD')")
check("guild messages still sent", any(x[0] == 'Cara' and x[1] == 'GUILD' for x in net.sent))
check("whispers still sent", any(x[0] == 'Cara' and x[2] == 'Fred' for x in net.sent))
clock.now += 120
check("friend whisper hidden only for a minute", nf("Fred") is False)


# A batch lost on the way: the end marker must not move the head past records that never arrived
print("-- lost batch")
net = Network()
A = net.clients["Alice"] = Client("Alice", net, clock)
B = Client("Bob", net, clock)  # offline while Alice records
for i in range(20):
    A.run(f"dgks.History:Record('K', 'Lost{i}', nil, 1, 0)")
A.tick(); net.deliver()
net.clients["Bob"] = B
lost = []
def drop_first_batch(sender, msg, dist, target):
    if sender == "Alice" and dist == "WHISPER" and msg.startswith("^1^SB^") and not lost:
        lost.append(msg)
        return True
    return False
net.drop = drop_first_batch
clock.now += 31
settle((A, B))
clock.now += 16 * 60
settle((A, B))
check("a batch was lost on the way", len(lost) == 1)
check("Bob still gets every record (20)", B.guild_count() == 20, B.guild_count())
check("Bob's head matches Alice's", B.live_heads() == A.live_heads(), (B.live_heads(), A.live_heads()))

# An end marker past the head the peer's summary showed is capped there. This one also comes without a
# record count, as from a version before the count was added, and is still taken.
print("-- end marker capped")
net = Network()
A = net.clients["Alice"] = Client("Alice", net, clock)
for i in range(5):
    A.run(f"dgks.History:Record('K', 'Cap{i}', nil, 1, 0)")
A.tick(); net.deliver()
C = net.clients["Cara"] = Client("Cara", net, clock)
net.drop = lambda sender, msg, dist, target: sender == "Alice" and dist == "WHISPER"
clock.now += 31
settle((A, C))
stream = A.my_stream()
forged = A.L.eval(f"dgks:Serialize('E', 'Bloodbath-Realm', '{stream}', 1000000)")
C.receive(forged, "WHISPER", "Alice")
check("head capped at the 5 Alice's summary showed", C.stream(stream) and C.stream(stream)[1] == 5, C.stream(stream))

# A newer version adds a record kind. An older one skips those records, notes where, and asks for them
# again once it is updated.
print("-- records from a newer version")
def newer(code):
    assert "X = true }" in code and "local SCHEMA = 1" in code
    return code.replace("X = true }", "X = true, Y = true }").replace("local SCHEMA = 1", "local SCHEMA = 2")
net = Network()
A = net.clients["Alice"] = Client("Alice", net, clock, patch=newer)
B = Client("Bob", net, clock)
A.run("dgks.History:Record('K', 'One', nil, 1, 0)")
A.run("dgks.History:Record('Y', 'Two', nil, 1, 0)")
A.run("dgks.History:Record('K', 'Three', nil, 1, 0)")
A.tick(); net.deliver()
net.clients["Bob"] = B
clock.now += 31
settle((A, B))
stream = A.my_stream()
check("older Bob keeps the 2 records he can read", B.guild_count() == 2, B.guild_count())
check("older Bob's head moves past the unreadable record, which is noted", B.stream(stream) and tuple(B.stream(stream).values()) == (3, 2), B.stream(stream))
run_for(20 * 60, (A, B))
net.count = {}
run_for(20 * 60, (A, B))
check("no requests for it while Bob cannot read it", net.count.get("WHISPER", 0) == 0, net.count)
B.load(newer)  # Bob updates
check("after the update Bob's head goes back before it", B.stream(stream) and tuple(B.stream(stream).values()) == (1,), B.stream(stream))
clock.now += 31
settle((A, B))
clock.now += 16 * 60
settle((A, B))
check("updated Bob gets the record (3)", B.guild_count() == 3, B.guild_count())
check("updated Bob's head is 3, nothing noted", B.stream(stream) and tuple(B.stream(stream).values()) == (3,), B.stream(stream))

# Empty streams: kept with their head so they are not asked for again, left out of summaries, and
# forgotten once older than any retention setting
print("-- empty streams")
B.run("dgks.db.profile.historyRetentionDays = 30")
clock.now += 40 * 86400
A.run("dgks.History:Prune()"); B.run("dgks.History:Prune()")
check("Alice (90 days) keeps the records, Bob (30 days) does not", A.guild_count() == 3 and B.guild_count() == 0)
check("Bob keeps the empty stream's head", B.heads().get(stream) == 3 and B.live_heads() == {}, B.heads())
run_for(20 * 60, (A, B))
net.count = {}
run_for(20 * 60, (A, B))
check("no requests for a stream Bob holds nothing in", net.count.get("WHISPER", 0) == 0, net.count)
check("summaries still suppressed (same heads)", 1 <= net.count.get("GUILD", 0) <= 2, net.count)
clock.now += 800 * 86400
A.run("dgks.History:Prune()"); B.run("dgks.History:Prune()")
check("a stream with nothing newer than 730 days is forgotten", A.heads() == {} and B.heads() == {}, (A.heads(), B.heads()))

print("FAILS:", fails)
sys.exit(1 if fails else 0)
