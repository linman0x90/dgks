-- dG KillShot: emotes that can be aimed at a target, for the killshot and duel emote choices.
--
-- Generated from the game's EmotesText and EmotesTextData tables (exported by wago.tools): an emote
-- is listed when it has a message for use on a target. Builds checked: retail 12.1.5.70961,
-- Classic Era 1.15.9.70576, Mists Classic 5.5.4.71060, TBC Anniversary 2.5.6.70577 and
-- Forever 1.60.1.71037. All Classic-family clients, Forever included, have the same 241 emotes;
-- retail has 11 more, marked retail = true.
--
-- To refresh: regenerate this list from those tables for the current builds.

local dgks = dgks

-- { token (as DoEmote takes it), label }
dgks.TARGETABLE_EMOTES = {
	{ "ABSENT", "Absent" },
	{ "AGREE", "Agree" },
	{ "ALLIANCE", "Alliance", retail = true },
	{ "AMAZE", "Amaze" },
	{ "ARM", "Arm (Raise Arm)" },
	{ "ATTACKMYTARGET", "Attack My Target" },
	{ "AWE", "Awe" },
	{ "BADFEELING", "Bad Feeling" },
	{ "BARK", "Bark" },
	{ "BASHFUL", "Bashful" },
	{ "BECKON", "Beckon" },
	{ "BEG", "Beg" },
	{ "BITE", "Bite" },
	{ "BLAME", "Blame" },
	{ "BLANK", "Blank Stare" },
	{ "BLINK", "Blink" },
	{ "BLUSH", "Blush" },
	{ "BOGGLE", "Boggle" },
	{ "BONK", "Bonk" },
	{ "BOOP", "Boop" },
	{ "BOOT", "Boot", retail = true },
	{ "BORED", "Bored" },
	{ "BOUNCE", "Bounce" },
	{ "BOW", "Bow" },
	{ "BRANDISH", "Brandish" },
	{ "APPLAUD", "Bravo" },
	{ "BRB", "BRB" },
	{ "BURP", "Burp" },
	{ "BYE", "Bye" },
	{ "CACKLE", "Cackle" },
	{ "CALM", "Calm" },
	{ "SCRATCH", "Cat" },
	{ "CHALLENGE", "Challenge" },
	{ "CHARGE", "Charge" },
	{ "CHARM", "Charm" },
	{ "CHEER", "Cheer" },
	{ "EAT", "Chew" },
	{ "CHICKEN", "Chicken" },
	{ "CHUCKLE", "Chuckle" },
	{ "CHUG", "Chug" },
	{ "CLAP", "Clap" },
	{ "COLD", "Cold" },
	{ "COMFORT", "Comfort" },
	{ "COMMEND", "Commend" },
	{ "CONFUSED", "Confused" },
	{ "CONGRATULATE", "Congrats" },
	{ "COUGH", "Cough" },
	{ "COVEREARS", "Cover Ears" },
	{ "COWER", "Cower" },
	{ "CRACK", "Crack Knuckles" },
	{ "CRINGE", "Cringe" },
	{ "CROSSARMS", "Cross Arms" },
	{ "CRY", "Cry" },
	{ "CUDDLE", "Cuddle" },
	{ "CURIOUS", "Curious" },
	{ "CURTSEY", "Curtsey" },
	{ "DANCE", "Dance" },
	{ "DING", "Ding" },
	{ "DISAGREE", "Disagree" },
	{ "DOUBT", "Doubt" },
	{ "DRINK", "Drink" },
	{ "DROOL", "Drool" },
	{ "DUCK", "Duck" },
	{ "EMBARRASS", "Embarrass" },
	{ "ENCOURAGE", "Encourage" },
	{ "ENEMY", "Enemy" },
	{ "TALKEX", "Exclaim" },
	{ "EYE", "Eye" },
	{ "FACEPALM", "Facepalm" },
	{ "FAIL", "Fail" },
	{ "FAINT", "Faint" },
	{ "FART", "Fart" },
	{ "FLEE", "Flee" },
	{ "FLEX", "Flex" },
	{ "FLIRT", "Flirt" },
	{ "FLOP", "Flop" },
	{ "FOLLOW", "Follow" },
	{ "FORTHEALLIANCE", "For the Alliance", retail = true },
	{ "FORTHEHORDE", "For the Horde", retail = true },
	{ "FROWN", "Frown" },
	{ "GASP", "Gasp" },
	{ "GAZE", "Gaze" },
	{ "GIGGLE", "Giggle" },
	{ "GLARE", "Glare" },
	{ "GLOAT", "Gloat" },
	{ "GLOWER", "Glower" },
	{ "GO", "Go" },
	{ "GOING", "Going" },
	{ "GOLFCLAP", "Golf Clap" },
	{ "GOODLUCK", "Good Luck" },
	{ "GREET", "Greet" },
	{ "GRIN", "Grin" },
	{ "GROAN", "Groan" },
	{ "GROVEL", "Grovel" },
	{ "GROWL", "Growl" },
	{ "GUFFAW", "Guffaw" },
	{ "HAIL", "Hail" },
	{ "HAPPY", "Happy" },
	{ "HEADACHE", "Headache" },
	{ "HELLO", "Hello" },
	{ "HELPME", "Help Me" },
	{ "HIGHFIVE", "High Five" },
	{ "HISS", "Hiss" },
	{ "HOLDHAND", "Hold Hand" },
	{ "HORDE", "Horde", retail = true },
	{ "HUG", "Hug" },
	{ "HUNGRY", "Hungry" },
	{ "HURRY", "Hurry" },
	{ "HUZZAH", "Huzzah", retail = true },
	{ "FIDGET", "Impatient" },
	{ "IMPRESSED", "Impressed", retail = true },
	{ "INCOMING", "Incoming" },
	{ "INSULT", "Insult" },
	{ "INTRODUCE", "Introduce" },
	{ "JEALOUS", "Jealous" },
	{ "JK", "JK" },
	{ "KISS", "Kiss" },
	{ "KNEEL", "Kneel" },
	{ "LAUGH", "Laugh" },
	{ "LAYDOWN", "Lay Down" },
	{ "LEAN", "Lean", retail = true },
	{ "LICK", "Lick" },
	{ "LISTEN", "Listen" },
	{ "LOOK", "Look" },
	{ "LOST", "Lost" },
	{ "LOVE", "Love" },
	{ "LUCK", "Luck" },
	{ "ANGRY", "Mad" },
	{ "MAGNIFICENT", "Magnificent", retail = true },
	{ "MASSAGE", "Massage" },
	{ "MEOW", "Meow" },
	{ "MERCY", "Mercy" },
	{ "MOAN", "Moan" },
	{ "MOCK", "Mock" },
	{ "MOO", "Moo" },
	{ "MOON", "Moon" },
	{ "MOURN", "Mourn" },
	{ "MUTTER", "Mutter" },
	{ "NERVOUS", "Nervous" },
	{ "NO", "No" },
	{ "NOD", "Nod" },
	{ "NOSEPICK", "Nosepick" },
	{ "OBJECT", "Object" },
	{ "OFFER", "Offer" },
	{ "OOPS", "Oops" },
	{ "BREATH", "Out of Breath" },
	{ "PANIC", "Panic" },
	{ "PAT", "Pat" },
	{ "PEER", "Peer" },
	{ "PET", "Pet" },
	{ "PINCH", "Pinch" },
	{ "PITY", "Pity" },
	{ "PLEAD", "Plead" },
	{ "POINT", "Point" },
	{ "POKE", "Poke" },
	{ "PONDER", "Ponder" },
	{ "POUNCE", "Pounce" },
	{ "POUT", "Pout" },
	{ "PRAISE", "Praise" },
	{ "PRAY", "Pray" },
	{ "PROMISE", "Promise" },
	{ "PROUD", "Proud" },
	{ "PULSE", "Pulse" },
	{ "PUNCH", "Punch" },
	{ "PURR", "Purr" },
	{ "PUZZLE", "Puzzled" },
	{ "QUACK", "Quack", retail = true },
	{ "TALKQ", "Question" },
	{ "RAISE", "Raise" },
	{ "EYEBROW", "Raise Eyebrow" },
	{ "RASP", "Rasp (Rude Gesture)" },
	{ "READY", "Ready" },
	{ "REGRET", "Regret" },
	{ "REVENGE", "Revenge" },
	{ "ROAR", "Roar" },
	{ "ROFL", "ROFL" },
	{ "ROLLEYES", "Roll Eyes" },
	{ "RUDE", "Rude" },
	{ "RUFFLE", "Ruffle" },
	{ "SALUTE", "Salute" },
	{ "SCARED", "Scared" },
	{ "SCOFF", "Scoff" },
	{ "SCOLD", "Scold" },
	{ "SCOWL", "Scowl" },
	{ "SEARCH", "Search" },
	{ "SERIOUS", "Serious" },
	{ "SEXY", "Sexy" },
	{ "SHAKEFIST", "Shake Fist" },
	{ "SHAKE", "Shake Rear" },
	{ "SHIFTY", "Shifty" },
	{ "SHIMMY", "Shimmy" },
	{ "SHIVER", "Shiver" },
	{ "SHOO", "Shoo" },
	{ "SHOUT", "Shout" },
	{ "SHRUG", "Shrug" },
	{ "SHUDDER", "Shudder" },
	{ "SHY", "Shy" },
	{ "SIGH", "Sigh" },
	{ "SIGNAL", "Signal" },
	{ "SILENCE", "Silence" },
	{ "JOKE", "Silly" },
	{ "SING", "Sing" },
	{ "SLAP", "Slap" },
	{ "SMACK", "Smack" },
	{ "SMILE", "Smile" },
	{ "SMIRK", "Smirk" },
	{ "SNAP", "Snap" },
	{ "SNARL", "Snarl" },
	{ "SNEAK", "Sneak" },
	{ "SNEEZE", "Sneeze" },
	{ "SNICKER", "Snicker" },
	{ "SNIFF", "Sniff" },
	{ "SNORT", "Snort" },
	{ "SNUB", "Snub" },
	{ "SOOTHE", "Soothe" },
	{ "APOLOGIZE", "Sorry" },
	{ "SPIT", "Spit" },
	{ "SQUEAL", "Squeal" },
	{ "STARE", "Stare" },
	{ "STINK", "Stink" },
	{ "STOPATTACK", "Stop Attack" },
	{ "SURPRISED", "Surprised" },
	{ "SURRENDER", "Surrender" },
	{ "SUSPICIOUS", "Suspicious" },
	{ "SWEAT", "Sweat" },
	{ "TALK", "Talk" },
	{ "TAP", "Tap" },
	{ "TAUNT", "Taunt" },
	{ "TEASE", "Tease" },
	{ "THANK", "Thank" },
	{ "THINK", "Think" },
	{ "THIRSTY", "Thirsty" },
	{ "THREATEN", "Threaten" },
	{ "TICKLE", "Tickle" },
	{ "TIRED", "Tired" },
	{ "TOAST", "Toast" },
	{ "TRUCE", "Truce" },
	{ "VETO", "Veto" },
	{ "VICTORY", "Victory" },
	{ "VIOLIN", "Violin" },
	{ "WAIT", "Wait" },
	{ "WARN", "Warn" },
	{ "WAVE", "Wave" },
	{ "WELCOME", "Welcome" },
	{ "WHINE", "Whine" },
	{ "WHISTLE", "Whistle" },
	{ "WHOA", "Whoa" },
	{ "WINCE", "Wince", retail = true },
	{ "WINK", "Wink" },
	{ "WORK", "Work" },
	{ "YAWN", "Yawn" },
	{ "YW", "You're Welcome" },
}

-- Old choices that were slash-command aliases rather than emote tokens, so DoEmote did nothing
dgks.EMOTE_ALIASES = { BELCH = "BURP", BLOWKISS = "KISS", DOOM = "THREATEN", KNUCKLES = "CRACK", SMELL = "STINK" }

-- Retail-only emotes are offered on retail (version 6 and later) only
local function isRetail()
	local version = GetBuildInfo and GetBuildInfo()
	local major = type(version) == "string" and tonumber(version:match("^(%d+)"))
	return major ~= nil and major >= 6
end

local available
-- token -> label for every targetable emote this client has
function dgks:AvailableEmotes()
	if not available then
		available = {}
		local retail = isRetail()
		for _, e in ipairs(dgks.TARGETABLE_EMOTES) do
			if retail or not e.retail then available[e[1]] = e[2] end
		end
	end
	return available
end

-- Values for an emote select: "None" first, then the emotes by label
function dgks:EmoteSelectValues()
	local values = { none = "None" }
	for token, label in pairs(dgks:AvailableEmotes()) do values[token] = label end
	return values
end

function dgks:EmoteSelectSorting()
	local order = { "none" }
	local emotes = dgks:AvailableEmotes()
	for _, e in ipairs(dgks.TARGETABLE_EMOTES) do
		if emotes[e[1]] then order[#order + 1] = e[1] end
	end
	return order
end

-- Fix saved emote choices: aliases become their emote, and anything this client cannot do resets
function dgks:MigrateEmoteSettings()
	local profile = dgks.db.profile
	local emotes = dgks:AvailableEmotes()
	for key, default in pairs({ doemote = "none", duelemotewin = "BOW", duelemoteloss = "BOW" }) do
		local v = profile[key]
		if type(v) == "string" and dgks.EMOTE_ALIASES[v] then v = dgks.EMOTE_ALIASES[v] end
		if v ~= "none" and not (type(v) == "string" and emotes[v]) then v = default end
		profile[key] = v
	end
end
