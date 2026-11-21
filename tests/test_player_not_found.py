import os
import sys
from lupa import lua51

from names_prelude import REPO
src = lambda f: open(f"{REPO}/{f}", encoding="utf-8").read()
import names_prelude; src = names_prelude.wrap(src, REPO)
HERE = os.path.dirname(os.path.abspath(__file__))
exec(open(HERE + "/test_death.py").read().split("fails = 0")[0])  # make(): dgks.lua with retail stubs

fails = 0


def check(label, cond, extra=""):
    global fails
    fails += not cond
    print(("PASS " if cond else "FAIL ") + label, extra)


L = make()
L.execute(r'''
EMOTES = {}
DoEmote = function(e, t) EMOTES[#EMOTES+1] = e .. ">" .. tostring(t) end
UnitName = function(u)
  if u == "player" then return "Me", nil end
  local i = UNITS[u] if i then return i.name, i.realm end
end
''')


def emote(setup, call):
    L.execute("EMOTES = {}; UNITS = {}")
    L.execute(setup)
    L.execute(call)
    return list(L.eval("EMOTES").values())


# ---------- Emotes ----------
check("kill victim found as target by GUID",
      emote("UNITS = { target = { guid = 'Player-2-ZED', name = 'Zed', realm = 'Other' } }", "dgks:EmoteAt('BOW', 'Player-2-ZED', 'Zed')") == ["BOW>target"])
check("kill victim found on a nameplate",
      emote("UNITS = { nameplate7 = { guid = 'Player-2-ZED', name = 'Zed', realm = 'Other' } }", "dgks:EmoteAt('BOW', 'Player-2-ZED', 'Zed')") == ["BOW>nameplate7"])
check("victim not nearby: emote without a target, never by name",
      emote("UNITS = { target = { guid = 'Player-9-SOMEONE', name = 'Bob' } }", "dgks:EmoteAt('BOW', 'Player-2-ZED', 'Zed')") == ["BOW>none"])
check("duel opponent matched by name (with realm)",
      emote("UNITS = { target = { guid = 'Player-2-ZED', name = 'Zed', realm = 'Other' } }", "dgks:EmoteAt('BOW', nil, 'Zed-Other')") == ["BOW>target"])
check("duel opponent matched by bare name",
      emote("UNITS = { focus = { guid = 'Player-3-BOB', name = 'Bob' } }", "dgks:EmoteAt('BOW', nil, 'Bob')") == ["BOW>focus"])
check("'Unknown Entity' never sent as a name",
      emote("", "dgks:EmoteAt('BOW', nil, 'Unknown Entity')") == ["BOW>none"])
check("secret GUIDs are skipped",
      emote("UNITS = { target = { guid = SECRET, name = 'Zed' } }", "dgks:EmoteAt('BOW', 'Player-2-ZED', 'Zed')") == ["BOW>none"])

# Through a real kill: PARTY_KILL -> KillshotTX -> ProcessKillshot -> emote at the target
L.execute(r'''
EMOTES = {}
UNITS = { target = { guid = 'Player-2-ZED', name = 'Zed', realm = 'Other' } }
GetPlayerInfoByGUID = function(g) if g == 'Player-2-ZED' then return "Mage", "MAGE", "Human", "Human", 2, "Zed", "Other" end return "Warrior", "WARRIOR", "Human", "Human", 2, "Me", "Realm" end
dgks.TargetCheck = function() return true end
for k, v in pairs({ killList = {}, killlog = {}, kstextS = {}, doemote = "BOW", dotxtemote = false, kstext = "$k killed $v", kstextM = { "x" }, dobroadcasts = false }) do dgks.db.profile[k] = v end
function dgks:ScrollText() end
function dgks:dgks_SoundPack() end
function dgks:GetKillshotSound() end
function dgks:SoundEventHandler() end
dgks.History.Record = function() end
function dgks:Serialize() return "x" end
REAL_SENDCM = dgks.SendCM
function dgks:SendCM() end
FIRE('PARTY_KILL', 'Player-1-ME', 'Player-2-ZED')
RUN_TIMERS()
''')
check("own kill emotes at the victim's unit", list(L.eval("EMOTES").values()) == ["BOW>target"], list(L.eval("EMOTES").values()))

# Duel loss with no known killer
L.execute("EMOTES = {}; UNITS = {}; dgks.db.profile.duelemoteloss = 'CRY'; dgks.db.profile.deathList = {}; dgks.db.profile.killlog = {}; dgks.db.profile.maxdeathstreak = 0; dgks.db.profile.doscreenshotonduelloss = false; dgks:PlayerLoss(nil)")
check("duel loss to an unknown killer: no name lookup", list(L.eval("EMOTES").values()) == ["CRY>none"])

# ---------- Battle.net friend whispers ----------
L.execute(r'''
WHISPERS = {}
dgks.SendCM = REAL_SENDCM
function dgks:SendCommMessage(prefix, msg, dist, target) if dist == "WHISPER" then WHISPERS[#WHISPERS+1] = target end end
dgks.db.profile.dobroadcasts = true
dgks.db.profile.dofriends = true
dgks.db.profile.doguild = false; dgks.db.profile.dobg = false; dgks.db.profile.doraid = false
IsInGuild = function() return false end
UnitFactionGroup = function() return "Horde" end
GetNormalizedRealmName = function() return "Realm" end
GetAutoCompleteRealms = function() return { "Realm", "ConnectedOne", "AzjolNerub" } end
GetRealmName = function() return "Realm" end
C_FriendList = { GetNumFriends = function() return 0 end }
FRIENDS = {
  { characterName = "Same", realmName = "Realm", factionName = "Horde" },
  { characterName = "Conn", realmName = "Connected One", factionName = "Horde" },
  { characterName = "Hyph", realmName = "Azjol-Nerub", factionName = "Horde" },
  { characterName = "Far", realmName = "Faraway", factionName = "Horde" },
  { characterName = "Ally", realmName = "Realm", factionName = "Alliance" },
  { characterName = "Classic", realmName = "Realm", factionName = "Horde", wowProjectID = 2 },
  { realmName = "Realm" }, -- the Battle.net app, not a character
}
BNGetNumFriends = function() return #FRIENDS, #FRIENDS end
C_BattleNet = { GetFriendNumGameAccounts = function() return 1 end, GetFriendGameAccountInfo = function(i) return FRIENDS[i] end }
dgks:SendCM("dgks", "x")
''')
w = list(L.eval("WHISPERS").values())
print("  whispered:", w)
check("Battle.net friends: own realm bare, connected realms with realm, unreachable/other faction/other game skipped",
      w == ["Same", "Conn-ConnectedOne", "Hyph-AzjolNerub"], w)
L.execute("WHISPERS = {}; RegionalUniqueNamesEnabled = function() return true end; FRIENDS = { { characterName = 'Ann Smith', realmName = 'Faraway', factionName = 'Horde' } }; dgks:SendCM('dgks', 'x')")
w = list(L.eval("WHISPERS").values())
check("Forever: names are region-wide, whispered as given", w == ["Ann Smith"], w)
print("FAILS:", fails)
sys.exit(1 if fails else 0)
