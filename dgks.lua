--TODO List
-- Cleanup potential name isssue
-- Find a way to reduce delay without taint
-- Test duel pets and instance checking

local version = "@project-version@"
local databaseversion = "1"
local addonName, ns = ...
local msg = ""
local streak = 0
local deathstreak = 0
local multikill = 0
local lastrxkiller = ""
local lastrxvictim = ""
local lastrxtimestamp = 0
local lastkill = 0
local timestamp = 0
local lastToHurtMe = ""
local lastLocalKillKey -- "victimGUID@timestamp" of the last kill we processed locally
local newestconfigversion = 1
local frame, events = CreateFrame("Frame"), {}; -- Event Frame
local damageDealers = {}
local targetList = {} -- Used for Execute
local playerGUID, playerClass, _, playerRace, playerSex, playerName
local inArena = false
local inBG = false
local lastMessage, lastSender, lastTimestamp --Versionchecking duplicate detection
local soundPath = "Interface\\AddOns\\dgks\\sounds\\"
local classic = false -- Assume retail, we will verify below


--Is this Classic? Only the known Classic flavors count; Retail, Forever and any unknown client
--keep the retail code path, because the combat log is closed to addons there.
local classicProjects = {
	WOW_PROJECT_CLASSIC,
	WOW_PROJECT_BURNING_CRUSADE_CLASSIC,
	WOW_PROJECT_WRATH_CLASSIC,
	WOW_PROJECT_CATACLYSM_CLASSIC,
	WOW_PROJECT_MISTS_CLASSIC,
}
for _, projectID in pairs(classicProjects) do
	if WOW_PROJECT_ID == projectID then
		classic = true
		break
	end
end

--Check for secret values in mainline versions
local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Is this GUID one of our party or raid members (not us)?
local function isGroupMember(guid)
	if type(guid) ~= "string" or isSecret(guid) then return false end
	local prefix, count = "party", 4
	if IsInRaid and IsInRaid() then prefix, count = "raid", 40 end
	for i = 1, count do
		local g = UnitGUID(prefix .. i)
		if g ~= nil and not isSecret(g) and g == guid then return true end
	end
	return false
end

dgks = LibStub("AceAddon-3.0"):NewAddon("dgks", "AceEvent-3.0", "AceConsole-3.0", "LibSink-2.0","AceComm-3.0","AceSerializer-3.0")

-- Overview tab of the dG KillShot window: record and streak tiles, Top 5 lists
local function giveOverview()
	local options = {
		type = "group",
		name = "Overview",
		args = {
			version = {
				type = "description",
				name = "|cff9d9d9dVersion " .. version .. "|r\n",
				order = 2
			},
			-- The record tiles and Top 5 lists are added below from dgks_history_ui.lua
			streak = dgks.History.Tile(15, "Kill streak", streak, "ff40ff40"),
			maxstreak = dgks.History.Tile(16, "Best streak", dgks.db.profile.maxstreak, "ffffd100"),
			deathstreak = dgks.History.Tile(17, "Death streak", deathstreak, "ffff4040"),
			maxdeathstreak = dgks.History.Tile(18, "Worst streak", dgks.db.profile.maxdeathstreak, "ffff8040"),
			--@debug@
			-- Dev Debugging functions
			testdgkskill = {
				type = 'execute',
				name = 'Simulate Killshot',
				order = 90,
				func = function()
					dgks:Test()
				end
			},
			testdgdeath = {
				type = 'execute',
				name = 'Simulate Death',
				order = 91,
				func = function()
					dgks:TestPlayerDeath()
				end
			}
			--@end-debug@
		}
	}
	for key, option in pairs(dgks.History:MainOptionArgs(10)) do
		options.args[key] = option
	end
	return options
end

-- Settings > History tab: history options, then the reset and clear buttons
local function giveHistorySettings()
	local history = {
		type = "group",
		name = "History",
		args = {
			resetHeader = {
				type = "header",
				name = "Reset",
				order = 90
			},
			resetmaxks = {
				type = 'execute',
				name = 'Reset Stats',
				func = function()
					streak = 0
					deathstreak = 0
					multikill = 0
					dgks.db.profile.maxstreak = dgks.db.defaults.profile.maxstreak
					dgks.db.profile.maxdeathstreak = dgks.db.defaults.profile.maxdeathstreak
					dgks.db.profile.killlog = dgks.db.defaults.profile.killlog
					dgks.db.profile.killList = dgks.db.defaults.profile.killList
					dgks.db.profile.deathList = dgks.db.defaults.profile.deathList
				end,
				width = "full",
				order = 91
			},
			resetdgks = {
				type = 'execute',
				name = 'Reset All dG Killshot Settings',
				func = function()
					streak = 0
					deathstreak = 0
					multikill = 0
					dgks.db:ResetProfile()
				end,
				width = "full",
				order = 92
			},
		}
	}
	for key, option in pairs(dgks.History:SettingsArgs(1)) do
		history.args[key] = option
	end
	return history
end

local function giveGeneral()
	local general = {
		type = "group",
		name = "General",
		handler = dgks,
		args = {
			deathRecapWindow = {
				type = 'toggle',
				name = 'Show a death recap when you die',
				desc = 'Open a window listing the damage you took in the last 10 seconds before dying. Reopen it with /dgks deathrecap.',
				get = function() return dgks.db.profile.deathRecap end,
				set = function(info, v) dgks.db.profile.deathRecap = v end,
				order = 2,
				width = "full"
			},
			minimapButton = {
				type = 'toggle',
				name = 'Show minimap button',
				desc = 'Left-click the button to open the dG KillShot window, right-click to open it on Settings. Drag it to move it around the minimap.',
				get = function() return not dgks.db.profile.minimap.hide end,
				set = function(info, v)
					dgks.db.profile.minimap.hide = not v
					dgks:UpdateMinimapButton()
				end,
				order = 1,
				width = "full"
			},
			style = {
				type = 'select',
				name = 'Select how often to trigger killshots notifications:',
				desc = 'DoTA plays sound on every kill, UT plays on new ranks',
				get = function()
					return dgks.db.profile.style
				end,
				set = function(info,b)
					dgks.db.profile.style = b
					
				end,
				values = {
					dota = "Every Killshot (DoTA/LoL Style)",
					ut = "Every " .. dgks.db.profile.utrank .. " Killshots (Unreal Tournament Style)"
				},
				order = 10,
				width = 2
			},
			dopreparesound = {
				type = 'toggle',
				name = 'Play prepare sound when entering battlegrounds',
				get = function()
					return dgks.db.profile.dopreparesound
				end,
				set = function(info, b)
					dgks.db.profile.dopreparesound = b
				end,
				width = "full",
				order = 11
			},
			doexecutesound = {
				type = 'toggle',
				name = 'Play execute sound when Player target hits threshold',
				get = function()
					return dgks.db.profile.doexecutesound
				end,
				set = function(info, b)
					dgks.db.profile.doexecutesound = b
				end,
				width = "full",
				order = 12
			},
			doexecutesoundpve = {
				type = 'toggle',
				name = 'Play execute sound when NPC target hits threshold',
				get = function()
					return dgks.db.profile.doexecutesoundpve
				end,
				set = function(info, b)
					dgks.db.profile.doexecutesoundpve = b
				end,
				width = "full",
				order = 13
			},
			doexecutepercent = {
				type = 'range',
				name = 'Execute Percent',
				desc = 'The percent health that triggers the execute sound',
				width = "full",
				get = function() return dgks.db.profile.doexecutepercent end,
				set = function(info, v) dgks.db.profile.doexecutepercent = v end,
				disabled = function() if dgks.db.profile.doexecutesound or dgks.db.profile.doexecutesoundpve then return false else return true end end,
				min = 1,
				max = 40,
				step = 1,
				order = 14
			},
			dochatbox = {
				type = 'toggle',
				name = 'Print killshots and deaths in chatbox in addition to logging in /dgks',
				get = function()
					return dgks.db.profile.dochatbox
				end,
				set = function(info, b)
					dgks.db.profile.dochatbox = b
				end,
				width = "full",
				order = 15
			},
			dozonechange = {
				type = 'toggle',
				name = 'Clear Streaks on Zone Change',
				get = function()
					return dgks.db.profile.dozonechange
				end,
				set = function(info, b)
					dgks.db.profile.dozonechange = b
				end,
				width = "full",
				order = 20
			},
			doemote = {
				type = 'select',
				name = 'Do built in Emote',
				desc = 'Choose an Emote',
				get = function()
					return dgks.db.profile.doemote
				end,
				set = function(info, b)
					dgks.db.profile.doemote = b
				end,
				values = function() return dgks:EmoteSelectValues() end,
				sorting = function() return dgks:EmoteSelectSorting() end,
				order = 25
				},
			dotxtemote = {
				type = 'toggle',
				name = 'Show Custom Emote',
				desc = 'Toggle Emote Spam',
				get = function()
					return dgks.db.profile.dotxtemote
				end,
				set = function(info, b)
					dgks.db.profile.dotxtemote = b
				end,
				width = "full",
				order = 30
			},
			ksemote = {
				type = 'input',
				name = 'Custom Emote Message',
				desc = "Use this to customize the emote message. $v = victim $s = streak",
				usage = "<message>",
				get = function()
					return dgks.db.profile.ksemote
				end,
				set = function(info, b)
					dgks.db.profile.ksemote = b
				end,
				width = "full",
				order = 40
			},
			docombattext = {
				type = 'toggle',
				name = "Show Combat Text (Game setting Combat->Scrolling Combat Text for Self must also be enabled.)",
				desc = 'Toggle Combat Text Spam',
				get = function()
					return dgks.db.profile.docombattext
				end,
				set = function(info, b)
					dgks.db.profile.docombattext = b
				end,
				width = "full",
				order = 50
			},
			kstext = {
				type = 'input',
				name = 'Scrolling Text Message',
				desc = 'Use this to customize the Scrolling Text Message. $k = killer, $v = victim',
				usage = "<message>",
				get = function()
					return dgks.db.profile.kstext
				end,
				set = function(info, b)
					dgks.db.profile.kstext = b
				end,
				width = "full",
				order = 60
			},
			--[[ dopet = {
				type = 'toggle',
				name = 'Summon Random Pet',
				desc = 'Summon Random Pet on Killshot',
				get = function()
					return dgks.db.profile.dopet
				end,
				set = function(info, b)
					dgks.db.profile.dopet = b
				end,
				width = "full",
				order = 30
			}, ]]--
			soundpack = {
				type = 'select',
				name = 'Sound Pack',
				desc = 'Choose a sound pack',
				get = "getSoundPack",
				set = "setSoundPack",
				values = {
					male = "male",
					female = "female",
					sexy = "sexy",
					baby = "baby"
				},
				order = 85
			},
			dosound = {
				type = 'toggle',
				name = "Play Sounds",
				desc = 'Toggle Sound Spam',
				get = function()
					return dgks.db.profile.dosound
				end,
				set = function(info, b)
					dgks.db.profile.dosound = b
				end,
				order = 70
			},
			soundchannel = {
				type = 'select',
				name = "Sound Channel",
				desc = 'Select the sound channel used for audio notifications. Default: Master',
				get = function()
					return dgks.db.profile.soundchannel
				end,
				set = function(info, b)
					dgks.db.profile.soundchannel = b
				end,
				values = {
					Master = "Master",
					SFX = "SFX",
					Ambience = "Ambience",
					Music = "Music"
				},
				order = 80
			},
			dopve = {
				type = 'toggle',
				name = "Trigger off NPC/PVE Killshots - VERY SPAMMY, use for testing.",
				desc = "Please don't use this",
				get = function()
					return dgks.db.profile.dopve
				end,
				set = function(info, b)
					dgks.db.profile.dopve = b
				end,
				width = "full",
				order = 90
			}
		}
	}
	return general
end

local function giveBroadcasts()
	local broadcasts = {
		type = "group",
		name = "Broadcasts",
		handler = dgks,
		args = {
			dobroadcasts = {
				type = 'toggle',
				name = 'Enable Broadcasts',
				desc = 'Enable/Disable all broadcasts',
				get = function()
					return dgks.db.profile.dobroadcasts
				end,
				set = function(info, b)
					dgks.db.profile.dobroadcasts = b
				end,
				width = "full",
				order = 80
			},
			doguild = {
				type = 'toggle',
				name = 'Broadcasts to/from Guild',
				desc = 'Broadcast killshot to dgks users in guild.',
				get = function()
					return dgks.db.profile.doguild
				end,
				set = function(info, c)
					dgks.db.profile.doguild = c
				end,
				disabled = function()
					return not dgks.db.profile.dobroadcasts
				end,
				width = "full",
				order = 90
			},
			doraid = {
				type = 'toggle',
				name = 'Broadcasts to/from Party/Raid/Instance',
				desc = 'Broadcast killshot to dgks users in your paty or raid.',
				get = function()
					return dgks.db.profile.doraid
				end,
				set = function(info, d)
					dgks.db.profile.doraid = d
				end,
				disabled = function()
					return not dgks.db.profile.dobroadcasts
				end,
				width = "full",
				order = 110
			},
			dobg = {
				type = 'toggle',
				name = 'Broadcast to/from Battleground',
				desc = 'Broadcast killshot to battleground.',
				get = function()
					return dgks.db.profile.dobg
				end,
				set = function(info, e)
					dgks.db.profile.dobg = e
				end,
				disabled = function()
					return not dgks.db.profile.dobroadcasts
				end,
				width = "full",
				order = 120
			},
			dofriends = {
				type = 'toggle',
				name = 'Broadcast to Friends',
				desc = 'Broadcast killshot to friends.',
				get = function()
					return dgks.db.profile.dofriends
				end,
				set = function(info, e)
					dgks.db.profile.dofriends = e
				end,
				disabled = function()
					return not dgks.db.profile.dobroadcasts
				end,
				width = "full",
				order = 125
			},
			versioncheck = {
				type = 'execute',
				width = "full",
				name = 'Check other players versions',
				desc = 'Check Versions',
				func = "VersionCheck",
				order = 130
			}
		}
	}
	return broadcasts 
end

local function giveScreenshots()
	local screenshots = {
		type = "group",
		name = "Screenshots",
		handler = dgks,
		args = {
			doscreenshotonkill = {
				type = 'toggle',
				name = 'Enable Screenshot on Killshot',
				desc = 'Enable Screenshot on Killshot',
				get = function()
					return dgks.db.profile.doscreenshotonkill
				end,
				set = function(info, b)
					dgks.db.profile.doscreenshotonkill = b
				end,
				width = "full",
				order = 80
			},
			doscreenshotonstreak = {
				type = 'toggle',
				name = 'Enable Screenshot on new max killing streak',
				desc = 'Enable Screenshot on new max killing streak',
				get = function()
					return dgks.db.profile.doscreenshotonstreak
				end,
				set = function(info, b)
					dgks.db.profile.doscreenshotonstreak = b
				end,
				width = "full",
				order = 90
			},
			doscreenshotonmultikill = {
				type = 'toggle',
				name = 'Enable Screenshot on multikill',
				desc = 'Enable Screenshot on multikill',
				get = function()
					return dgks.db.profile.doscreenshotonmultikill
				end,
				set = function(info, b)
					dgks.db.profile.doscreenshotonmultikill = b
				end,
				width = "full",
				order = 100
			},
			doscreenshotonduelwin = {
				type = 'toggle',
				name = 'Enable Screenshot on duel win',
				desc = '',
				get = function()
					return dgks.db.profile.doscreenshotonduelwin
				end,
				set = function(info, b)
					dgks.db.profile.doscreenshotonduelwin = b
				end,
				width = "full",
				order = 105
			},
			doscreenshotonduelloss = {
				type = 'toggle',
				name = 'Enable Screenshot on duel loss',
				desc = '',
				get = function()
					return dgks.db.profile.doscreenshotonduelloss
				end,
				set = function(info, b)
					dgks.db.profile.doscreenshotonduelloss = b
				end,
				width = "full",
				order = 106
			},
			doscreenshotondeath = {
				type = 'toggle',
				name = 'Enable Screenshot on death',
				desc = 'Enable Screenshot on death',
				get = function()
					return dgks.db.profile.doscreenshotondeath
				end,
				set = function(info, b)
					dgks.db.profile.doscreenshotondeath = b
				end,
				width = "full",
				order = 110
			},	
			versioncheck = {
				type = 'execute',
				width = "full",
				name = 'Test Screenshot Lag',
				desc = 'Enable screenshots will cause a short lag, please test first.',
				func = function() Screenshot() end,
				order = 130
			}
		}
	}
	return screenshots 
end

local function giveDuels()
	local duels = {
		type = "group",
		name = "Duels",
		handler = dgks,
		args = {
			duelhumiliation = {
				type = 'toggle',
				name = 'Play humiliation when player flees a duel',
				desc = '',
				get = function()
					return dgks.db.profile.duelhumiliation
				end,
				set = function(info, b)
					dgks.db.profile.duelhumiliation = b
				end,
				width = "full",
				order = 10
			},
			duelemotewin = {
				type = 'select',
				name = 'Emote for Duel Win',
				desc = 'Choose an Emote',
				get = function()
					return dgks.db.profile.duelemotewin
				end,
				set = function(info, b)
					dgks.db.profile.duelemotewin = b
				end,
				values = function() return dgks:EmoteSelectValues() end,
				sorting = function() return dgks:EmoteSelectSorting() end,
				order = 25
				},
				duelemoteloss = {
				type = 'select',
				name = 'Emote for Duel Loss',
				desc = 'Choose an Emote',
				get = function()
					return dgks.db.profile.duelemoteloss
				end,
				set = function(info, b)
					dgks.db.profile.duelemoteloss = b
				end,
				values = function() return dgks:EmoteSelectValues() end,
				sorting = function() return dgks:EmoteSelectSorting() end,
				order = 26
				},
			dueltxtemote = {
				type = 'toggle',
				name = 'Show Custom Emote',
				desc = 'Toggle Emote Spam',
				get = function()
					return dgks.db.profile.dueltxtemote
				end,
				set = function(info, b)
					dgks.db.profile.dueltxtemote = b
				end,
				width = "full",
				order = 30
			},
			duelcustomemote = {
				type = 'input',
				name = 'Custom Emote Message',
				desc = "Use this to customize the emote message. $v = victim $s = streak",
				usage = "<message>",
				get = function()
					return dgks.db.profile.duelcustomemote
				end,
				set = function(info, b)
					dgks.db.profile.duelcustomemote = b
				end,
				width = "full",
				order = 40
			},		
			dueltext = {
				type = 'input',
				name = 'Scrolling Text Message',
				desc = 'Use this to customize the Scrolling Text Message. $k = killer, $v = victim',
				usage = "<message>",
				get = function()
					return dgks.db.profile.dueltext
				end,
				set = function(info, b)
					dgks.db.profile.dueltext = b
				end,
				width = "full",
				order = 60
			},
		}
	}
	return duels 
end

local function giveRanks()
	local ranks = {
		type = "group",
		name = "Rank Tuning",
		desc = "0 is disabled",
		args = {
			ksrank1 = {
				type = 'range',
				name = 'KS Rank 1',
				desc = 'Number of kills to reach Rank 1',
				width = "full",
				get = function() return dgks.db.profile.ksrank[1] end,
				set = function(info, v) dgks.db.profile.ksrank[1] = v end,
				disabled = function() if (dgks.db.profile.style == "dota") then return false else return true end end,
				min = 1,
				max = 50,
				step = 1
			},
			ksrank2 = {
				type = 'range',
				name = 'KS Rank 2',
				desc = 'Number of kills to reach Rank 2',
				width = "full",
				get = function() return dgks.db.profile.ksrank[2] end,
				set = function(info, v) dgks.db.profile.ksrank[2] = v end,
				disabled = function() if (dgks.db.profile.style == "dota") then return false else return true end end,
				min = 0,
				max = 50,
				step = 1
			},
			ksrank3 = {
				type = 'range',
				name = 'KS Rank 3',
				desc = 'Number of kills to reach Rank 3',
				width = "full",
				get = function()
					return dgks.db.profile.ksrank[3]
				end,
				set = function(info, v)
					dgks.db.profile.ksrank[3] = v
				end,
				disabled = function() if (dgks.db.profile.style == "dota") then return false else return true end end,
				min = 0,
				max = 50,
				step = 1
			},
			ksrank4 = {
				type = 'range',
				name = 'KS Rank 4',
				desc = 'Number of kills to reach Rank 4',
				width = "full",
				get = function()
					return dgks.db.profile.ksrank[4]
				end,
				set = function(info, v)
					dgks.db.profile.ksrank[4] = v
				end,
				disabled = function() if (dgks.db.profile.style == "dota") then return false else return true end end,
				min = 0,
				max = 50,
				step = 1
			},
			ksrank5 = {
				type = 'range',
				name = 'KS Rank 5',
				desc = 'Number of kills to reach Rank 5',
				width = "full",
				get = function()
					return dgks.db.profile.ksrank[5]
				end,
				set = function(info, v)
					dgks.db.profile.ksrank[5] = v
				end,
				disabled = function() if (dgks.db.profile.style == "dota") then return false else return true end end,
				min = 0,
				max = 50,
				step = 1
			},
			ksrank6 = {
				type = 'range',
				name = 'KS Rank 6',
				desc = 'Number of kills to reach Rank 6',
				width = "full",
				get = function() return dgks.db.profile.ksrank[6] end,
				set = function(info, v)	dgks.db.profile.ksrank[6] = v end,
				disabled = function() if (dgks.db.profile.style == "dota") then return false else return true end end,
				min = 0,
				max = 50,
				step = 1
			},
			ksrank7 = {
				type = 'range',
				name = 'KS Rank 7',
				desc = 'Number of kills to reach Rank 7',
				width = "full",
				get = function() return dgks.db.profile.ksrank[7] end,
				set = function(info, v)	dgks.db.profile.ksrank[7] = v end,
				disabled = function() if (dgks.db.profile.style == "dota") then return false else return true end end,
				min = 0,
				max = 50,
				step = 1
			},
			utrank = {
				type = 'range',
				name = 'Unreal Tournament Multiplier',
				width = "double",
				desc = 'Number of kills between notifies, ex: 3 would play sounds at 3,9,12,...',
				get = function() return dgks.db.profile.utrank end,
				set = function(info, v) dgks.db.profile.utrank = v end,
				disabled = function() if (dgks.db.profile.style == "ut") then return false else return true end end,
				min = 1,
				max = 10,
				step = 1
			}
	
		}
	}
	return ranks
end

local function giveSoundFileSetup()
	local soundfilesetup = {
		type = "group",
		name = "Sound File Setup",
		desc = "For setting up custom sounds only",
		args = {
			resetkssound = {
				type = 'execute',
				width = "full",
				name = 'Reset to default files',
				func = function() dgks.db.profile.kssound = dgks.db.defaults.profile.kssound end,
			},
			kssound1 = {
				type = 'input',
				name = 'KS Sound 1',
				desc = 'Choose a sound file',
				usage = "End the name of a sound file",
				get = function()
					return dgks.db.profile.kssound[1]
				end,
				set = function(info, v)
					dgks.db.profile.kssound[1] = v
				end
			},
			kssound2 = {
				type = 'input',
				name = 'KS Sound 2',
			desc = 'Choose a sound file',
				usage = "End the name of a sound file",
				get = function()
				return dgks.db.profile.kssound[2]
					end,
				set = function(info, v)
					dgks.db.profile.kssound[2] = v
				end
				},
			kssound3 = {
				type = 'input',
				name = 'KS Sound 3',
				desc = 'Choose a sound file',
				usage = "End the name of a sound file",
				get = function()
					return dgks.db.profile.kssound[3]
				end,
				set = function(info, v)
					dgks.db.profile.kssound[3] = v
				end
			},
			kssound4 = {
				type = 'input',
				name = 'KS Sound 4',
				desc = 'Choose a sound file',
				usage = "End the name of a sound file",
				get = function()
					return dgks.db.profile.kssound[4]
				end,
				set = function(info, v)
					dgks.db.profile.kssound[4] = v
				end
			},
			kssound5 = {
				type = 'input',
				name = 'KS Sound 5',
				desc = 'Choose a sound file',
				usage = "End the name of a sound file",
				get = function()
					return dgks.db.profile.kssound[5]
				end,
				set = function(info, v)
					dgks.db.profile.kssound[5] = v
				end
			},
			kssound6 = {
				type = 'input',
				name = 'KS Sound 6',
				desc = 'Choose a sound file',
				usage = "End the name of a sound file",
				get = function()
					return dgks.db.profile.kssound[6]
				end,
				set = function(info, v)
					dgks.db.profile.kssound[6] = v
				end
			},
			kssound7 = {
				type = 'input',
				name = 'KS Sound 7',
				desc = 'Choose a sound file',
				usage = "End the name of a sound file",
				get = function()
					return dgks.db.profile.kssound[7]
				end,
				set = function(info, v)
					dgks.db.profile.kssound[7] = v
				end
			},
			prepare = {
				type = 'input',
				name = 'Prepare Sound',
				desc = 'Choose a sound file',
				usage = "Enter the name of the sound file",
				get = function()
					return dgks.db.profile.kssoundP
				end,
				set = function(info, v)
					dgks.db.profile.kssoundP = v
				end
			},
			executesound = {
				type = 'input',
				name = 'Execute Sound',
				desc = 'Choose a sound file',
				usage = "Enter the name of the sound file",
				get = function()
					return dgks.db.profile.kssoundE
				end,
				set = function(info, v)
					dgks.db.profile.kssoundE = v
				end
			}
		}
	}
	return soundfilesetup
end

local function giveOutput()
	local output = {
		name = "Combat Message Output",
		type = "group",
		args = {
			desc = {
				type = "description",
				name = "You can select where you want dG Killshot Combat messages displayed from this screen.",
				order = 0
			},
			sink = dgks:GetSinkAce3OptionsDataTable(),
		}
	}
	-- hacks borrowed from Witch Hunt
	output.args.sink.order = 1
	output.args.sink.inline = true
	--output.args.sink.name = ""
	return output
end

-- Settings tab of the dG KillShot window: one sub-tab per settings page
local function giveSettings()
	local pages = {
		{ "general", giveGeneral(), "General" },
		{ "broadcasts", giveBroadcasts(), "Broadcasts" },
		{ "duels", giveDuels(), "Duels" },
		{ "screenshots", giveScreenshots(), "Screenshots" },
		{ "ranks", giveRanks(), "Ranks" },
		{ "output", giveOutput(), "Text Output" },
		{ "history", giveHistorySettings(), "History" },
	}
	local settings = { type = "group", name = "Settings", childGroups = "tab", args = {} }
	for i, page in ipairs(pages) do
		local group = page[2]
		group.name = page[3]
		group.order = i
		settings.args[page[1]] = group
	end
	return settings
end

-- The page in Blizzard's Settings panel: everything lives in the dG KillShot window now
local function giveLauncher()
	return {
		type = "group",
		name = "dG KillShot",
		args = {
			desc = {
				type = "description",
				order = 1,
				fontSize = "medium",
				name = "Stats, history and all settings are in the dG KillShot window.\n\nOpen it with /dgks or by clicking the minimap button.\n",
			},
			open = {
				type = "execute",
				order = 2,
				name = "Open dG KillShot",
				func = function() dgks:ShowMainWindow("settings") end,
			},
		},
	}
end

local defaults = {
	profile = {
		configversion = newestconfigversion,
		maxstreak = 0,
		maxdeathstreak = 0,
		ksemote = "has killed $v! Streak of $s!",
		dueltxtemote = false,
		duelcustomemote = "has defended his honor against $v! Streak of $s!",
		kstext = "$k killed $v!",
		dueltext = "$k has defeated $v!",
		soundpack = "male",
		soundpath = "Interface\\AddOns\\dgks\\sounds\\",
		dotxtemote = false,
		doemote = "none",
		duelemotewin = "BOW",
		duelemoteloss = "BOW",
		duelhumiliation = true,
		doscreenshotonkill = false,
		doscreenshotonstreak = false,
		doscreenshotonmultikill = false,
		doscreenshotonduelwin = false,
		doscreenshotonduelloss = false,
		doscreenshotondeath = false,
		--dopet = false,
		style = "dota",
		docombattext = true,
		dobroadcasts = true,
		doguild = true,
		dobg = true,
		doraid = true,
		dofriends = true,
		dosound = true,
		soundchannel = "Master",
		dopve = false,
		dozonechange = false,
		dopreparesound = false,
		doexecutesound = false,
		doexecutesoundpve = false,
		doexecutepercent = 25,
		dochatbox = true,
		utrank = 3,
		ksrank = {1, 2, 4, 6, 8, 10, 12},
		kssound = {"ownage.ogg", "killingspree.ogg", "rampage.ogg", "dominating.ogg", "unstoppable.ogg", "godlike.ogg", "whickedsick.ogg"},
		kssoundM = {"doublekill.ogg", "multikill.ogg", "megakill.ogg", "ultrakill.ogg", "monsterkill.ogg", "ludicrouskill.ogg", "holyshit.ogg"},
		kssoundP = "prepare.ogg",
		kssoundE = "finishhim.ogg",
		kstextM = {"DOUBLEKILL!", "MULTIKILL!", "MEGAKILL!", "ULTRAKILL!!!", "MONSTERKILL!!!", "LUDICROUSKILL!!!", "H O L Y  S H I T!!!"},
		killlog = {},
		damageDealers = {},
		killList = {},
		deathList = {},
		kssoundH = "humiliation.ogg",
		sink20Sticky = true,
		sink20OutputSink = "Default",
		sink20ScrollArea = "Outgoing",
		historyShare = true, -- Share our kills and deaths with the guild history
		historyRetentionDays = 90, -- Guild history older than this is pruned; personal history is kept
		historyTooltip = true, -- Show kill and death counts when mousing over a player
		minimap = { hide = false, angle = 200 }, -- Minimap button (dgks_minimap.lua)
		guessKiller = true, -- When the Death Recap cannot name the killer, record the likely one
		deathRecap = true, -- Open the death recap window when we die (dgks_deathrecap.lua)
		inspectSpecs = true, -- Inspect nearby enemy players to learn their spec (dgks_players.lua)
		recordTeamKills = true, -- Record party and raid members' killing blows on players (team kills)
	},
}

function dgks:OnInitialize()

	-- Setup DB
	self.db = LibStub("AceDB-3.0"):New("dgksDB", defaults, true)

	self:SetSinkStorage(self.db.profile)
	-- Emote choices: aliases become real emotes, unavailable ones reset (dgks_emotelist.lua)
	self:MigrateEmoteSettings()

	-- Increment newestconfigversion to reset db to defaults when needed
	if (dgks.db.profile.configversion < newestconfigversion ) then
		dgks:Print("Config outdated, reverting to defaults.")
		dgks.db:ResetProfile()
	end

	if (addonName == "dgks_classic") then
		SendSystemMessage("Please switch to dG Killshot, the classic specific version, dG Killshot Classic, is no longer getting updates.")
		self.db.soundPath = "Interface\\AddOns\\dgks_classic\\sounds\\"
	end

	-- Setup Config Screens
	local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

	-- The dG KillShot window (dgks_history_ui.lua) draws the Overview and Settings tables in its tabs
	AceConfigRegistry:RegisterOptionsTable("dG KillShot Overview", giveOverview)
	AceConfigRegistry:RegisterOptionsTable("dG KillShot Settings", giveSettings)
	AceConfigRegistry:RegisterOptionsTable("dG KillShot File Setup", giveSoundFileSetup)

	-- Blizzard's Settings panel gets one page that opens the window
	AceConfigRegistry:RegisterOptionsTable("dG KillShot", giveLauncher)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("dG KillShot", "dG KillShot")

	-- Cannot get ACECONSOLE working correctly in latest versions so I do it the old fashioned way
	-- /dgks              toggle the dG KillShot window
	-- /dgks history      the window on its History tab
	-- /dgks settings     the window on its Settings tab (also: options, config)
	-- /dgks deathrecap   reopen the last death recap window
	-- /dgks recap        print the raw Death Recap of the last death
	SLASH_DGKS1 = "/dgks"
	SLASH_DGKS2 = "/ks"
	SlashCmdList.DGKS = function(msg)
		local cmd = type(msg) == "string" and msg:lower():match("^%s*(%S*)") or ""
		if cmd == "history" then
			dgks:ShowMainWindow("history")
		elseif cmd == "settings" or cmd == "options" or cmd == "config" then
			dgks:ShowMainWindow("settings")
		elseif cmd == "deathrecap" then
			dgks:ToggleDeathRecap()
		elseif cmd == "recap" then
			dgks:DumpRecap()
		else
			dgks:ToggleMainWindow()
		end
	end

	-- Setup Comms
	self:RegisterComm("dgks") --Killshots
	self:RegisterComm("dgksV") --Version check
	self:RegisterComm("dgksVR") --Version check responses
	self:RegisterComm("dgksDUEL") --Duels

	-- Kill and death history (dgks_history.lua)
	self.History:Initialize()
end

-- Open the dG KillShot window on its Settings tab
function dgks:OpenOptions()
	dgks:ShowMainWindow("settings")
end

-- Current killing streak and death streak, for the minimap button tooltip
function dgks:GetStreaks()
	return streak, deathstreak
end

function dgks:SoundEventHandler(info, sound)
	if (dgks.db.profile.dosound) then
		if (tonumber(GetCVar("Sound_EnableAllSound") and GetCVar("Sound_EnableSFX")) == 1) then
			--@debug@
				-- Dev Debugging functions
				self.Print("DEBUG: Sound: " .. sound )
				self.Print("DEBUG: Soundchannel: " .. dgks.db.profile.soundchannel )
			--@end-debug@
			PlaySoundFile(sound,dgks.db.profile.soundchannel)
		end
	end
end

function dgks:OnDisable()
    -- Called when the addon is disabled
end

function dgks:CombatLogEventHandler(info, timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceFlags2, destGUID, destName, destFlags, destFlags2, ...)
	
	-- Example of player kill
	-- 7/21 01:23:16.879  PARTY_KILL,Player-9-00064F35,"Ratchet-Kil'jaeden",0x511,0x0,Player-3676-09BED6E0,"Kruulmokthan-Area52",0x10548,0x0
	-- 7/21 01:23:16.879  SPELL_DAMAGE,Player-9-00064F35,"Ratchet-Kil'jaeden",0x511,0x0,Player-3676-09BED6E0,"Kruulmokthan-Area52",0x10548,0x0,585,"Smite",0x2,0000000000000000,0000000000000000,0,0,0,0,0,-1,0,0,0,0.00,0.00,628,0.0000,0,930,969,249,2,0,0,0,nil,nil,nil
    -- 7/21 01:23:16.879  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,Player-3676-09BED6E0,"Kruulmokthan-Area52",0x10548,0x0
	
	-- FIXME Use party_kill for all kills by player, use unit_died for owned pets only
	-- Remove Party Kill to test damageDealers table This maybe required to detect Feign Death
	if event == "PARTY_KILL" then
		if (destFlags == nil) then return end
		if (bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) == COMBATLOG_OBJECT_TYPE_PLAYER) or dgks.db.profile.dopve then
			-- A unit has died to someone in our party
				
			if sourceGUID == UnitGUID("player") then
							
				--@debug@
				-- Dev Debugging functions
				self.Print("DEBUG: " .. UnitName("player") .. " has landed the kill.")
				self.Print("DEBUG: " .. "Sending "..destName.." and "..timestamp.." to KillshotTX." )
				--@end-debug@
				
				-- The player has landed a killshot
				self:KillshotTX(destName, timestamp, destGUID)
			elseif bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) == COMBATLOG_OBJECT_TYPE_PLAYER
				and isGroupMember(sourceGUID) and not isGroupMember(destGUID) then
				-- A party or raid member landed the killing blow on another player: a team kill
				dgks.History:RecordTeamKill(sourceGUID, destGUID)
			end
		end
	end
	-- Check for player death by pet
	-- FIXME limit this to pet kills only
	if event == "UNIT_DIED" then
		if destName == playerName then
			-- Player has died
			local myKiller = damageDealers[destName]			
			self:PlayerDeath(myKiller)
			-- Test is probably broken
		elseif bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) == COMBATLOG_OBJECT_TYPE_PLAYER or dgks.db.profile.dopve or destName == "Test-Victim" then
				if damageDealers[destName] == "PlayerPet" then
				-- Last damage dealt to dead unit was from player
				--@debug@
				-- Dev Debugging functions
				self:Print("DEBUG: " .. UnitName("player") .. " has landed the kill.")
				self:Print("DEBUG: " .. "Sending "..destName.." and "..timestamp.." to KillshotTX." )
				--@end-debug@
				-- The player has landed a killshot,this detection method is fooled by Feign Death so we do PARTY_KILL ALSO
				self:KillshotTX(destName, timestamp, destGUID)
			end
		end
	end
	
	-- Record last damage source for pet kill and player death tracking
	if string.find(event, "_DAMAGE") then
		-- This should log pets and creatures under players control to the player
		-- This worked, but we need to superate pets -- if sourceName ~= playerName and bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) > 0 then sourceName = playerName end
		if sourceName ~= playerName and bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) > 0 then sourceName = "PlayerPet" end
		damageDealers[destName] = sourceName
		
		-- Check for execute if enabled
		if dgks.db.profile.doexecutesound or dgks.db.profile.doexecutesoundpve then
		--Only do execute if we have a target and they are hostile 
			if GetUnitName("target", true) == destName then
				-- This _DAMAGE event is for out target
				if UnitIsEnemy("player","target") then 
					-- This is an enemy
					if bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) == COMBATLOG_OBJECT_TYPE_PLAYER or dgks.db.profile.doexecutesoundpve then
						-- dest is a player or pve is enabled
						local targetHealthPercent = floor(UnitHealth("target") / UnitHealthMax("target") * 100,0)
						if targetHealthPercent <= dgks.db.profile.doexecutepercent and targetHealthPercent > 1 then
							-- Target is under threshold
							--@debug@
							-- Dev Debugging functions
							--dgks:Print("DEBUG: " .. GetUnitName("target",true) .. " " .. destName .. " " .. targetHealthPercent)
							--@end-debug@
							if targetList[GetUnitName("target",true)] == nil then
								--First time we have seen this target in execute range
								dgks:dgks_SoundPack(dgks.db.profile.kssoundE)
							elseif targetList[GetUnitName("target",true)] <= dgks.db.profile.doexecutepercent then
								--Target was already under threshold don't spam
							else
								-- Target is now below threshhold play sound
								dgks:dgks_SoundPack(dgks.db.profile.kssoundE)
							end
						end
						--Store target health in table so we can filter repeat executes
						targetList[GetUnitName("target",true)] = targetHealthPercent
						--dgks:Print(targetList[GetUnitName("target",true)])
					end
				end
			end
		end
	end 
end

function dgks:KillshotTX(txvictim,txtimestamp,txvictimGUID)
	-- One death is one kill. If the same death is reported twice with the same victim and timestamp
	-- (the combat-log path can do that through PARTY_KILL and the pet-credited UNIT_DIED branch), drop
	-- the repeat. This used to be caught by the duplicate check on our own broadcast coming back.
	if txvictimGUID ~= nil and not isSecret(txvictimGUID) then
		local key = tostring(txvictimGUID) .. "@" .. tostring(txtimestamp)
		if key == lastLocalKillKey then return end
		lastLocalKillKey = key
	end
	-- Process the detect killshot
	-- Increment killshot streak 
	streak = streak + 1
	-- Check and set multikill
	if (lastkill + 10) > txtimestamp then
		-- Ladies and Gentlemen we have a multikill
		multikill = multikill + 1;
		-- This most like will never be used except in test mode, but lets prevent the error anyways
		if (multikill > table.maxn(self.db.profile.kstextM)) then multikill = table.maxn(self.db.profile.kstextM) end
	else
		multikill =  0 
	end
	
	-- New Multikill timer
	lastkill = txtimestamp
	
	-- Reset deathstreak
	deathstreak = 0
	
	-- Handle it locally first: sounds and text must not depend on our own broadcast coming back
	-- (it does not when we are in no guild or group, or when addon messages are locked down).
	self:ProcessKillshot("dgks", playerName, txvictim, txtimestamp, streak, multikill, true)
	self.History:Record("K", txvictim, txvictimGUID, streak, multikill)

	-- Then broadcast our Killshot to other dgks users. Our own echo is dropped in OnCommReceived.
	self:SendCM("dgks",dgks:Serialize(playerName,txvictim,txtimestamp,streak,multikill))
end

function dgks:DuelTX(txvictim,txtimestamp)
	-- Process the detect killshot
	-- Increment killshot streak 
	streak = streak + 1
	
	-- Reset deathstreak
	deathstreak = 0
	
	-- Handle it locally first (see KillshotTX), then broadcast our duel win.
	-- A duel is never a multikill: the multikill counter belongs to the last killshot, so send 0.
	self:ProcessKillshot("dgksDUEL", playerName, txvictim, txtimestamp, streak, 0, true)
	self.History:Record("W", txvictim, nil, streak, 0)
	self:SendCM("dgksDUEL",dgks:Serialize(playerName,txvictim,txtimestamp,streak,0))
end

function dgks:PlayerLoss(myKiller)
	streak = 0;
	deathstreak = deathstreak + 1;
	if (deathstreak > dgks.db.profile.maxdeathstreak) then dgks.db.profile.maxdeathstreak = deathstreak end
	if (myKiller == nil) then myKiller = "Unknown Entity" end
	-- Add to log
    tinsert(dgks.db.profile.killlog, 1, "[" .. date() .. "]" .. " You were defeated by " .. myKiller .. ".")
	-- If log is too long prune it
    if (dgks.db.profile.killlog[21]) then tremove(dgks.db.profile.killlog,21) end
	-- Store in deathList
	-- If deathList doesn't exist create it
	if not dgks.db.profile.deathList[myKiller] then dgks.db.profile.deathList[myKiller] = {} end
	tinsert(dgks.db.profile.deathList[myKiller], date("%m/%d/%y %H:%M:%S"))
	if (dgks.db.profile.dochatbox) then dgks:Print("You been defeated by "..myKiller.." "..#dgks.db.profile.deathList[myKiller].." times.") end
	dgks.History:Record("L", myKiller)
	if dgks.db.profile.doscreenshotonduelloss then Screenshot() end
	if dgks.db.profile.duelemoteloss ~= "none" then
		DoEmote(dgks.db.profile.duelemoteloss, myKiller)
	end
end

function dgks:OnCommReceived(cchan, message, distribution, sender)
	
	--If broadcast type is off return
	if not dgks.db.profile.dobroadcasts and sender ~= playerName then return end
	-- If Guild broadcast is off and we received a guild broadcast just return
	if not dgks.db.profile.doguild and distribution == "GUILD" then return end
	-- If raid broadcast is off and we received a raid broadcast just return
	if not dgks.db.profile.doraid and distribution == "RAID" then return end
	if not dgks.db.profile.doraid and distribution == "PARTY" then return end
	if not dgks.db.profile.doraid and distribution == "INSTANCE_CHAT" then return end

	local timestamp = time()
	
	--Process non-serialized cchan
	--@debug@
	self:Print("OnCommReceived: CChan= " .. cchan .. " " .. message .. distribution .. sender)
	--@end-debug@
	if cchan == "dgksVR" then
		if sender ~= playerName then self:Print(sender .. " is on version " .. message) end

	elseif cchan == "dgksV" then
		-- Check for duplicates here
		if sender == lastSender and message == lastMessage and timestamp == lastTimestamp then return end
		-- Respond with our version

		--@debug@
		-- No need to print unless debugging
		self:Print(sender .. " is on version " .. message)
		--@end-debug@

		--This should always be a direct whisper
		self:SendCommMessage("dgksVR",version,"WHISPER",sender)

	elseif cchan == "dgks" or cchan == "dgksDUEL" then
		-- Our own kills are handled locally in KillshotTX/DuelTX, so a message from ourselves is only
		-- the echo of our own broadcast (GUILD/PARTY/RAID/INSTANCE_CHAT deliver it back to us). The echo
		-- is recognised by who sent it, not by the killer name inside the message, so that another
		-- player who shares our name is still heard.
		if dgks:IsOwnSender(sender) then return end
		--Verify we have a valid event
		local ok,rxkiller,rxvictim,rxtimestamp,rxstreak,rxmultikill = dgks:Deserialize(message)
		if ok then
			dgks:ProcessKillshot(cchan, rxkiller, rxvictim, rxtimestamp, rxstreak, rxmultikill, false)
		end
	end

	--Set duplicate prevention variables
	lastMessage, lastSender, lastTimestamp = message, sender, timestamp

end

-- Is this addon-message sender our own character? Senders can arrive as "Name-Realm";
-- Ambiguate() strips our own realm.
function dgks:IsOwnSender(sender)
	if isSecret(sender) or type(sender) ~= "string" or playerName == nil then return false end
	if sender == playerName then return true end
	if type(Ambiguate) == "function" then
		local ok, short = pcall(Ambiguate, sender, "none")
		if ok and not isSecret(short) and short == playerName then return true end
	end
	return false
end

-- Handle one killshot ("dgks") or duel result ("dgksDUEL"): play the sound, show the text, do
-- emotes/screenshots and update the stats. Called directly for our own kills (isLocal = true) and
-- from OnCommReceived for kills broadcast by other dgks users (isLocal = false).
function dgks:ProcessKillshot(cchan, rxkiller, rxvictim, rxtimestamp, rxstreak, rxmultikill, isLocal)
	-- The values may come from another player's client: ignore anything that is not shaped like a kill
	if type(rxkiller) ~= "string" or type(rxvictim) ~= "string" or type(rxstreak) ~= "number" or type(rxmultikill) ~= "number" then return end
	if rxmultikill ~= rxmultikill then return end -- NaN
	-- and keep the multikill number a whole number inside the configured text/sound tables
	rxmultikill = math.floor(rxmultikill)
	if rxmultikill > #self.db.profile.kstextM then rxmultikill = #self.db.profile.kstextM end
	if rxmultikill < 0 then rxmultikill = 0 end
	-- The names are used as string.gsub replacement text below, where "%" has a special meaning
	local killerText, victimText = rxkiller:gsub("%%", "%%%%"), rxvictim:gsub("%%", "%%%%")

	-- Check for duplicates here: several channels (GUILD and PARTY, say) can deliver the same kill
	-- from the same player. Our own kills come straight from the game and are never duplicates.
	if not isLocal then
		if rxkiller == lastrxkiller and rxvictim == lastrxvictim and rxtimestamp == lastrxtimestamp then return end
		-- Set duplicate prevention variables
		lastrxkiller, lastrxvictim, lastrxtimestamp = rxkiller, rxvictim, rxtimestamp
	end

	-- Generate Text
	local killshottext
	if cchan == "dgks" then
		killshottext = string.gsub(string.gsub(dgks.db.profile.kstext, "$k", killerText), "$v", victimText)
		-- Killshot Emotes
		if (dgks.db.profile.dotxtemote and isLocal) then
			local emoteText = string.gsub(string.gsub(dgks.db.profile.ksemote, "$v", victimText), "$s", streak)
			-- Defer the chat send out of the event handler context to avoid tainting the player
			C_Timer.After(0, function() SendChatMessage(emoteText, "EMOTE") end)
		end
		if (dgks.db.profile.doemote ~= "none" and isLocal) then
			-- fixme targeting doesn't seem to work with NPCs
			local emote = dgks.db.profile.doemote
			-- Defer the emote out of the event handler context to avoid tainting the player
			C_Timer.After(0, function() DoEmote(emote, rxvictim) end)
		end
	else
		killshottext = string.gsub(string.gsub(dgks.db.profile.dueltext, "$k", killerText), "$v", victimText)
		--Duel Emotes
		if (dgks.db.profile.dueltxtemote and isLocal) then
			local emoteText = string.gsub(string.gsub(dgks.db.profile.duelcustomemote, "$v", victimText), "$s", streak)
			-- Defer the chat send out of the event handler context to avoid tainting the player
			C_Timer.After(0, function() SendChatMessage(emoteText, "EMOTE") end)
		end
		if (dgks.db.profile.duelemotewin ~= "none" and isLocal) then
			-- fixme targeting doesn't seem to work with NPCs
			local emote = dgks.db.profile.duelemotewin
			-- Defer the emote out of the event handler context to avoid tainting the player
			C_Timer.After(0, function() DoEmote(emote, rxvictim) end)
		end
	end

	-- Send to sink for local output
	-- Defer sink output (a Channel sink would call SendChatMessage) out of the event handler context
	local sinkText = killshottext
	C_Timer.After(0, function() self:ScrollText(sinkText) end)

	-- Process multikill and play appropiate sound and text
	if rxmultikill > 0 then
		-- Defer sink output (a Channel sink would call SendChatMessage) out of the event handler context
		local multikillText = rxkiller .. " got a " .. self.db.profile.kstextM[rxmultikill] .. "!"
		C_Timer.After(0, function() self:ScrollText(multikillText) end)
		self:dgks_SoundPack(self.db.profile.kssoundM[rxmultikill])
	else
		self:dgks_SoundPack(dgks:GetKillshotSound(rxstreak))
	end

	-- We have landed a kill. Only a kill detected here is ours: a broadcast from another player is
	-- never added to our stats, even if it carries our name.
	if isLocal then
		local setMaxStreak = false

		-- Increment maxstreak if this is a record high
		if ( streak > dgks.db.profile.maxstreak ) then
			dgks.db.profile.maxstreak = streak
			setMaxStreak = true
		end

		-- This now triggers a global cool and most likely cannot work anymore
		-- if dgks.db.profile.dopet then C_PetJournal.SummonRandomPet(allPets) end

		if dgks.db.profile.doscreenshotonkill then Screenshot()
		elseif dgks.db.profile.doscreenshotonstreak and setMaxStreak then Screenshot()
		elseif dgks.db.profile.doscreenshotonmultikill and rxmultikill > 0 then Screenshot() end

		-- Store in killList
		if not dgks.db.profile.killList[rxvictim] then dgks.db.profile.killList[rxvictim] = {} end
		tinsert(dgks.db.profile.killList[rxvictim], date("%m/%d/%y %H:%M:%S"))
		--fixme this count my be inaccurate due to the way lua handles tables without numeric index
		if (dgks.db.profile.dochatbox) then dgks:Print("You have killed "..rxvictim.." "..#dgks.db.profile.killList[rxvictim].." times.") end
	end
end

-- flags: nil, { unknown = true } (myKiller is a reason, not a name) or { guessed = n } (a likely
-- killer out of n candidates). guid: the killer's GUID when known.
function dgks:PlayerDeath(myKiller, flags, guid)
	streak = 0;
	deathstreak = deathstreak + 1;
	if (deathstreak > dgks.db.profile.maxdeathstreak) then dgks.db.profile.maxdeathstreak = deathstreak end
	if (myKiller == nil) then myKiller = "Unknown Entity" end
	-- Add to log
    tinsert(dgks.db.profile.killlog, 1, "[" .. date() .. "]" .. " You were killed by " .. myKiller .. ".")
	-- If log is too long prune it
    if (dgks.db.profile.killlog[21]) then tremove(dgks.db.profile.killlog,21) end
	-- Store in deathList
	-- If deathList doesn't exist create it
	if not dgks.db.profile.deathList[myKiller] then dgks.db.profile.deathList[myKiller] = {} end
	tinsert(dgks.db.profile.deathList[myKiller], date("%m/%d/%y %H:%M:%S"))
	if (dgks.db.profile.dochatbox) then
		if flags and flags.unknown then
			dgks:Print("You died. Killer unknown: " .. myKiller .. ".")
		elseif flags and flags.guessed then
			dgks:Print("You were likely killed by " .. myKiller .. ".")
		else
			dgks:Print("You been murdered by "..myKiller.." "..#dgks.db.profile.deathList[myKiller].." times.")
		end
	end
	local rec = dgks.History:Record("D", myKiller, guid, nil, nil, flags)
	local recapKiller = myKiller
	if flags and flags.unknown then
		recapKiller = "killer unknown (" .. myKiller .. ")"
	elseif flags and flags.guessed then
		recapKiller = "likely killed by " .. myKiller
	else
		recapKiller = "killed by " .. myKiller
	end
	pcall(dgks.ShowDeathRecap, dgks, recapKiller, rec)
	if dgks.db.profile.doscreenshotondeath then Screenshot() end
end

-- Who killed the player, according to Blizzard's Death Recap (the only source on retail/Forever,
-- where the combat log is closed to addons). Read it the way Blizzard's own Death Recap frame does:
-- the first event is the one that caused the death, and its caster is hidden when hideCaster is set.
-- Returns name, reason. reason is one of:
--   "found"        name is the killer
--   "pending"      no recap yet; it may still be filled in, so try again shortly
--   "unavailable"  this client has no Death Recap
--   "secret"       the game hides the killer from addons here (dungeons, raids, PvP matches...)
--   "hidden"       the killing blow has no visible caster
--   "environment"  no attacker at all: falling, drowning, lava and the like
function dgks:GetRecapKiller()
	if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil, "unavailable" end
	if C_DeathRecap.HasRecapEvents then
		local ok, has = pcall(C_DeathRecap.HasRecapEvents)
		if ok and not isSecret(has) and has == false then return nil, "pending" end
	end
	local ok, events = pcall(C_DeathRecap.GetRecapEvents)
	if not ok or events == nil then return nil, "pending" end
	if isSecret(events) then return nil, "secret" end
	if type(events) ~= "table" then return nil, "pending" end
	local ev = events[1]
	if ev == nil then return nil, "pending" end
	if isSecret(ev) then return nil, "secret" end
	if type(ev) ~= "table" then return nil, "pending" end

	local hide = ev.hideCaster
	if isSecret(hide) then return nil, "secret" end
	if hide == true then return nil, "hidden" end

	local name = ev.sourceName
	if isSecret(name) then return nil, "secret" end
	if type(name) == "string" and name ~= "" then return name, "found" end
	return nil, "environment"
end

-- What to record as the killer when the recap does not name one. History marks these as unknown,
-- so they stay out of Top predators and the opponent lists.
dgks.UNKNOWN_KILLER_TEXT = {
	pending = "No death recap",
	unavailable = "No death recap",
	secret = "Hidden by the game",
	hidden = "Hidden attacker",
	environment = "Environment",
}

-- /dgks recap: print the raw Death Recap of the last death, to see what the game gives addons here.
-- Hidden (secret) values are reported as such, never compared or stored.
function dgks:DumpRecap()
	local function show(v)
		if isSecret(v) then return "<hidden by the game>" end
		if type(v) == "string" then return '"' .. v .. '"' end
		return tostring(v)
	end
	local _, instanceType = IsInInstance()
	self:Print(("Death Recap - zone: %s, instance type: %s"):format(show(GetRealZoneText()), show(instanceType)))
	if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then
		self:Print("This client has no Death Recap API.")
		return
	end
	if C_DeathRecap.HasRecapEvents then
		local ok, has = pcall(C_DeathRecap.HasRecapEvents)
		self:Print("HasRecapEvents: " .. (ok and show(has) or ("error: " .. tostring(has))))
	end
	local ok, events = pcall(C_DeathRecap.GetRecapEvents)
	if not ok then
		self:Print("GetRecapEvents error: " .. tostring(events))
		return
	end
	if isSecret(events) or type(events) ~= "table" then
		self:Print("GetRecapEvents returned " .. show(events))
		return
	end
	local count = 0
	for i = 1, 10 do
		local ev = events[i]
		if ev == nil then break end
		count = i
		if isSecret(ev) or type(ev) ~= "table" then
			self:Print(("Event %d: %s"):format(i, show(ev)))
		else
			local keys = {}
			for k in pairs(ev) do
				if not isSecret(k) and type(k) == "string" then keys[#keys + 1] = k end
			end
			table.sort(keys)
			local parts = {}
			for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. show(ev[k]) end
			self:Print(("Event %d%s: %s"):format(i, i == 1 and " (caused death)" or "", table.concat(parts, ", ")))
		end
	end
	if count == 0 then self:Print("No recap events (no death yet this session, or nothing recorded).") end
	local killer, reason = self:GetRecapKiller()
	self:Print(("dgks reads this as: %s (%s)"):format(killer or dgks.UNKNOWN_KILLER_TEXT[reason] or "?", reason))
end

function dgks:GetKillshotSound(streak)
	if (dgks.db.profile.style == "dota") then
		-- DoTA Style
		for x = 7, 1, -1 do
			if (dgks.db.profile.ksrank[x] > 0) and (streak >= dgks.db.profile.ksrank[x]) then return dgks.db.profile.kssound[x]; end
		end
	else
		-- UT Style
		if (streak == 1) then return dgks.db.profile.kssound[1]; end
		if (streak %  dgks.db.profile.utrank == 0) then 
			local uttmp = streak / dgks.db.profile.utrank
			if (uttmp > 7) then
				return dgks.db.profile.kssound[7]
			else
				return dgks.db.profile.kssound[uttmp]
			end
		else
			return
		end
	end
    --If we get here the user has messed up their config we could build some sort of safety someday but for now we will just default to kssound1 FIXME
	return dgks.db.profile.kssound[1];
end

-- Would LibSink route our text to Blizzard's floating combat text on a client with secret values?
-- "Default" falls back to Blizzard's floating combat text unless SCT or MikSBT is installed.
function dgks:SinkUsesBlizzardFCT()
	if issecretvalue == nil then return false end -- No secret values on this client, so no taint problem
	local output = dgks.db.profile.sink20OutputSink
	if output == "Blizzard" then return true end
	if output == nil or output == "Default" then
		return not (_G.SCT or _G.MikSBT)
	end
	return false
end

function dgks:ScrollText(msg)
	
	tinsert(dgks.db.profile.killlog, 1, "[" .. date() .. "] " .. msg)
	if (dgks.db.profile.killlog[21]) then tremove(dgks.db.profile.killlog,21) end
	
	-- Also print to the chat window when "Print killshots and deaths in chatbox" is on, so the
	-- text is visible even if the combat text output isn't. Skip when the output sink is already
	-- ChatFrame, otherwise the line would print twice.
	if dgks.db.profile.dochatbox and dgks.db.profile.sink20OutputSink ~= "ChatFrame" then
		dgks:Print(msg)
	end

	if (dgks.db.profile.docombattext) then
		--if (GetCVar("enableFloatingCombatText") == "0") then
		--	dgks:Print("Setting Combat Scrolling Text for Self to enabled. Please /reload your UI or restart client.")
		--	SetCVar("enableFloatingCombatText", 1)
		--end
		-- On clients with secret values, writing to Blizzard's floating combat text from addon code
		-- taints its frame. Blizzard's own combat text (heals, damage) then runs tainted and errors on
		-- every secret number it compares ("execution tainted by 'dgks'"), for the rest of the session.
		-- A pcall cannot catch that, because the error happens later in Blizzard's code, so never
		-- send our text there: use the error frame instead.
		if dgks:SinkUsesBlizzardFCT() then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage(msg, 1.0, 0.1, 0.1, 1.0)
			end
			return
		end
		-- The selected output can still raise an error. Never let that reach the player: show the
		-- line in the error frame instead.
		local ok = pcall(dgks.Pour, dgks, msg, 1.0, 0.1, 0.1)
		if not ok then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage(msg, 1.0, 0.1, 0.1, 1.0)
			end
			if not dgks.pourFallbackNoticed then
				dgks.pourFallbackNoticed = true
				dgks:Print("The selected text output raised an error. Showing killshot text in the error frame instead; pick another output under /dgks > Combat Text Output.")
			end
		end
		
	end
end

-- FIXME Entire version checking needs cleanup for duplicate sends
function dgks:VersionCheck()
    self:SendCM("dgksV",version)
end

function dgks:dgks_SoundPack(sound)
	-- FIXME	
	if not sound then sound = 1 end
    local soundfile = self.db.profile.soundpath .. sound
    dgks:SoundEventHandler(info, soundfile)
end

function dgks:getSoundPack()
    return self.db.profile.soundpack;
end

function dgks:setSoundPack(info, newsoundset)
    if (newsoundset == "male") then
        self.db.profile.soundpack = newsoundset
        self.db.profile.soundpath = soundPath
    elseif (newsoundset == "female") then
		self.db.profile.soundpack = newsoundset
		self.db.profile.soundpath = soundPath .. "female\\"
    elseif (newsoundset == "sexy") then
		self.db.profile.soundpack = newsoundset
		self.db.profile.soundpath = soundPath .. "sexy\\"
    elseif (newsoundset == "baby") then
		self.db.profile.soundpack = newsoundset
		self.db.profile.soundpath = soundPath .. "baby\\"
    else
        message("Error: That is not a valid option")
    end
end

function dgks:getKillLog()
	local plog = ""
	table.foreach(dgks.db.profile.killlog, function(k,v) plog = plog .. v .. "\n" end)
	return plog
end

function dgks:SendCM(cchan,msg)
	-- Example usage: self:SendCM("dgksDUEL",dgks:Serialize(playerName,txvictim,txtimestamp,streak,multikill)

	-- Our own kills are already handled locally (ProcessKillshot), so no whisper to ourselves is needed.

	if dgks.db.profile.dobroadcasts then

		-- If not Retail, send to yell
		-- FIXME can we still yell in retail even though this was a classic fix?
		-- https://wowpedia.fandom.com/wiki/WOW_PROJECT_ID
		if classic then
			self:SendCommMessage(cchan,msg,"YELL")
			--@debug@
			self:Print("Sending: CChan= " .. cchan .. " " .. msg .. " to YELL")
			--@end-debug@

		end

		if dgks.db.profile.doguild and IsInGuild() then
			self:SendCommMessage(cchan,msg,"GUILD")
			--@debug@
			self:Print("Sending: CChan= " .. cchan .. " " .. msg .. " to GUILD")
			--@end-debug@

		end

		-- Send to Battleground / Arena	
		if dgks.db.profile.dobg then
			if inBG or inArena then 
				--@debug@
				self:Print("Sending: BG CChan= " .. cchan .. " " .. msg .. " to INSTANCE_CHAT")
				--@end-debug@
				self:SendCommMessage(cchan,msg,"INSTANCE_CHAT")
			end
		end

		-- Send to Raid
		-- LFG style parties and raids use INSTANCE_CHAT
		if dgks.db.profile.doraid then
			-- Raid/Party Broadcast on

			--Standard Raid
			if IsInRaid(LE_PARTY_CATEGORY_HOME) and not inArena and not inBG then
				--@debug@
				self:Print("Sending: CChan= " .. cchan .. " " .. msg .. " to RAID")
				--@end-debug@
				self:SendCommMessage(cchan,msg,"RAID") 
			end

				-- LFG or Group Finder Raid
			if IsInRaid(LE_PARTY_CATEGORY_INSTANCE) and not inArena and not inBG then
				--@debug@
				self:Print("Sending: RAID CChan= " .. cchan .. " " .. msg .. " to INSTANCE_CHAT")
				--@end-debug@
				self:SendCommMessage(cchan,msg,"INSTANCE_CHAT")
			end

			if UnitInParty("player") and not inArena and not inBG then
				self:SendCommMessage(cchan,msg,"PARTY")
				--@debug@
				self:Print("Sending: CChan= " .. cchan .. " " .. msg .. " to PARTY")
				--@end-debug@

			end
		end

		--Whisper to friends
		if dgks.db.profile.dofriends then
			for i = 1, C_FriendList.GetNumFriends() do
				local info = C_FriendList.GetFriendInfoByIndex(i)
				if info and info.connected then
					self:SendCommMessage(cchan,msg,"WHISPER",info.name)
					--@debug@
					self:Print("Sending: CChan= " .. cchan .. " " .. msg .. " to WHISPER " .. " Name: " .. info.name)
					--@end-debug@
					--C_ChatInfo.SendAddonMessage(prefix, message, "WHISPER", info.name)
				end
			end
			--Battle.net friends

			--@debug@
			--for i = 1, BNGetNumFriends() do
			--	for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) do
			--		local game = C_BattleNet.GetFriendGameAccountInfo(i, j)
			--		if game.isOnline and game.factionName then
			--			print(game.gameAccountID, game.isOnline, game.factionName, UnitFactionGroup("player"), game.realmName, GetRealmName())
			--		end
			--	end
			--end
			--@end-debug@

			local totalBFriends, onlineBFriends = BNGetNumFriends()
			for i = 1, onlineBFriends  do
				for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) do
					local game = C_BattleNet.GetFriendGameAccountInfo(i, j)
					-- A friend can have several game accounts online at once (the Battle.net app, the mobile app,
					-- a game). Skip the ones that are not a character and keep looking: stopping at the first of
					-- them ("break") skipped every friend whose app was listed before their game.
					-- Now that every entry is looked at, also skip characters in another version of WoW: they
					-- cannot be whispered from this one.
					if game and game.characterName ~= nil and game.realmName ~= nil and game.factionName ~= nil
						and (game.wowProjectID == nil or game.wowProjectID == WOW_PROJECT_ID) then
						--@debug@
						self:Print("BNET: " .. j .. "Name: " .. game.characterName .. "Realm: " .. game.realmName .. GetRealmName())
						--@end-debug@
						--if game.realmName == GetRealmName() and game.factionName == UnitFactionGroup("player") then
						if game.factionName == UnitFactionGroup("player") then
							self:SendCommMessage(cchan,msg,"WHISPER",game.characterName)

							--@debug@
							self:Print("Sending: CChan= " .. cchan .. " " .. msg .. " to WHISPER " .. game.characterName)
							--@end-debug@
							--C_ChatInfo.SendAddonMessage(prefix, message, "WHISPER", info.name)
						end
					end
				end
			end
		end
	end
end

-- TargetCheck is used outside of debugging, so it must stay out of the debug block below.
-- The packager does not nest debug blocks, so an inner one would end the outer one early.
function dgks:TargetCheck(victimName)
	if victimName == playerGUID then return false end 	--Victim is player lets dip out
	--@debug@
	dgks:Print("DEBUG:dgks:TargetCheck(" .. victimName .. ")")
	--@end-debug@
	if string.find(victimName, "Player", 1, true) ~= nil then -- Retail/Froever is dumb and always returns false on UnitIsPlayer, so we have to check the GUID string for "Player" to determine if it is a player or not
   		return true
	else
    	return false
	end
end

--@debug@
-- Dev Debugging functions
function dgks:Test()
	-- Dev Debugging functions
	--FIXME This is now a valid test on Wow 12 API
	self:Print("DEBUG: " .. "Sending KillShot Event...")
	-- Example combat log entries
	-- Old 12/6 10:49:47.392  UNIT_DIED,0x0000000000000000,nil,0x80000000,0x80000000,0x0300000007362B6E,"Vvatsitchy-Caelestrasz",0x512,0x0
	-- Old 12/6 10:51:35.342  PARTY_KILL,0x0300000000064F35,"Ratchet",0x511,0x0,0xF130388200000029,"Horde Battle Standard",0x2148,0x0
	-- 9/12 20:28:09.501  PARTY_KILL,Player-9-00064F35,"Ratchet-Kil'jaeden",0x511,0x0,Player-9-0A43E636,"Liinx-Kil'jaeden",0x10548,0x0
	-- 7/21 01:23:16.879  PARTY_KILL,Player-9-00064F35,"Ratchet-Kil'jaeden",0x511,0x0,Player-3676-09BED6E0,"Kruulmokthan-Area52",0x10548,0x0
	-- 7/21 01:23:16.879  SPELL_DAMAGE,Player-9-00064F35,"Ratchet-Kil'jaeden",0x511,0x0,Player-3676-09BED6E0,"Kruulmokthan-Area52",0x10548,0x0,585,"Smite",0x2,0000000000000000,0000000000000000,0,0,0,0,0,-1,0,0,0,0.00,0.00,628,0.0000,0,930,969,249,2,0,0,0,nil,nil,nil
    -- 7/21 01:23:16.879  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,Player-3676-09BED6E0,"Kruulmokthan-Area52",0x10548,0x0
	self:CombatLogEventHandler(info,GetTime(),"PARTY_KILL",false,"Player-9-00064F35","Ratchet-Kil'jaeden",0x511,0x0,"Player-3676-09BED6E0","Test-Victim",0x10548,0x0)
	self:CombatLogEventHandler(info,GetTime(),"SPELL_DAMAGE",false,"Player-9-00064F35","Ratchet-Kil'jaeden",0x511,0x0,"Player-3676-09BED6E0","Test-Victim",0x10548,0x0,585,"Smite",0x2,0000000000000000,0000000000000000,0,0,0,0,0,-1,0,0,0,0.00,0.00,628,0.0000,0,930,969,249,2,0,0,0,nil,nil,nil)
	self:CombatLogEventHandler(info,GetTime(),"UNIT_DIED",false,0000000000000000,nil,0x80000000,0x80000000,"Player-3676-09BED6E0","Test-Victim",0x10548,0x0)
end

function dgks:TestPlayerDeath()
	-- Example from combat log
	-- Old 12/6 10:50:47.727  RANGE_DAMAGE,0x0300000006B14637,"Kumonu-Ner'zhul",0x10548,0x0,0x0300000000064F35,"Ratchet",0x511,0x0,75,"Auto Shot",0x1,10990,-1,1,0,0,0,nil,nil,nil
	-- Old 12/6 10:50:48.308  UNIT_DIED,0x0000000000000000,nil,0x80000000,0x80000000,0x0300000000064F35,"Ratchet",0x511,0x0
	-- 07202018 7/21 00:34:33.944  SPELL_PERIODIC_DAMAGE,Player-11-0A947E83,"Invictusgg-Tichondrius",0x548,0x0,Player-9-00064F35,"Ratchet-Kil'jaeden",0x511,0x0,198097,"Creeping Venom",0x8,0000000000000000,0000000000000000,0,0,0,0,0,-1,0,0,0,0.00,0.00,92,0.0000,0,116,134,97,8,0,0,0,nil,nil,nil
	-- 07202018 7/21 00:34:33.944  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,Player-9-00064F35,"Ratchet-Kil'jaeden",0x511,0x0
	self:Print("DEBUG: " .. "Sending Player Death Event...")
	self:CombatLogEventHandler(info,GetTime(),"RANGE_DAMAGE",false,0x030000000086920F,"KillerName",0x548,0x0,UnitGUID("Player"),playerName,0x511,50622,"Auto Shot",0x1,10990,-1,1,0,0,0,nil,nil,nil)
	self:CombatLogEventHandler(info,GetTime(),"UNIT_DIED",false,0x0000000000000000,nil,0x80000000,0x80000000,UnitGUID("Player"),playerName,0x511,0x0)
end
--@end-debug@

if classic then 
	function events:COMBAT_LOG_EVENT_UNFILTERED(info, event, ...)
		local timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceFlags2, destGUID, destName, destFlags, destFlags2 = CombatLogGetCurrentEventInfo()
		-- Keep the last seconds of damage we take for the death recap window (dgks_deathrecap.lua)
		if destGUID == playerGUID then pcall(dgks.TrackDamageTaken, dgks, CombatLogGetCurrentEventInfo()) end
		-- Remember the players we fight, so kill and death records can name their class (dgks_players.lua)
		if destGUID == playerGUID then
			dgks.Players:NoteCombatant(sourceGUID, sourceName)
		elseif sourceGUID == playerGUID then
			dgks.Players:NoteCombatant(destGUID, destName)
		end
		dgks:CombatLogEventHandler(info, timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceFlags2, destGUID, destName, destFlags, destFlags2, ...)
	end 
	else
	-- This section handles Retail and Forever
	local inInstance, instanceType = IsInInstance()
	-- If we are in an instance we will not use the PARTY_KILL event, since it is protected
	function events:PARTY_KILL(attackerGUID, targetGUID)
		-- In restricted content the GUIDs arrive as secret values, which addon code cannot compare or inspect.
		-- This guard must stay outside the debug block below, which is stripped from release builds.
		if isSecret(attackerGUID) or isSecret(targetGUID) then return end
		--@debug@
			if isSecret(attackerGUID) then attackerGUID = "Attacker-SECRET" end
			if isSecret(targetGUID) then targetGUID = "Target-SECRET" end
				dgks:Print(
				"DEBUG:EVENT:PARTY_KILL: attackerGUID: " .. tostring(attackerGUID) .. 
				" targetGUID: " .. tostring(targetGUID) .. 
				" UnitIsPlayer(): " .. tostring(UnitIsPlayer(targetGUID)) .. 
				" dgksTargetCheck: " .. tostring(dgks:TargetCheck(targetGUID)))
		--@end-debug@
		-- If we are attacker and victim is a playr or pve is enabled, send the killshot
		if attackerGUID == playerGUID and (dgks:TargetCheck(targetGUID) or dgks.db.profile.dopve) then
			local timestamp = GetTime() --Set timestamp because retail does not provide it in the PARTY_KILL event
			local _, _, _, _, _, vName, playerServer = GetPlayerInfoByGUID(targetGUID)
			if vName == nil then
				--Could be an NPC, if in an instance even we will still get nil
				vName, playerServer = UnitNameFromGUID(targetGUID)		
			end
			if vName ~= nil then
				--@debug@
				dgks:Print("DEBUG: " .. "Sending "..vName.." and "..timestamp.." to KillshotTX." )
				--@end-debug@
				dgks:KillshotTX(vName, timestamp, targetGUID)
			end
		elseif attackerGUID ~= playerGUID and dgks:TargetCheck(targetGUID)
			and isGroupMember(attackerGUID) and not isGroupMember(targetGUID) then
			-- A party or raid member landed the killing blow on another player: a team kill
			dgks.History:RecordTeamKill(attackerGUID, targetGUID)
		end --if attackerGUID
	end
	-- Likely killer, for deaths the Death Recap cannot name: an enemy player who is targeting us when
	-- we die, or who switched their target to us in the last few seconds. Right in a 1v1, a guess in
	-- a group fight. Where the game hides unit comparisons (dungeons, raids) nothing is found.
	local recentTargeters = {} -- [Name-Realm] = { t = GetTime(), guid = guid }
	local GUESS_WINDOW = 8 -- seconds
	local guessUnits = { "target", "focus", "mouseover", "softenemy" }
	for i = 1, 40 do guessUnits[#guessUnits + 1] = "nameplate" .. i end
	for i = 1, 5 do guessUnits[#guessUnits + 1] = "arena" .. i end

	-- Calls fn and returns its first result, or nil if it failed or is hidden from addons
	local function readable(fn, ...)
		local ok, v = pcall(fn, ...)
		if not ok or isSecret(v) then return nil end
		return v
	end

	-- If unit is an enemy player whose target is us, returns their "Name-Realm" and GUID
	local function enemyTargetingMe(unit)
		if readable(UnitExists, unit) ~= true then return nil end
		if readable(UnitIsPlayer, unit) ~= true then return nil end
		if readable(UnitCanAttack, "player", unit) ~= true then return nil end
		-- Is their target us? Compare GUIDs: UnitIsUnit on a compound token ("nameplate3target") always
		-- returns a secret on retail, while UnitGUID stays readable along a chain of player-controlled units.
		local targetGUID = readable(UnitGUID, unit .. "target")
		if type(targetGUID) ~= "string" or targetGUID ~= UnitGUID("player") then return nil end
		local ok, name, realm = pcall(UnitFullName, unit)
		if not ok or isSecret(name) or type(name) ~= "string" or name == "" then return nil end
		if isSecret(realm) or type(realm) ~= "string" or realm == "" then realm = GetNormalizedRealmName() end
		local guid = readable(UnitGUID, unit)
		return name .. "-" .. realm, (type(guid) == "string") and guid or nil
	end

	function events:UNIT_TARGET(unit)
		if not dgks.db.profile.guessKiller or isSecret(unit) or type(unit) ~= "string" then return end
		local name, guid = enemyTargetingMe(unit)
		if name then recentTargeters[name] = { t = GetTime(), guid = guid } end
	end

	-- Returns the likely killer's name, GUID and how many enemies were candidates, or nil
	local function guessKiller()
		local now, found, count = GetTime(), {}, 0
		for _, unit in ipairs(guessUnits) do
			local name, guid = enemyTargetingMe(unit)
			if name and not found[name] then
				local seen = recentTargeters[name]
				found[name] = { guid = guid, t = seen and seen.t or 0, current = true }
				count = count + 1
			end
		end
		for name, seen in pairs(recentTargeters) do
			if not found[name] and now - seen.t <= GUESS_WINDOW then
				found[name] = { guid = seen.guid, t = seen.t, current = false }
				count = count + 1
			end
		end
		wipe(recentTargeters)
		-- Prefer someone still targeting us; among those, whoever turned to us last
		local bestName, best
		for name, c in pairs(found) do
			if not best or (c.current and not best.current) or (c.current == best.current and c.t > best.t) then
				bestName, best = name, c
			end
		end
		if not best then return nil end
		return bestName, best.guid, count
	end

	local deathPending = false
	function events:PLAYER_DEAD()
		-- We have died. PLAYER_DEAD fires once per death and carries nothing to compare, so it also works
		-- where UNIT_DIED hides its GUID. The combat log is closed to addons on retail/Forever, so ask
		-- Blizzard's Death Recap who dealt the damage. The recap may not be filled in the instant we
		-- die, so retry briefly before falling back to the placeholder. Each death is recorded once.
		if deathPending then return end
		deathPending = true
		streak = 0
		-- Look for a likely killer now, while the enemies around us still have us targeted
		local guessName, guessGUID, guessCount
		if dgks.db.profile.guessKiller then
			local ok, n, g, c = pcall(guessKiller)
			if ok then guessName, guessGUID, guessCount = n, g, c end
		end
		local attempts = 0
		local function resolveKiller()
			attempts = attempts + 1
			-- A failing lookup must not leave deathPending set, or later deaths would be ignored
			local ok, killer, reason = pcall(dgks.GetRecapKiller, dgks)
			if not ok then killer, reason = nil, "pending" end
			-- Only an empty recap is worth waiting for; give it up to 5 seconds
			if reason ~= "pending" or attempts >= 10 then
				deathPending = false
				if killer then
					dgks:PlayerDeath(killer)
				elseif guessName and reason ~= "environment" then
					dgks:PlayerDeath(guessName, { guessed = guessCount }, guessGUID)
				else
					dgks:PlayerDeath(dgks.UNKNOWN_KILLER_TEXT[reason] or "No death recap", { unknown = true })
				end
			else
				C_Timer.After(0.5, resolveKiller)
			end
		end
		C_Timer.After(0.5, resolveKiller)
	end
end

-- Are we inside an arena or battleground? This decides which chat channel carries broadcasts.
-- (The old check "IsActiveBattlefieldArena() ~= nil" was always true, because that function
-- returns false, not nil, outside arenas.)
local function updatePvPInstanceState()
	local _, instanceType = IsInInstance()
	if isSecret(instanceType) then instanceType = nil end
	inArena = (instanceType == "arena")
	inBG = (instanceType == "pvp")
end

function events:ZONE_CHANGED_NEW_AREA(info, event, ...)
	
	if (dgks.db.profile.dozonechange) then
		streak = 0
		deathstreak = 0
	end

	-- Check for Arena and Battleground
	updatePvPInstanceState()

	--if (dgks.db.profile.dopreparesound) then
		--local junk
		--junk, inbg = IsInInstance()
		--if inbg == "pvp" or IsActiveBattlefieldArena() then
			--fixme dgks:dgks_SoundPack(dgks.db.profile.kssoundP)
		--end
	--end
end

function events:PLAYER_ENTERING_WORLD()
	-- Login or /reload inside a battleground or arena: ZONE_CHANGED_NEW_AREA does not fire then
	updatePvPInstanceState()
end

function events:CHAT_MSG_BG_SYSTEM_NEUTRAL(msg, ...)
	-- Chat payloads can be secret values in restricted content; addon code cannot compare them
	if isSecret(msg) then return end
	-- Prepare for Battleground
	if (dgks.db.profile.dopreparesound) then
		if msg == "The battle begins in 30 seconds!" then dgks:dgks_SoundPack(dgks.db.profile.kssoundP) end
	end
end 

 function events:CHAT_MSG_SYSTEM(msg, ...)
	-- Chat payloads can be secret values in restricted content; strmatch/compare on them errors
	if isSecret(msg) then return end
	-- Prepare for Duel
	if (dgks.db.profile.dopreparesound) then
		if msg == format(DUEL_COUNTDOWN,3) then dgks:dgks_SoundPack(dgks.db.profile.kssoundP) end
	end
	-- Player fled from Duel
	if strmatch(msg, format(DUEL_WINNER_RETREAT, "(.-%--.-)", playerName)) then
		if dgks.db.profile.duelhumiliation then dgks:dgks_SoundPack(dgks.db.profile.kssoundH) end
		opponent = strmatch(msg, format(DUEL_WINNER_RETREAT, "(.-%--.-)", playerName))
		dgks:PlayerLoss(opponent)
	--fixme should probably create new msgs for duels in the future
	-- Opponent fled from Duel
	elseif strmatch(msg, format(DUEL_WINNER_RETREAT, playerName, "(.-%--.-)")) then
		opponent = strmatch(msg, format(DUEL_WINNER_RETREAT, playerName, "(.-%--.-)"))
		dgks:DuelTX(opponent,GetTime())
	-- Won Duel
	elseif strmatch(msg, format(DUEL_WINNER_KNOCKOUT, playerName, "(.-%--.-)")) then
		opponent = strmatch(msg, format(DUEL_WINNER_KNOCKOUT, playerName, "(.-%--.-)"))
		dgks:DuelTX(opponent,GetTime())
	-- Lost Duel
	elseif strmatch(msg, format(DUEL_WINNER_KNOCKOUT, "(.-%--.-)", playerName)) then
		opponent = strmatch(msg, format(DUEL_WINNER_KNOCKOUT, "(.-%--.-)", playerName))
		dgks:PlayerLoss(opponent,GetTime())
	else
		--@debug@
		-- Dev Debugging functions - This will print all system messages to the chat window, which is useful for debugging
		--dgks:Print("DEBUG: " .. msg)
		--@end-debug@
	end
end

function dgks:OnEnable()
	--self:RegisterEvent("CHAT_MSG_ADDON", "AddonMessageHandler")
	--OnEvent runs the function events:event
	-- NOTE: must be SetScript (not HookScript) - HookScript is a SecureFrame (Blizzard UI only)
	-- API; calling it here fires ADDON_ACTION_FORBIDDEN and protects the frame, which then
	-- also blocks the RegisterEvent calls below.
	frame:SetScript("OnEvent", function(self, event, ...)
		events[event](self,...);
	end);
	--Register all events with function events:event
	for k, v in pairs(events) do
		frame:RegisterEvent(k);
	end
	
	--Setup variables
	playerGUID = UnitGUID("player")
	playerClass, _, playerRace, playerSex, _, playerName, _ = GetPlayerInfoByGUID(playerGUID)

	self.History:Enable()
	self.Players:Enable()
	self:SetupMinimapButton()

	--@debug@
	dgks:Print("DEBUG:OnEnable:playerName: " .. playerName .. " playerGUID: " .. playerGUID)
	--@end-debug@
end