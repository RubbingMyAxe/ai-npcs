--[[
	AI NPC
--]]

-- Lets this run if on the server-side, if it's multiplayer, doesn't let it run on the client, and if it's singleplayer, lets it run on the client.
if CLIENT and Game.IsMultiplayer then return end

local Missions = AI_NPC.Missions
local Orders = AI_NPC.Orders
local Utils = AI_NPC.Utils
local SaveData = AI_NPC.SaveData

-- Register NPCPersonalityTrait so that it can be read.
LuaUserData.RegisterType("Barotrauma.NPCPersonalityTrait")
-- Register HumanPrefab so that NpcSetIdentifier can be accessed.
LuaUserData.RegisterType("Barotrauma.HumanPrefab")
-- Make private field prevAiChatMessages accessible to help regulate NPC speach.
LuaUserData.MakeFieldAccessible(Descriptors["Barotrauma.AICharacter"], "prevAiChatMessages")

-- For accessing conversation data and blocking random conversations.
LuaUserData.MakeMethodAccessible(Descriptors["Barotrauma.CrewManager"], "CreateRandomConversation")
-- Attempted to do it through Lua, but I could not get access to the methods to clear/modify the conversation.
--LuaUserData.MakeFieldAccessible(Descriptors["Barotrauma.CrewManager"], "pendingConversationLines")

-- For overriding character issues speach like "Help! I am bleeding!".
LuaUserData.MakeMethodAccessible(Descriptors["Barotrauma.HumanAIController"], "SpeakAboutIssues")

--LuaUserData.MakeFieldAccessible(Descriptors["Barotrauma.Location"], "loadedMissions")

-- Table to store data about when each character last spoke through AI.
local CharacterSpeechInfo = {}
local LastSpeech = 0.0

-- TODO: Fix errors with this save/load code with sub editor. Not very important.

-- Load data and create folders in case Lua was reloaded mid-session.
if Game.GameSession then

	if CLIENT or Game.ServerSettings.GameModeIdentifier == "multiplayercampaign" then
		PrintDebugInfo("Reloaded campaign mid-session: " .. Game.GameSession.GameMode.Map.Seed)
		SaveData.CurrentSaveDirectory = AI_NPC.SavePath .. "/" .. Game.GameSession.GameMode.Map.Seed
	else
		PrintDebugInfo("Reloaded other multiplayer match mid-session: " .. Game.ServerSettings.GameModeIdentifier.ToString() .. ", " .. Game.GameSession.Level.Seed)
		SaveData.CurrentSaveDirectory = AI_NPC.SavePath .. "/" .. Game.GameSession.Level.Seed
	end
	
	SaveData.SavedCharactersFile = SaveData.CurrentSaveDirectory .. "/SavedCharacters.json"
	if File.DirectoryExists(SaveData.CurrentSaveDirectory) then
		-- If there is an existing profiles file, load it.
		if AI_NPC.Config.UseCharacterProfiles and File.Exists(SaveData.SavedCharactersFile) then
			AI_NPC.CharacterProfiles = json.parse(File.Read(SaveData.SavedCharactersFile))
		end
	else
		File.CreateDirectory(SaveData.CurrentSaveDirectory)
	end
	
	Missions.LoadMissions(SaveData.CurrentSaveDirectory .. "/Missions.txt", true)
end

-- Loading data if it's campaign and previous data exists.
-- Creating folders at the start if previous data does not exist.
Hook.Add("roundStart", "LoadNPCData", function()

	if CLIENT or Game.ServerSettings.GameModeIdentifier == "multiplayercampaign" then
		PrintDebugInfo("Loaded campaign: " .. Game.GameSession.GameMode.Map.Seed)
		SaveData.CurrentSaveDirectory = AI_NPC.SavePath .. "/" .. Game.GameSession.GameMode.Map.Seed
	else
		PrintDebugInfo("Loaded other multiplayer match: " .. Game.ServerSettings.GameModeIdentifier.ToString() .. ", " .. Game.GameSession.Level.Seed)
		SaveData.CurrentSaveDirectory = AI_NPC.SavePath .. "/" .. Game.GameSession.Level.Seed
	end
	
	SaveData.SavedCharactersFile = SaveData.CurrentSaveDirectory .. "/SavedCharacters.json"
	
	if File.DirectoryExists(SaveData.CurrentSaveDirectory) then
		-- If there is an existing profiles file, load it.
		if AI_NPC.Config.UseCharacterProfiles and File.Exists(SaveData.SavedCharactersFile) then
			AI_NPC.CharacterProfiles = json.parse(File.Read(SaveData.SavedCharactersFile))
		end
	else
		File.CreateDirectory(SaveData.CurrentSaveDirectory)
	end	
	
	Missions.LoadMissions(SaveData.CurrentSaveDirectory .. "/Missions.txt", false)
end)

-- Cleaning up on round end.
-- This function only runs server-side.
Hook.Add("roundEnd", "DeleteNPCData", function()

	if CLIENT or Game.ServerSettings.GameModeIdentifier == "multiplayercampaign" then
		PrintDebugInfo("Ended campaign: " .. Game.GameSession.GameMode.Map.Seed)
		
		-- Delete missions file.
		if File.DirectoryExists(SaveData.CurrentSaveDirectory) and File.Exists(Missions.MissionsFile) then
			File.Delete(Missions.MissionsFile)
		end
	else
		-- If was a temporary game mode, delete entire directory.
		PrintDebugInfo("Ended other multiplayer match: " .. Game.ServerSettings.GameModeIdentifier.ToString() .. ", " .. Game.GameSession.Level.Seed)
		if File.DirectoryExists(SaveData.CurrentSaveDirectory) then
			File.DeleteDirectory(SaveData.CurrentSaveDirectory)
		end
	end
end)

function AI_NPC.Globals.GetPromptJSON(prompt)
	local data = {
		model = AI_NPC.Config.Model,
		messages = {{
			role = "user",
			content = prompt
		}},
		temperature = 0.7,
	}
	
	PrintDebugInfo(data["messages"][1]["content"])
	
	return json.serialize(data)
end

-- Runs player input through OpenAI's moderation API first to check that it will not be flagged for violating OpenAI's usage policies.
-- Only used if endpoint is set to OpenAI and the Moderation configuration setting is enabled.
local function ModerateInput(source, msg, character, prompt, chatType)
	if AI_NPC.Config.Moderation and string.find(AI_NPC.Config.APIEndpoint, "api.openai.com") then
		local input = {input = msg}
		local JSONinput = json.serialize(input)
		local savePath = AI_NPC.Path .. "/HTTP_Response_Moderation.txt" -- Save HTTP response to a file for debugging purposes.
		if Utils.ValidateAPISettings() then
			Networking.HttpPost("https://api.openai.com/v1/moderations", 
				function(response)
					
					local success, info = pcall(json.parse, response)
					if not success then
						print(Utils.MakeErrorText("Error parsing moderation JSON: " .. info))
						print(Utils.MakeErrorText("Reason: " .. response))
						return
					end
					
					if info["error"] then
						print(Utils.MakeErrorText("Error received from moderation API: " .. info["error"]["message"]))
						return
					end

					if not info["results"][1]["flagged"] then
						-- Send the prompt to API and process the output in MakeCharacterSpeak.
						CharacterSpeechInfo[character.Name].IsSpeaking = true
						
						if AI_NPC.Config.EnableOrders and character.TeamID == source.TeamID then
							Orders.DetermineOrder(source, character, msg, chatType)
						elseif AI_NPC.Config.EnableChat then
							AI_NPC.Globals.ProcessPlayerSpeach(source, character, msg, chatType, "")
						end
					else
						local flags = {}
						for key, val in pairs(info["results"][1].categories) do
							if val then
								table.insert(flags, key)
							end
						end
					
						print(Utils.MakeErrorText(character.Name .. "'s message disallowed by OpenAI." ))
						print(Utils.MakeErrorText("Message: " .. msg))
						print(Utils.MakeErrorText("Reasons: " .. table.concat(flags,", ")))
					end
				end, JSONinput, "application/json", { ["Authorization"] = "Bearer " .. AI_NPC.Config.APIKey }, savePath)
			return
		end
	else
		-- Send the prompt to API and process the output in MakeCharacterSpeak.
		if AI_NPC.Config.EnableOrders and character.TeamID == source.TeamID then
			Orders.DetermineOrder(source, character, msg, chatType)
		elseif AI_NPC.Config.EnableChat then
			AI_NPC.Globals.ProcessPlayerSpeach(source, character, msg, chatType, "")
		end
	end
end

-- Prevents players from changing their character name to something that would be flagged by OpenAI.
Hook.Add("tryChangeClientName", "PreventDisallowedNameChanges", function(client, newName, newJob, newTeam)
	-- Only do moderation for OpenAI API calls.
	if AI_NPC.Config.Moderation and Utils.ValidateAPISettings() and string.find(AI_NPC.Config.APIEndpoint, "api.openai.com") then
	
		local oldName = client.Name
		local input = {input = newName}
		local JSONinput = json.serialize(input)
		
		Networking.HttpPost("https://api.openai.com/v1/moderations", 
		function(response)
		
			local success, info = pcall(json.parse, response)
			if not success then
				print(Utils.MakeErrorText("Error parsing moderation JSON: " .. info))
				print(Utils.MakeErrorText("Reason: " .. response))
				return
			end
			
			if info["error"] then
				print(Utils.MakeErrorText("Error received from moderation API: " .. info["error"]["message"]))
				return
			end
			
			if info["results"][1]["flagged"] then
				local chatMessage = ChatMessage.Create("Game", string.format("Name not allowed by OpenAI: %s", newName), ChatMessageType.MessageBox, nil, nil)
				chatMessage.Color = Color(255,0,0)
				Game.SendDirectChatMessage(chatMessage, client)
				client.Name = "BadName"
				Networking.LastClientListUpdateID = Networking.LastClientListUpdateID + 1
			end
		end, JSONinput, "application/json",{["Authorization"] = string.format("Bearer %s", AI_NPC.Config.APIKey)}, nil)
	end
end)

-- Removes artifacts from the AI output.
local function SanitizeNPCSpeach(character, str)
	local message = str
	
	message = Utils.ExtractTextBetweenSecondQuotes(message)
	
	-- Removes the NPC name and colon that AI sometimes adds to start of a message.
	-- For example: "Roselle Jones:"
	local fullNameColon = character.Name .. ":"
	message = message:gsub(fullNameColon, "")
	
	-- Removes the NPC first name and colon that AI sometimes adds to start of a message.
	local firstNameColon = string.match(character.Name, "([^%s]+)") .. ":"
	message = message:gsub(firstNameColon, "")
	
	-- Removes You and colon that AI sometimes adds to start of a message.
	-- For example: "You:"
	local name_colon = "You:"
	message = message:gsub(name_colon, "")
	
	-- Remove line breaks.
	message = message:gsub("\n", "")
	
	-- Remove single slashes.
	message = message:gsub("\\", "")
	
	-- Remove double quotes and leading whitespace. Sometimes AI likes to wrap its responses in these.
	message = Utils.TrimLeadingWhitespace(Utils.RemoveQuotes(message))
	
	return message
end

local function IsCharacterStatusDialogueIdentifier(identifier)
	if string.find(identifier, "CharacterIssues") then
		return true
	elseif string.find(identifier, "DialogLowOxygen") then
		return true
	elseif string.find(identifier, "DialogBleeding") then
		return true
	elseif string.find(identifier, "DialogInsufficientPressureProtection") then
		return true
	elseif string.find(identifier, "DialogPressure") then
		return true
	else
		return false
	end
end

Hook.Patch("Barotrauma.HumanAIController", "SpeakAboutIssues", function(instance, ptable)
	
	if AI_NPC.Config.UseForCharacterIssues == "off" then
		-- Use the vanilla SpeakAboutIssues function.
		ptable.PreventExecution = false
		return
	elseif AI_NPC.Config.UseForCharacterIssues == "full" then
		-- Always use this patch.
		ptable.PreventExecution = true
	elseif AI_NPC.Config.UseForCharacterIssues == "mixed" then
		-- Use has a chance to use this patch, based on ChanceForNPCSpeech configuration setting.
		if math.random(1, 100) <= AI_NPC.Config.ChanceForNPCSpeach then
			ptable.PreventExecution = true
		else
			ptable.PreventExecution = false
			return
		end	
	else
		-- Use the vanilla SpeakAboutIssues function.
		ptable.PreventExecution = false
		return
	end

	
	local character = instance.Character
	
	if not character.IsOnPlayerTeam then
		return
	end
	
	if character.SpeechImpediment >= 100 then
		return
	end
	
	-- Use radio if character has a radio.
	local chatType = ChatMessageType.Default
	if character.Inventory.GetItemInLimbSlot(InvSlotType.Headset) then
		chatType = ChatMessageType.Radio
	end
	
	local message = "I need help! "
	local SayMessage = false
	-- TODO: Combine all of these into one message.

	-- DialogLowOxygen
	if character.Oxygen < CharacterHealth.InsufficientOxygenThreshold then
		message = message .. "I am having trouble breathing because of a lack of oxygen. "
		SayMessage = true
	end
	
	-- DialogBleeding
	local bleedingPrefab = AfflictionPrefab.Prefabs["bleeding"]
	if character.Bleeding > bleedingPrefab.TreatmentThreshold and not character.IsMedic then
		message = message .. "I need help, I am bleeding!"
		SayMessage = true
	end
	
	if (character.CurrentHull == nil or character.CurrentHull.LethalPressure > 0) and not character.IsProtectedFromPressure then
		-- DialogInsufficientPressureProtection
		if character.PressureProtection > 0 then
			message = message .. "My diving suit can't handle this pressure!"
			SayMessage = true
		-- DialogPressure
		elseif character.CurrentHull then
			message = message .. "The room I am in, " .. character.CurrentHull.DisplayName.Value .. ", has dangerously high pressure!"
			SayMessage = true
		end
	end
	
	if SayMessage then
		character.Speak(message, chatType, 0.0, "CharacterIssues", 60.0)
	end
	
end, Hook.HookMethodType.Before)

-- Some vanilla speech is very vague and does not generate good results with AI.
-- For example: "Target down!" and "I think I got it!"
-- This function adjusts it if possible.
-- Returns:
-- 1. A probability that it should be ran through AI. 80 = 80% chance.
-- 2. How long the character should wait before trying to say this message again. 60.0 = 60 seconds until the character tries to say this again.
-- 3. The adjusted message.
-- 4. Extra information to pass into the prompt.
local function GetAdjustedNPCSpeach(msg, identifier, delay, character)

	-- killedtarget + ID
	-- Used when the NPC kills a target.
	-- Example: "Target down!"
	if string.find(identifier, "killedtarget") then
		-- Remove the killedtarget from the string to get the ID.
		local targetID = identifier:gsub("killedtarget", "")
		-- Convert the ID to a number, then use it to find the character.
		targetID = tonumber(targetID)
		if targetID then
			local target = Entity.FindEntityByID(targetID)
			if target then
				if target.IsHuman then
					return "I just killed " .. target.Name, ""
				else
					local message = ""
					local extrainfo = ""
					
					local bestiaryinfo = AI_NPC.Bestiary[string.lower(target.SpeciesName.Value)]
					-- If it's a variant not found in the bestiary, get the base species name.
					if bestiaryinfo == nil then
						local basespecies = target.GetBaseCharacterSpeciesName().Value
						bestiaryinfo = AI_NPC.Bestiary[string.lower(basespecies)]
					end
					
					if bestiaryinfo then
						-- TODO: Experimental, if it is a creature let's include some information about that creature in the prompt.
						message = "I just killed a " .. bestiaryinfo.Name .. "!"
						extrainfo = extrainfo .. "A" .. bestiaryinfo.Name .. " is a " .. bestiaryinfo.Size .. ", " .. bestiaryinfo.Description .. "."
					else
						message = "I just killed a " .. target.SpeciesName.Value .. "!"
					end

					return 100, 20.0, message, extrainfo
				end
			end
		end
	end
	
	if string.find(identifier, "CharacterIssues") then
		--[[local bleedingPrefab = AfflictionPrefab.Prefabs["bleeding"]

		local message = ""
		--if not character.IsMedic then
		if character.Bleeding > bleedingPrefab.TreatmentThreshold then
			print("Custom SpeakAboutIssues")
			message = "I need help, I am bleeding!"
			return 100, 10.0, message, ""
		end
		--end
		return 0]]--
		return 100, delay, msg, ""
	end
	
	-- Used when a target is spotted.
	--[[if string.find(identifier, "fireturret") then
		-- TODO: Figure out what the target is and include details.
		if character.AIController then 
			print(character.AIController)
			if character.AIController.SelectedAiTarget then
				print(character.AIController.SelectedAiTarget)
				if character.AIController.SelectedAiTarget.Entity then
					print(character.AIController.SelectedAiTarget.Entity.SpeciesName)
				end
			end
		end
		--if character.AIController and character.AIController.SelectedAiTarget and character.AIController.SelectedAiTarget.Entity then
		--	print(character.AIController.SelectedAiTarget.Entity.SpeciesName)
		--end
		--print("   I spotted an enemy!")
		return "I am firing this turret!", ""
	end]]--
	
	-- Used when ice spire is spotted.
	if string.find(identifier, "icespirespotted") then
		return 100, 60.0, "I have spotted an ice spire, I will shoot it if we get any closer!", ""
	end
	
	-- leaksfixed doesn't need any changes.
	-- Example: "All leaks repaired in [roomname]!"
	if string.find(identifier, "leakfixed") then
		return 100, 20.0, msg, ""
	end
	
	-- Identifiers that should always be ignored go below here.
	-- They only return 0 because they are being ignored, the other values don't matter.
	
	-- Used for this script's AI messages. Ignore these.
	if string.find(identifier, "dialogaffirmative") then
		return 0
	end

	-- Used when an NPC can't get somewhere.
	-- Example: "Can't get there!"
	if string.find(identifier, "dialogcannotreachplace") then
		return 0
	end

	if string.find(identifier, "getdivinggear") then
		return 0
	end

	-- Spammed when NPC is firing a turret.
	-- Example: "Firing!"
	if string.find(identifier, "fireturret") then
		return 0
	end
	
	-- Handling all of these in SpeakAboutIssues patch.
	if string.find(identifier, "DialogLowOxygen") then
		return 0
	end
	
	if string.find(identifier, "DialogBleeding") then
		return 0
	end
	
	if string.find(identifier, "DialogInsufficientPressureProtection") then
		return 0
	end
	
	if string.find(identifier, "DialogPressure") then
		return 0
	end
	
	-- All other messages.
	return 100, 60.0, msg, ""
end

-- Tell the character what language it speaks.
local function BuildLanguagePrompt(character)
	local LanguagePrompt = ""
	
	if AI_NPC.Config.Language ~= "English" then
		LanguagePrompt = "You speak " .. AI_NPC.Config.Language .. "."
	end

	return LanguagePrompt
end

-- Tell the character the custom instructions.
local function BuildCustomInstructionsPrompt()
	return Utils.EscapeQuotes(AI_NPC.Config.CustomInstructions)
end

-- Tell the character about itself.
local function BuildDemographicsPrompt(character)
	local DemographicsPrompt = "Respond directly as <NPC_NAME>, a <PERSONALITY> <GENDER> <ROLE><SKILL>, <SUBMARINE> in a region called <REGION>. <BROKEN_ENGLISH>"

	-- Tell the character its name.
	DemographicsPrompt = DemographicsPrompt:gsub("<NPC_NAME>", character.Name)
	
	-- Tell the character what gender it is.
	local gender = character.Info.IsMale and "male" or "female"
	DemographicsPrompt = DemographicsPrompt:gsub("<GENDER>", gender)

	-- Tell the character what their role is.
	local role = AI_NPC.Utils.GetRole(character)
	DemographicsPrompt = DemographicsPrompt:gsub("<ROLE>", role)
	
	-- Tell the character the skill level of their primary job.
	-- Assistants might not have primary jobs.
	if role and character.Info.Job and character.Info.Job.PrimarySkill then
		local skillLevel = character.GetSkillLevel(character.Info.Job.PrimarySkill.Identifier)

		local skillLevels = {"novice", "mediocre", "average", "expert", "legendary"}
		local skill = skillLevels[math.floor(skillLevel / 25) + 1] or "novice"
		
		DemographicsPrompt = DemographicsPrompt:gsub("<SKILL>", " of " .. skill .. " skill")
	else
		DemographicsPrompt = DemographicsPrompt:gsub("<SKILL>", "")
	end
	
	-- Tell the character the name of their submarine.
	local SubmarinePrompt = ""	
	local character_submarine = nil
	for submarine in Submarine.Loaded do
		if submarine.TeamID == character.TeamID then
			character_submarine = submarine
			break;
		end
	end

	if character_submarine and character_submarine.Info then
		if character.IsPrisoner then
			SubmarinePrompt = "imprisoned and being transported to " .. character_submarine.Info.Name
		elseif character.IsEscorted or character.IsVip then
			SubmarinePrompt = "being escorted to " .. character_submarine.Info.Name
		else

			if character_submarine.Info.IsPlayer then
				SubmarinePrompt = "serving on a " .. character_submarine.Info.Name .. " class submarine"
				--SubmarinePrompt = SubmarinePrompt .. " " .. math.floor(character_submarine.RealWorldDepth) .. " meters below the surface"
			elseif character_submarine.Info.IsOutpost then
				if string.len(character.Info.Title.Value) > 0 then
					-- Merchants, HR Manager, etc.
					SubmarinePrompt = "serving as the " .. character.Info.Title.Value .. " on an outpost named " .. character_submarine.Info.Name
				elseif character.HumanPrefab.SpawnPointTags == "admin" then
					SubmarinePrompt = "serving as the administrator of an outpost named " .. character_submarine.Info.Name
				else
					if role == "civilian" then
						SubmarinePrompt = "living on an outpost named " .. character_submarine.Info.Name
					elseif role == "researcher" or role == "miner" or role == "clown" then
						SubmarinePrompt = "working on an outpost named " .. character_submarine.Info.Name
					elseif role == "huskcultist" or role == "huskcultecclesiast" or role == "merchanthusk" then
						SubmarinePrompt = "worshipping on an outpost named " .. character_submarine.Info.Name
					else
						SubmarinePrompt = "serving on an outpost named " .. character_submarine.Info.Name
					end
				end
			elseif character_submarine.Info.IsBeacon then
				SubmarinePrompt = "serving on a beacon station"
			else
				-- No idea what this could be.
				SubmarinePrompt = "serving on " .. character_submarine.Info.Name .. " "
			end
		end
	end
	DemographicsPrompt = DemographicsPrompt:gsub("<SUBMARINE>", SubmarinePrompt)

	local PersonalityPrompt = ""
	local BrokenEnglishPrompt = ""

	-- Tell the character about their personality trait.
	if character.Info.PersonalityTrait and character.Info.PersonalityTrait.DisplayName then
		local personality = string.lower(character.Info.PersonalityTrait.DisplayName.Value)
		
		if not character.IsPrisoner and character.IsVip then
			-- Wanted to make VIPs act more arrogant.
			-- Prisoners are also considered VIPs, did not want this to apply to them.
			DemographicsPrompt = DemographicsPrompt:gsub("<PERSONALITY>", " a snobby, arrogant<PERSONALITY> VIP")
		end

		-- Just putting "broken english" into the prompt doesn't work, have to expand on it more.
		if personality == "broken english" then
			if AI_NPC.Config.UseCharacterProfiles then
				local Profile = AI_NPC.Globals.UniqueProfiles[character.Name] or AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())]

				-- If we're using profiles and the character doesn't have one with a style, use a default style.
				if not Profile or #Profile.Style == 0 then
					BrokenEnglishPrompt = " You speak in a jumbled, fragmented, unconventional, accented style."
				end
			else
				-- If we're not using profiles, use a default style.
				BrokenEnglishPrompt = " You speak in a jumbled, fragmented, unconventional, accented style."
			end
		else
			PersonalityPrompt = " " .. personality
		end
	end
	
	DemographicsPrompt = DemographicsPrompt:gsub("<PERSONALITY>", PersonalityPrompt)
	DemographicsPrompt = DemographicsPrompt:gsub("<BROKEN_ENGLISH>", BrokenEnglishPrompt)

	-- TODO: Move the region information elsewhere, maybe?
	-- Not technically character-related but I couldn't figure out how to fit it in location.
	local biomeDisplayName = Game.GameSession.LevelData.Biome.DisplayName.Value
	DemographicsPrompt = DemographicsPrompt:gsub("<REGION>", biomeDisplayName)

	return DemographicsPrompt
end

local function BuildCharacterProfilePrompt(character)
	local CharacterProfile = nil
	
	if AI_NPC.Config.UseCharacterProfiles then
	
		if AI_NPC.UniqueProfiles[character.Name] then
			-- If it's a unique character's name, use their profile.
			CharacterProfile = Utils.ShallowCopyTable(AI_NPC.UniqueProfiles[character.Name])
			CharacterProfile.Style = table.concat(CharacterProfile.Style, ", ")
		elseif AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())] then
			CharacterProfile = AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())]
			
			-- TODO: Experimental code for saving character with map seed.
			--[[-- If it's singleplayer or a multiplayer campaign, we need to check if the profile's map seed matches for non-crew and non-unique NPCs.
			if CLIENT or Game.ServerSettings.GameModeIdentifier == "multiplayercampaign" then
				if character.IsOnPlayerTeam or UniqueProfiles[character.Name] or CharacterProfiles[character.Name].MapSeed = Game.GameSession.GameMode.Map.Seed then
					-- Character is on the player's team, a unique character, or the profile has a matching map seed.
					CharacterProfile = CharacterProfiles[character.Name]
				end
			else
				CharacterProfile = CharacterProfiles[character.Name]
			end]]--
		end
			
		-- No profile for this character, create one.
		if not CharacterProfile then		
			AssignProfile(character, false)
			CharacterProfile = AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())]
		end
	end
	
	local CharacterProfilePrompt = ""
	
	if CharacterProfile and #CharacterProfile.Description > 0 then
		CharacterProfilePrompt = CharacterProfile.Description
		if #CharacterProfile.Style > 0 then
			CharacterProfilePrompt = CharacterProfilePrompt .. " You speak in a " .. CharacterProfile.Style .. " style."
		end
	end
	
	return CharacterProfilePrompt
end

local function GetOutpostInfo(location, default)	
	if not location or not location.Faction then
		return default
	end
		
	local NameFormatString = string.lower(location.Type.Name.Value)
	return "a " .. location.Faction.Prefab.Name.Value .. " controlled " .. NameFormatString .. " named " .. default
end

-- Tell the character information about where they are.
local function BuildLocationPrompt(character)
	local LocationPrompt = ""

	-- Get the submarine (or outpost) associated with this character.
	local character_submarine = nil
	for submarine in Submarine.Loaded do
		if submarine.TeamID == character.TeamID then
			character_submarine = submarine
		end
	end
	
	-- TODO: Test unnamed hulls...
	if character_submarine and character_submarine == character.Submarine then
		-- If the character is on their own submarine, just get the room information.
		if character.CurrentHull then
			LocationPrompt = "You are currently in the " .. string.lower(character.CurrentHull.DisplayName.Value) .. "."
		end
	elseif character.Submarine and character.Submarine.Info then
		-- If the character is not on their own submarine...
		local submarine = ""

		-- Get the submarine name.
		if character.Submarine.Info.IsOutpost and character.IsOnPlayerTeam then
			local outpostinfo = GetOutpostInfo(Game.GameSession.StartLocation, character.Submarine.Info.Name)
			submarine = "visting " .. outpostinfo
		elseif character.Submarine.Info.IsOutpost then
			submarine = "onboard " .. GetOutpostInfo(Game.GameSession.StartLocation, character.Submarine.Info.Name)
		elseif character.Submarine.Info.IsBeacon then
			submarine = "onboard a beacon station"
		elseif character.Submarine.Info.IsWreck then
			submarine = "onboard a sunken and derelict " .. character.Submarine.Info.Name
		else
			submarine = "onboard a " .. character.Submarine.Info.Name
		end
			
		-- If there is a hull, get the name of that area.
		local room = ""
		if character.CurrentHull then
			room = " in the " .. string.lower(character.CurrentHull.DisplayName.Value)
		end
		
		LocationPrompt = "You are currently " .. submarine .. room .. "."
	end


	if #LocationPrompt == 0 and not character.CurrentHull then
		-- If they aren't on any submarine, then they must be in the ocean.
		LocationPrompt = "You are currently swimming outside, in the Europan sea."
	end
	
	return LocationPrompt
end

-- Tell the character what they're carrying and wearing.
local function BuildInventoryPrompt(character)
	local InventoryPrompt = ""
	
	-- Adjectives might improve the responses from AI.
	--[[local qualityAdjectives = {
	[0] = {"", "rusty ", "worn ", "poor ", "shoddy ", "crude "},
	[1] = {"", "regular ", "decent ", "typical ", "adequate "},
	[2] = {"", "great ", "excellent ", "solid ", "trustworthy ", "well-made "},
	[3] = {"", "masterwork ", "top-quality ", "exceptional ", "exquisite "}}
	
	local important_inventory = {}
	for item in character.Inventory.AllItems do
		if item.HasTag("weapon") or item.HasTag("tool") and not item.HasTag("mobilecontainer") then
			local adjectives = qualityAdjectives[item.Quality]
			local adjective = adjectives[math.random(1, #adjectives)]
			table.insert(important_inventory, adjective .. item.Name)
		end
	end]]--
	
	local important_inventory = {}
	for item in character.Inventory.AllItems do
		if not Utils.FindStringInTable(important_inventory, string.lower(item.Name)) and item.HasTag("weapon") or item.HasTag("tool") and not item.HasTag("mobilecontainer") then
			table.insert(important_inventory, string.lower(item.Name))
		end
	end
	
	if #important_inventory > 0 then
		InventoryPrompt = "You have these items: " .. table.concat(important_inventory, ", ") .. "."
	else
		InventoryPrompt = "You have no tools or weapons."
	end
	
	local ClothingPrompt = ""

	-- Tell the character they're handcuffed.
	if character.LockHands then
		ClothingPrompt = "You are are handcuffed. "
	end
	
	-- Tell the character if they're wearing a diving suit or body armor.
	local OuterClothing = character.Inventory.GetItemInLimbSlot(InvSlotType.OuterClothes)
	if OuterClothing then
		if string.lower(OuterClothing.Name) == "exosuit" then
			ClothingPrompt = ClothingPrompt .. "You are wearing a large, bulky, heavy, well-armored, nuclear powered, mechanical exosuit."
		else
			ClothingPrompt = ClothingPrompt .. "You are wearing " .. OuterClothing.Name .. "."
		end
	end

	-- TODO: Role-based additions?
	-- Medical supplies for medics?
	-- Probably too much extra text for too little benefit.

	return InventoryPrompt .. " " .. ClothingPrompt
end

-- Tell the character their currently assigned orders.
local function BuildOrdersPrompt(character)
	local OrdersPrompt = ""
	
	local important_orders = {}
	for order in character.CurrentOrders do
		table.insert(important_orders, order.Name.Value)
	end
	
	-- Only use this prompt if orders were found.
	if #important_orders > 0 then	
		 OrdersPrompt = "Your current orders in order of priority are: " .. table.concat(important_orders, ", ") .. "."
	end
	
	-- Tell the character if they are sitting or laying down.
	local CurrentActionsPrompt = ""
	if character.SelectedSecondaryItem then
		local secondaryName = string.lower(character.SelectedSecondaryItem.Name)
	
		local action = nil
		if string.find(secondaryName, "chair") then
			action = "sitting"
		elseif string.find(secondaryName, "bed") or string.find(secondaryName, "bunk") then
			action = "laying down"
		end
		
		if action then
			local actionText = "You are " .. action .. " in a " .. secondaryName .. ". "
			CurrentActionsPrompt = CurrentActionsPrompt .. actionText
		end
	end

	-- Tell the character what it is doing.
	if character.IsOnPlayerTeam and LuaUserData.IsTargetType(character.AIController.ObjectiveManager.CurrentObjective, "Barotrauma.AIObjectiveIdle") then
		CurrentActionsPrompt = "You are idle, not doing anything important."
	else
		local TurretTypes = {
			["chaingun"] = "fast-firing chain gun",
			["coilgun"] = "standard coil gun",
			["doublecoilgun"] = "burst-fire double coil gun",
			["flakcannon"] = "flak cannon",
			["pulselaser"] = "pulse laser",
			["railgun"] = "rail gun" }

		
		if character.SelectedItem then
			if character.SelectedItem.HasTag("junctionbox") then
				-- If their selected item is a junction box, they're repairing it.
				CurrentActionsPrompt = CurrentActionsPrompt .. "You are currently repairing a junction box."
			elseif character.SelectedItem.HasTag("pump") then
				CurrentActionsPrompt = CurrentActionsPrompt .. "You are currently repairing a pump."
			elseif character.SelectedItem.HasTag("periscope") then
				--If the character is currently manning a turret.
				for turret in character.SelectedItem.GetConnectedComponents(Components.Turret) do
					if turret.Item and turret.Item.Prefab and turret.Item.Prefab.Identifier and TurretTypes[turret.Item.Prefab.Identifier.Value] then
						CurrentActionsPrompt = CurrentActionsPrompt .. "You are currently stationed at the " .. TurretTypes[turret.Item.Prefab.Identifier.Value] .. " turret"
						
						local foundAmmo = false
						-- Get the ammo it's loaded with.
						for loader in turret.Item.linkedTo do
							local ammobox = loader.OwnInventory.FirstOrDefault()
							if ammobox then
								local ammobox_name = string.lower(ammobox.Name):gsub(" box", "")
								CurrentActionsPrompt = CurrentActionsPrompt .. " loaded with " .. ammobox_name .. ", scanning the water for threats."
								foundAmmo = true
								break
							end
						end
						
						if not foundAmmo then
							CurrentActionsPrompt = CurrentActionsPrompt .. ", scanning the water for threats."
						end
						
						-- Only look at the first turret since vanilla subs only have 1 turret per periscope.
						break
					end
				end
			end
		end
	end

	return OrdersPrompt .. " " .. CurrentActionsPrompt
end

-- Tell the character the current missions.
local function BuildMissionsPrompt(source, character)

	local DestinationPrompt = ""
	if not Game.GameSession.Level.IsLoadedOutpost and Game.GameSession.Level.EndLocation then
		-- Get the destination name.
		DestinationPrompt = "Your crew is enroute to " .. Game.GameSession.Level.EndLocation.DisplayName.Value .. "."
	end

	local MissionsPrompt = ""
	-- If the character is not on a player team, it won't have a mission.
	if character.IsOnPlayerTeam then
		-- Only use this prompt if missions are found.
		if string.len(Missions.CurrentMissions) > 0 then
			MissionsPrompt = "Your crew's current missions are: " .. Missions.CurrentMissions .. "."
		else
			MissionsPrompt = "Your crew is just passing through."
		end
	-- TODO: Experimental, let station administrator tell you the jobs he has available.
	--[[elseif character.HumanPrefab.SpawnPointTags == "admin" then
		local availableMissions = {}
		for mission in Game.GameSession.GameMode.Map.CurrentLocation.SelectedMissions do
		--print(Game.GameSession.GameMode.Map.CurrentLocation.loadedMissions)
		--for mission in Game.GameSession.GameMode.Map.CurrentLocation.loadedMissions do
			table.insert(availableMissions, mission.Name.ToString())
		end
		
		if #availableMissions > 0 then
			 MissionsPrompt = "You have these jobs available to give: " .. table.concat(availableMissions, ", ") .. "."
		else
			MissionsPrompt = "You have no more jobs to give."
		end]]--
	end
	
	return DestinationPrompt .. " " .. MissionsPrompt
end

-- Tell the character what crew members are nearby.
local function BuildNearbyCrewPrompt(character)
	local NearbyCrewPrompt = ""

	local nearby_crew = {}
	for other in Character.GetFriendlyCrew(character) do
		if other ~= character and other.IsInSameRoomAs(character) then
			table.insert(nearby_crew, other.Name)
		end
	end

	-- Only use this prompt if there are crew nearby.
	if #nearby_crew > 0 then
		 NearbyCrewPrompt = "You are in the same area as: " .. table.concat(nearby_crew, ", ") .. "."
	end

	return NearbyCrewPrompt
end


local function GetAfflictionText(character, affliction, strength)

	local valid_afflictions = {"gunshotwound", "blunttrauma", "lacerations", "bitewounds", "organdamage", "explosiondamage", "bleeding", "burn", "acidburn", "oxygenlow", 
								"concussion", "bloodloss", "stun", "huskinfection", "opiatewithdrawal", "opiateoverdose", "radiationsickness", 
								"morbusinepoisoning", "sufforinpoisoning", "deliriuminepoisoning", "paralysis", "nausea", "watchersgaze"}
	
	if Utils.FindStringInTable(valid_afflictions, affliction.Identifier) then
		local affliction_name = affliction.GetStrengthText().Value .. " " .. affliction.Prefab.Name.Value
		if affliction.Source and affliction.Source ~= character then
				affliction_name = affliction_name .. ", caused by " .. affliction.Source.Name
		end
		affliction_name = "(" .. affliction_name .. ") "
		return affliction_name .. affliction.Prefab.GetDescription(strength, affliction.Prefab.Description.TargetType.Self).Value
		--return " (" .. affliction.Prefab.Name.Value .. ") " .. affliction.Prefab.GetDescription(strength, affliction.Prefab.Description.TargetType.Self).Value
	else
		return nil
	end
end

-- Tell the character about its health status.
local function BuildHealthPrompt(character)

	local function SortAfflictionsBySeverity(afflictions, excludeBuffs, excludeZero, filterDuplicates, amount)
		local always_add = {"huskinfection"}
		local never_add = {"psychosis"}
		
		local filteredAfflictions = {}
		local afflictionNames = {}

		for affliction in afflictions do
			if (not excludeBuffs or not affliction.Prefab.IsBuff) and
			   (not excludeZero or affliction.Strength > 0) and
			   (affliction.Prefab.Name.Value ~= "") or 
			   Utils.FindStringInTable(always_add, affliction.Identifier) and not Utils.FindStringInTable(never_add, affliction.Identifier) then
				if not filterDuplicates or not Utils.FindStringInTable(afflictionNames, affliction.Identifier) then
					table.insert(filteredAfflictions, affliction)
					table.insert(afflictionNames, affliction.Identifier)
				else
					-- If duplicates are not allowed, replace the existing one with the more damaging one.
					for j, existingAffliction in ipairs(filteredAfflictions) do
						if existingAffliction.Prefab.Name.Value == affliction.Prefab.Name.Value then
							if affliction.DamagePerSecond > existingAffliction.DamagePerSecond or
							   (affliction.DamagePerSecond == existingAffliction.DamagePerSecond and
								(affliction.Strength / affliction.Prefab.MaxStrength) > (existingAffliction.Strength / existingAffliction.Prefab.MaxStrength)) then
								filteredAfflictions[j] = affliction
							end
							break
						end
					end
				end
			end
		end
		
		-- Sort the afflictions by DamagePerSecond and then by Strength / MaxStrength.
		table.sort(filteredAfflictions, function(a, b)
			if a.DamagePerSecond == b.DamagePerSecond then
				return (a.Strength / a.Prefab.MaxStrength) > (b.Strength / b.Prefab.MaxStrength)
			else
				return a.DamagePerSecond > b.DamagePerSecond
			end
		end)

		-- Limit the number of afflictions returned based on amount.
		if amount and amount > 0 then
			local limitedAfflictions = {}
			for i = 1, math.min(amount + 1, #filteredAfflictions) do
				table.insert(limitedAfflictions, filteredAfflictions[i])
			end
			return limitedAfflictions
		else
			return filteredAfflictions
		end
	end

	-- Tell the character its vitality, if injured.
	local healthLevels = {"You are seriously injured, close to death.", "You are heavily injured.", "You are very injured.", "You are slightly injured.", ""}
	local HealthLevelPrompt = healthLevels[math.floor(character.HealthPercentage / 25) + 1] or ""

	-- Tell the character if it has psychosis.
	local PsychosisPrompt = ""
	local PsychosisStrength = character.CharacterHealth.GetAfflictionStrengthByIdentifier("psychosis")

	if PsychosisStrength <= 10 then
		PsychosisPrompt = ""
	elseif PsychosisStrength > 10 and PsychosisStrength <= 25 then
		PsychosisPrompt = "You are hallucinating slightly."
	else
		if PsychosisStrength > 25 and PsychosisStrength <= 50 then
			PsychosisPrompt = "You are moderately hallucinating."
		elseif PsychosisStrength > 50 and PsychosisStrength <= 75 then
			PsychosisPrompt = "You are severely hallucinating."
		elseif PsychosisStrength > 75 then
			PsychosisPrompt = "You are severely hallucinating, but aren't aware of it. You don't know what's real or illusion."
		end

		-- Calculate the probability factor based on the strength of psychosis.
		local probabilityFactor = math.max(10, PsychosisStrength - 10)

		-- Add random hallucinations based on the psychosis strength.
		if math.random(1, 100) <= probabilityFactor then
			PsychosisPrompt = PsychosisPrompt .. " You can hear the reactor melting down."
		end

		if math.random(1, 100) <= probabilityFactor * 1.5 then
			if math.random(1, 100) <= 50 then
				PsychosisPrompt = PsychosisPrompt .. " You can see a fire."
			else
				PsychosisPrompt = PsychosisPrompt .. " The room you are in is flooded."
			end
		end

		if math.random(1, 100) <= 50 then
			PsychosisPrompt = PsychosisPrompt .. " You can see some broken devices that need repair."
		end

		if math.random(1, 100) <= probabilityFactor then
			if math.random(1, 100) <= 50 then
				PsychosisPrompt = PsychosisPrompt .. " You hear a growling and chewing at the hull."
			else
				PsychosisPrompt = PsychosisPrompt .. " Someone is honking a clown horn."
			end
		end
	end

	-- Tell the character if it has a concussion.
	--[[local ConcussionPrompt = ""
	local ConcussionStrength = character.CharacterHealth.GetAfflictionStrengthByIdentifier("concussion")
	if ConcussionStrength > 5 then
		ConcussionPrompt = "A concussion is causing your vision to be blurred, nausea, and a pounding headache."
	end]]--
	
	local sorted_afflictions = SortAfflictionsBySeverity(character.CharacterHealth.GetAllAfflictions(function(a) end), true, true, true, 4)

	local AfflictionDescriptions = ""
	-- List any afflictions.
	local serious_afflictions = {}
	for affliction in sorted_afflictions do
		local description = GetAfflictionText(character, affliction, affliction.Strength)
		
		if description then
			if #AfflictionDescriptions == 0 then
				AfflictionDescriptions = description
			else
				AfflictionDescriptions = AfflictionDescriptions .. ", " .. description
			end
		end
	end

	local AfflictionDescriptionPrompt = ""
	if #AfflictionDescriptions > 0 then
		AfflictionDescriptionPrompt = "Here is information about your current ailments: " .. AfflictionDescriptions
	end

	return HealthLevelPrompt .. " " .. PsychosisPrompt .. " " .. " " .. AfflictionDescriptionPrompt
end

-- Tell the character who is speaking to it.
local function BuildSourcePrompt(source, character)
	local SourcePrompt = "Speaking to you is <CREW> <NAME>, a <PERSONALITY> <GENDER> <ROLE><SKILL><APPEARANCE>."

	-- Tell the character if the source is part of their crew.
	if source.TeamID == character.TeamID then
		SourcePrompt = SourcePrompt:gsub("<CREW>", "a crewmate named")
	else
		local disposition = ""

		-- Tell the character if the source is an enemy.
		if not character.IsFriendly(source) then
			disposition = "hostile and dangerous "
		end
		SourcePrompt = SourcePrompt:gsub("<CREW>", " a " .. disposition .. "stranger named")
	end

	-- Tell the character the source's name.
	SourcePrompt = SourcePrompt:gsub("<NAME>", source.Name)

	-- Tell the character about their personality trait.
	if character.Info.PersonalityTrait and character.Info.PersonalityTrait.DisplayName then
		local personality = string.lower(character.Info.PersonalityTrait.DisplayName.Value)
		if personality == "broken english" then
			SourcePrompt = SourcePrompt:gsub("<PERSONALITY>", "")
		else
			SourcePrompt = SourcePrompt:gsub("<PERSONALITY>", " " .. personality)
		end
	else
		SourcePrompt = SourcePrompt:gsub("<PERSONALITY>", "")
	end

	-- Tell the character what gender the source is.
	local gender = character.Info.IsMale and "male" or "female"
	SourcePrompt = SourcePrompt:gsub("<GENDER>", gender)
	
	-- Tell the character what role the source is.
	local role = Utils.GetRole(source)
	SourcePrompt = SourcePrompt:gsub("<ROLE>", role)
	
	-- Tell the character the skill level of the source at their primary job.
	-- Assistants might not have primary jobs.
	if role and source.Info.Job and source.Info.Job.PrimarySkill then
		local skillLevel = source.GetSkillLevel(source.Info.Job.PrimarySkill.Identifier)

		local skillLevels = {"novice", "mediocre", "average", "expert", "legendary"}
		local skill = skillLevels[math.floor(skillLevel / 25) + 1] or "novice"
				
		SourcePrompt = SourcePrompt:gsub("<SKILL>", " of " .. skill .. " skill")
	else
		SourcePrompt = SourcePrompt:gsub("<SKILL>", "")
	end
	
	-- Tell the character what the source looks like.
	local appearance = ""
	local hair_description = ""
	local hair = source.Info.Head.HairIndex

	if hair == 0 then
		hair_description = "bald"
	elseif hair == 1 then
		hair_description = "shaved"
	end
	
	local face_description = ""
	local faceattachment = source.Info.Head.FaceAttachmentIndex

	if faceattachment == 1 then
		face_description = "a face with scarred slash marks"
	elseif faceattachment == 3 then
		face_description = "a scarred face"
	elseif faceattachment == 2 or faceattachment == 4 then
		face_description = "a dirty face"
	elseif faceattachment >= 5 and faceattachment <= 8 then
		face_description = "a tattooed face"
	elseif faceattachment >= 9 and faceattachment <= 11 then
		face_description = "a pierced face"
	elseif faceattachment == 12 then
		face_description = "sunglasses"
	elseif faceattachment == 13 or faceattachment == 14 then
		face_description = "a bandaged face"
	elseif faceattachment == 15 then
		face_description = "an eyepatch"
	end
	
	if #hair_description > 0 and #face_description > 0 then
		appearance = ", with a " .. hair_description .. " head and " .. face_description
	elseif #hair_description > 0 then
		appearance = ", with a " .. hair_description .. " head"
	elseif #face_description > 0 then
		appearance = ", with " .. face_description
	end
	
	SourcePrompt = SourcePrompt:gsub("<APPEARANCE>", appearance)
	
	return SourcePrompt
end

-- Tell the character about their submarine's state.
local function BuildSubmarineStatePrompt(character)

	-- Ignore this for NPCs that aren't on a player's crew.
	if not character.IsOnPlayerTeam then
		return ""
	end

	-- If they have strong psychosis, don't give accurate information about the sub's state.
	local PsychosisStrength = character.CharacterHealth.GetAfflictionStrengthByIdentifier("psychosis")
	if PsychosisStrength >= 50 then
		return
	end

	local isMechanic = character.IsMechanic
	local isEngineer = character.IsEngineer
	-- If they have a handheld status monitor, they can see damaged hulls, 
	-- mechanical devices, and electrical devices even if they aren't on the submarine.
	local hasStatusMonitor = false

	-- Determine if character has a status monitor.
	for item in character.Inventory.AllItems do
		if item.Prefab and item.Prefab.Identifier.Value then
			if item.Prefab.Identifier.Value == "handheldstatusmonitor" then
				isMechanic = true
				isEngineer = true
				hasStatusMonitor = true
			end
		end
	end

	-- Get the submarine (or outpost) associated with this character.
	local character_submarine = nil
	for submarine in Submarine.Loaded do
		if submarine.TeamID == character.TeamID then
			character_submarine = submarine
		end
	end

	-- If the character is not on the submarine and doesn't have a status monitor, it shouldn't know anything about the state of the submarine.
	if character_submarine ~= character.Submarine and not hasStatusMonitor then
		return ""
	end

	-- Get a list of damaged rooms.
	local damaged_hulls = {}
	for gap in character_submarine.GetGaps(false) do
		-- Determine if it's a leak in the outer hull.
		if gap.FlowTargetHull and gap.open > 0.0 and (gap.ConnectedDoor == nil) and not gap.IsRoomToRoom then
			-- No duplicates and limit to 5 to keep the list short on massive subs.
			if not Utils.FindStringInTable(damaged_hulls, gap.FlowTargetHull.DisplayName.Value) and not (#damaged_hulls > 5) then
				table.insert(damaged_hulls, gap.FlowTargetHull.DisplayName.Value)
			end
		end
	end
	
	-- Get a list of flooded rooms and fires.
	local TotalNonWetRooms = 0
	local TotalFires = 0
	
	local flooded_rooms = {}
	local flaming_devices = {}
	for hull in character_submarine.GetHulls(false) do
		
		for firesource in hull.FireSources do
			if firesource.Size.X > 0 then
				TotalFires = TotalFires + 1
			end
		end
		
		if not hull.IsWetRoom then
			TotalNonWetRooms = TotalNonWetRooms + 1
			if hull.WaterPercentage > 25 and not Utils.FindStringInTable(flooded_rooms, hull.DisplayName.Value) then
				table.insert(flooded_rooms, hull.DisplayName.Value)
			end
		end
	end
	
	-- Get a table of the categories so we can determine if something is  Machine (4) or Electrical (256).
	local MapEntityCategory = LuaUserData.CreateEnumTable("Barotrauma.MapEntityCategory")
	local ElectricCategory = MapEntityCategory["Electrical"]
	local MachineCategory = MapEntityCategory["Machine"]

	local TotalElectricalRepairables = 0
	local TotalDamagedElectricalRepairables = 0
	local damaged_electric_repairables = {}
		
	local TotalMechanicalRepairables = 0
	local TotalDamagedMechanicaRepairables = 0
	local damaged_machine_repairables = {}
		
	-- Get a list of devices that need repair, keep a running count of devices of the same type.
	for repairable in Item.RepairableItems do
		if repairable.Submarine == character_submarine and not repairable.HasTag("door") then
			local electric = Utils.HasFlag(repairable.Prefab.Category, ElectricCategory)
			local machine = Utils.HasFlag(repairable.Prefab.Category, MachineCategory)

			if electric then
				TotalElectricalRepairables = TotalElectricalRepairables + 1
			elseif machine then
				TotalMechanicalRepairables = TotalMechanicalRepairables + 1
			end

			if repairable.ConditionPercentage < 25.0 then
				-- Navigation Terminal, Junction Box, Small Pump, Status Monitor
				repairable_name = string.lower(repairable.Name)
				
				if electric then
					TotalDamagedElectricalRepairables = TotalDamagedElectricalRepairables + 1
					if damaged_electric_repairables[repairable_name] then
						damaged_electric_repairables[repairable_name] = damaged_electric_repairables[repairable_name] + 1
					else
						damaged_electric_repairables[repairable_name] = 1
					end
				elseif machine then
					TotalDamagedMechanicaRepairables = TotalDamagedMechanicaRepairables + 1
					if damaged_machine_repairables[repairable_name] then
						damaged_machine_repairables[repairable_name] = damaged_machine_repairables[repairable_name] + 1
					else
						damaged_machine_repairables[repairable_name] = 1
					end
				end
			end
		end
	end

	-- Everyone knows if the sub is breached, mechanics know specific details.
	local OuterHullStatus = ""
	if #damaged_hulls > 0 then
		if isMechanic then
			OuterHullStatus = OuterHullStatus .. "The outer hull is breached in the following areas: " .. table.concat(damaged_hulls, ", ") .. "."
		else
			OuterHullStatus = OuterHullStatus .. "The outer hull is breached."
		end
	end
	
	-- Everyone knows if the sub is on fire.
	local FireStatus = ""
	if TotalFires == 1 then
		FireStatus = FireStatus .. "There is a fire."
	elseif TotalFires > 1 then
		FireStatus = FireStatus .. "There are multiple fires."
	end
	
	-- Everyone knows if the sub is flooded, engineers know specific details.
	local FloodedStatus = ""
	if #flooded_rooms > 0 then
		local PercentageDescriptor = {"very slightly flooded", "slightly flooded", "significantly flooded", "severely flooded", "completely flooded"}
		local PercentFlooded = math.floor(#flooded_rooms / TotalNonWetRooms * 100)
		local FloodedIndex = math.min(math.floor(PercentFlooded / 25), 4) + 1
		
		if isMechanic then
			if PercentFlooded >= 75 then
				-- If the submarine is 75% to 100% flooded, there's no point in listing almost every room.
				FloodedStatus = FloodedStatus .. "The submarine is " .. PercentageDescriptor[FloodedIndex] .. "."
			else
				FloodedStatus = FloodedStatus .. "The submarine is " .. PercentageDescriptor[FloodedIndex] .. ", including these rooms: " .. table.concat(flooded_rooms, ", ") .. "."
			end
		else
			FloodedStatus = FloodedStatus .. "The submarine is " .. PercentageDescriptor[FloodedIndex] .. "."
		end
	end

	-- Engineers know how damaged the electrical systems are.
	local ElectricStatus = ""
	if TotalDamagedElectricalRepairables > 0 and isEngineer then
		local PercentageDescriptor = {"A minor amount", "Several", "Half", "Most", "All"}
		local PercentBroken = math.floor(TotalDamagedElectricalRepairables / TotalElectricalRepairables * 100)
		local BrokenIndex = math.min(math.floor(PercentBroken / 25), 4) + 1

		local listOfRepairables = {}
		local counter = 0
		for repairable, number in pairs(damaged_electric_repairables) do
			-- Limit this list to 5 devices.
			if counter >= 5 then
				break
			end
		
			if number == 1 then
				table.insert(listOfRepairables, repairable)
			else
				table.insert(listOfRepairables, string.format("%s (x%d)", repairable, number))
			end
			counter = counter + 1
		end
		
		-- If 75% to 100% of the devices are broken, there's no point in listing all of them.
		if PercentBroken >= 75 then
			ElectricStatus = ElectricStatus .. PercentageDescriptor[BrokenIndex] .. " of the electrical systems on the submarine are damaged."
		else
			ElectricStatus = ElectricStatus .. PercentageDescriptor[BrokenIndex] .. " of the electrical systems on the submarine are damaged, including: " .. table.concat(listOfRepairables, ", ") .. "."
		end
	end
	
	-- Mechanics know how damaged the machines are.
	local MechanicalStatus = ""
	if TotalDamagedMechanicaRepairables > 0 and isMechanic then
		local PercentageDescriptor = {"A minor amount", "Several", "Half", "Most", "All"}
		local PercentBroken = math.floor(TotalDamagedMechanicaRepairables / TotalMechanicalRepairables * 100)
		local BrokenIndex = math.min(math.floor(PercentBroken / 25), 4) + 1

		local listOfRepairables = {}
		local counter = 0
		for repairable, number in pairs(damaged_machine_repairables) do
			-- Limit this list to 5 devices.
			if counter > 5 then
				break
			end
		
			if number == 1 then
				table.insert(listOfRepairables, repairable)
			else
				table.insert(listOfRepairables, string.format("%s (x%d)", repairable, number))
			end
			counter = counter + 1
		end
		
		-- If 75% to 100% of the devices are broken, there's no point in listing all of them.
		if PercentBroken >= 75 then
			MechanicalStatus = MechanicalStatus .. PercentageDescriptor[BrokenIndex] .. " of the machines in the submarine are damaged."
		else
			MechanicalStatus = MechanicalStatus .. PercentageDescriptor[BrokenIndex] .. " of the machines in the submarine are damaged, including: " .. table.concat(listOfRepairables, ", ") .. "."
		end
	end
	
	return FireStatus .. " " .. OuterHullStatus .. " " .. FloodedStatus .. " " .. ElectricStatus .. " " .. MechanicalStatus
end

-- Save data to an NPC's conversation history file.
-- source = Who spoke to the NPC to trigger the reply, if any.
-- target = The NPC saying the reply.
-- message = The message text.
local function AddToConversationHistory(source, target, message)
	local filename = string.format("%s/%s - %s.txt", SaveData.CurrentSaveDirectory, tostring(target.Info.GetIdentifierUsingOriginalName()), target.Info.OriginalName)
	local messageline = ""
	
	if source then
		messageline = source.Name .. ": \"" .. message .. "\""
	else
		-- Use "You" instead of the NPC's name for better output.
		messageline = "You: \"" .. message .. "\""
	end

	if File.Exists(filename) then
		-- Append to existing file.
		File.Write(filename, File.Read(filename) .. "\r" .. messageline)
	else
		File.Write(filename, messageline)
	end
end

-- Read the NPC's conversation file and pull the last lines from it.
-- The number of lines is determined by the ConversationHistoryToUse configuration setting.
local function ReadConversationHistory(target)
	local filename = string.format("%s/%s - %s.txt", SaveData.CurrentSaveDirectory, tostring(target.Info.GetIdentifierUsingOriginalName()), target.Info.OriginalName)
	local lastLines = {}
	
	if File.Exists(filename) then
		local fileContent = File.Read(filename)
		local messages = {}
		
		-- Split the file content into lines
		for line in fileContent:gmatch("[^\r\n]+") do
			table.insert(messages, line)
		end

		-- Only get the number of lines we need, from the bottom of the file for the most recent information.
		for i = math.max(1, #messages - AI_NPC.Config.ConversationHistoryToUse), #messages do
			table.insert(lastLines, messages[i])
		end
	end
	
	return lastLines
end

-- Tell the character its previous conversation history.
local function BuildConversationHistoryPrompt(character)
	local ConversationHistoryPrompt = ""
	local messageHistory = ReadConversationHistory(character)
	
	-- If there is no conversation history data for this NPC, don't include this section.
	if #messageHistory > 0 then
		--ConversationHistoryPrompt = ConversationHistoryPrompt .. "This is the conversation so far, this is only for reference you should not format your response to match this: "
		ConversationHistoryPrompt = ConversationHistoryPrompt .. "Here's the conversation so far for reference: "

		-- Loop through each line in the conversation history that we're using.
		while #messageHistory > 0 do
			-- Save it and then remove it from the table.
			local item = table.remove(messageHistory, 1)
			-- Escape any quotes and add it to the prompt.
			ConversationHistoryPrompt = ConversationHistoryPrompt .. "\\n" .. Utils.EscapeQuotes(item) .. " "
		end
	end

	return ConversationHistoryPrompt
end

-- Split the prompt into different parts, as recommended by the OpenAI API.
-- Example:
--[[messages=[
	{"role": "system", "content": "You are a helpful assistant."},
	{"role": "user", "content": "Knock knock."},
	{"role": "assistant", "content": "Who's there?"},
	{"role": "user", "content": "Orange."},
],--]]
local function BuildJSONMessages(prompt_header, character, source, msg)
	local Messages = {}
	
	-- Add the system message.
	local header = {
		role = "system",
		content = prompt_header
	}
	table.insert(Messages, header)
	
	local messageHistory = ReadConversationHistory(character)
	
	-- If there is no conversation history data for this NPC, don't include this section.
	if #messageHistory > 0 then
		-- Loop through each line in the conversation history that we're using.
		while #messageHistory > 0 do
			-- Save it and then remove it from the table.
			local sentence = table.remove(messageHistory, 1)
			
			-- Extract the name excluding the colon.
			local name = sentence:match("^(.-):")
			local nameWithoutSpaces = ""
			
			local role = nil
			if name == "You" then
				role = "assistant"
			else
				role = "user"
				nameWithoutSpaces = name:gsub(" ", "")
			end

			-- Extract the content within quotes.
			local message = sentence:match('"([^"]+)"')

			local line = {
				role = role
			}
		
			-- Only add the name if it's not itself.
			if role == "user" then
				line.content = name .. ": " .. message
				line.name = nameWithoutSpaces
			else
				line.content = message
			end
		
			table.insert(Messages, line)
		end
	end
	
	-- Insert the current line as the last message.
	if character == source then
		local line = {
			role = "assistant",
			content = msg
		}
		table.insert(Messages, line)
	
	else
		local nameWithoutSpaces = source.Name:gsub(" ", "")
		
		local line = {
			role = "user",
			name = nameWithoutSpaces,
			content = msg
		}
		table.insert(Messages, line)
	end

	return Messages
end

-- Make the character walk toward the speaker.
local function MoveTowardSpeaker(character, speaker)
	local manager = character.AIController.ObjectiveManager
	local gotoObjective = AIObjectiveGoTo(speaker, character, manager)
	gotoObjective.SpeakIfFails = false
	gotoObjective.DebugLogWhenFails = false
	gotoObjective.AllowGoingOutside = false
	gotoObjective.CloseEnoughMultiplier = 1.5

	manager.AddObjective(gotoObjective)
end

-- Make the character speak the data from API.
local function MakeCharacterSpeak(source, msg, character, str, identifier, delay, chatType, add_to_history)	
	local speach = Utils.GetAPIResponse(str)
	
	if identifier == nil then
		identifier = Identifier.Empty
	end
	
	if string.len(speach) > 0 then
	
		speach = SanitizeNPCSpeach(character, speach)
	
		if add_to_history then
			if source ~= character and str then
				-- Add the original message from the player to the NPC's conversation log.
				AddToConversationHistory(source, character, msg)
			end
		
			-- Add this line from the NPC to the player to the NPC's conversation history.
			AddToConversationHistory(nil, character, speach)
		end

		-- Use local chat if the original message was in local chat or both characters do not have radios.
		if not (chatType == ChatMessageType.Radio and source.Inventory.GetItemInLimbSlot(InvSlotType.Headset) and character.Inventory.GetItemInLimbSlot(InvSlotType.Headset)) then
			chatType = ChatMessageType.Default
		end

		if(AI_NPC.Config.ResponseChunkSize > 0) then
			-- Split response into chunks.
			local messages = Utils.SplitBySentences(speach, AI_NPC.Config.ResponseChunkSize)

			-- Send each chunk with a delay based on its index.
			-- So first chunk is sent after 1 second, second chunk is sent after 2 seconds, etc.
			-- Adding a little extra delay after the first message to make longer messages less spammy: (index-1 * 0.5)
			-- First = 1 second, Second = 2.5 seconds, Third = 4 seconds, Fourth = 5.5 seconds
			for index, message in ipairs(messages) do
				local delay_time = index + (index - 1) * 1.5
				character.Speak(message, chatType, delay_time, identifier, delay)
			end
		else
			-- Send the entire message at once.
			character.Speak(speach, chatType, 1.0, identifier, delay)
		end
		
		-- 50% chance for an idle character to walk toward speaker when using local chat.
		if source ~= character and not character.SelectedSecondaryItem and (math.random(1, 100) <= 50) and character.IsOnFriendlyTeam(source) and chatType == ChatMessageType.Default 
		and LuaUserData.IsTargetType(character.AIController.ObjectiveManager.CurrentObjective, "Barotrauma.AIObjectiveIdle") then
			MoveTowardSpeaker(character, source)
		end
	end
	
	CharacterSpeechInfo[character.Name].IsSpeaking = false
end

-- Used to refine canned speach from NPCs with AI.
local function NPCSpeak(character, messageType, message, identifier, delay, extrainfo, add_to_history)

	if not AI_NPC.Config.EnableChat then
		return
	end

	-- Prevent spam.
	if CharacterSpeechInfo[character.Name] then
	
		if CharacterSpeechInfo[character.Name].LastSpeech then
			PrintDebugInfo("   Seconds since last speach: " .. Timer.GetTime() - CharacterSpeechInfo[character.Name].LastSpeech)
		end
		
		-- Already waiting on a response from this character.
		if CharacterSpeechInfo[character.Name].IsSpeaking then
			PrintDebugInfo("   Character is already speaking.")
			
			-- However, we've been waiting 30 seconds already so something probably went wrong.
			if (Timer.GetTime() - CharacterSpeechInfo[character.Name].LastSpeech) > 30.0 then
				-- Reset the IsSpeaking flag so that it doesn't stay stuck.
				CharacterSpeechInfo[character.Name].IsSpeaking = false
			else
				-- If it has been less than 30 seconds, maybe it's just slow.
				return false
			end
		end
		
		-- At least 5 seconds between requests.
		if (Timer.GetTime() - CharacterSpeechInfo[character.Name].LastSpeech) < 5.0 then
			PrintDebugInfo("   Blocked to prevent spam.")
			return false
		end
		
		-- At least 5 seconds between requests.
		if (Timer.GetTime() - LastSpeech) < 5.0 then
			PrintDebugInfo("   Blocked to prevent spam, globally.")
			return false
		end
	else
		CharacterSpeechInfo[character.Name] = {IsSpeaking = false, LastSpeech = 0.0}
	end

	PrintDebugInfo("   Building prompt.")
	
	local prompt_header = AI_NPC.Config.PromptInstructions
	prompt_header = prompt_header .. " <CUSTOM_INSTRUCTIONS>\\n\\n"
	prompt_header = prompt_header .. "<LANGUAGE> <DEMOGRAPHICS> <PROFILE> <MISSIONS> <LOCATION> <ORDERS> <SUBMARINE> <INVENTORY> <HEALTH> <EXTRA_INFO> <CONVERSATION_HISTORY> "
	
	local CustomInstructionsPrompt = BuildCustomInstructionsPrompt(character)
	prompt_header = prompt_header:gsub("<CUSTOM_INSTRUCTIONS>", CustomInstructionsPrompt)
	
	local LanguagePrompt = BuildLanguagePrompt(character)
	prompt_header = prompt_header:gsub("<LANGUAGE>", LanguagePrompt)
	
	local CharacterProfilePrompt = BuildCharacterProfilePrompt(character)
	prompt_header = prompt_header:gsub("<PROFILE>", CharacterProfilePrompt)
	
	local DemographicsPrompt = BuildDemographicsPrompt(character)
	prompt_header = prompt_header:gsub("<DEMOGRAPHICS>", DemographicsPrompt)
	
	local LocationPrompt = BuildLocationPrompt(character)
	prompt_header = prompt_header:gsub("<LOCATION>", LocationPrompt)
	
	local SubmarinePrompt = BuildSubmarineStatePrompt(character)
	prompt_header = prompt_header:gsub("<SUBMARINE>", SubmarinePrompt)
	
	local InventoryPrompt = BuildInventoryPrompt(character)
	prompt_header = prompt_header:gsub("<INVENTORY>", InventoryPrompt)
	
	local OrdersPrompt = BuildOrdersPrompt(character)
	prompt_header = prompt_header:gsub("<ORDERS>", OrdersPrompt)
	
	local MissionsPrompt = BuildMissionsPrompt(source, character)
	prompt_header = prompt_header:gsub("<MISSIONS>", MissionsPrompt)

	local HealthPrompt = BuildHealthPrompt(character)
	prompt_header = prompt_header:gsub("<HEALTH>", HealthPrompt)

	local ExtraInfoPrompt = extrainfo
	prompt_header = prompt_header:gsub("<EXTRA_INFO>", ExtraInfoPrompt)

	local ConversationHistoryPrompt = BuildConversationHistoryPrompt(character)
	prompt_header = prompt_header:gsub("<CONVERSATION_HISTORY>", ConversationHistoryPrompt)

	prompt_header = prompt_header .. "\\n\\nThis what you are trying to say next, but you need to transform it into the style of your character using only known information: "

	-- Save some tokens by replacing consecutive spaces with a single space.
	prompt_header = prompt_header:gsub("%s+", " ")

	-- Concatenate the header prompt with the player message.
	prompt_header = prompt_header .. "\\\"" .. message .. "\\\""

	-- Write the full prompt to a file for debugging purposes.
	File.Write(AI_NPC.Path .. "/Last_Prompt.txt", prompt_header .. "\\\"" .. message .. "\\\"")
	
	local JSONData = AI_NPC.Globals.GetPromptJSON(prompt_header)

	local savePath = AI_NPC.Path .. "/HTTP_Response.txt" -- Save HTTP response to a file for debugging purposes.

	if Utils.ValidateAPISettings() then
		-- Send the prompt to API and process the output in MakeCharacterSpeak.
		-- Comment this line out to test prompt formation without sending to API.
		CharacterSpeechInfo[character.Name].IsSpeaking = true
		CharacterSpeechInfo[character.Name].LastSpeech = Timer.GetTime()
		LastSpeech = CharacterSpeechInfo[character.Name].LastSpeech
		Networking.HttpPost(AI_NPC.Config.APIEndpoint, function(res) MakeCharacterSpeak(character, nil, character, res, identifier, delay, messageType, add_to_history) end, JSONData, "application/json", { ["Authorization"] = "Bearer " .. AI_NPC.Config.APIKey }, savePath)
		return true
	end
	
	return false
end

-- Patch to the Speak function to allow for NPCs to talk through AI without the player explicitly commanding them.
-- Used in SP for NPC speach and Player orders, but not Player speach.
-- Used in MP for NPC speach only.
Hook.Patch('Barotrauma.Character', 'Speak', function(instance, ptable) 
	ptable.PreventExecution = false

	-- Check if configuration setting for this feature is turned on.
	if not AI_NPC.Config.EnableForNPCs or not AI_NPC.Config.EnableChat then
		return
	end
	
	-- Only use this for bots.
	-- This prevents it from running whenever the player assigns an order.
	if not instance.IsBot then
		return
	end

	-- Exclude NPCs not on a player team.
	-- This will exclude outpost chatter.
	if not instance.IsOnPlayerTeam then
		return
	end
	
	-- Skip empty identifiers.
	-- Just let anything with no identifier through, it doesn't work well with AI.
	-- Examples: random NPC conversations and positive/negative response to orders like "Yes, sir!"
	if not ptable['identifier'] or ptable['identifier'] == Identifier.Empty then
		--PrintDebugInfo("Non-AI speach detected: '" .. ptable['message'] .. "', EMPTY IDENTIFIER")
		return
	end
				
	local identifier = ptable['identifier'].ToString()
			
	-- Ignore speech already ran through AI.
	if #identifier >= 3 and identifier:sub(1, 3) == "ai_" then
		PrintDebugInfo("AI Speach detected: " .. identifier)
		return
	elseif CharacterSpeechInfo[instance.Name] and CharacterSpeechInfo[instance.Name].IsSpeaking then
		PrintDebugInfo("Skipping because character is currently saying something with AI.")
		ptable['message'] = ""
		return
	end

	-- Skip identifiers that should be ignored.
	--if IsIgnoredSpeach(identifier) then
	--	return
	--end

	--if string.find(identifier, "CharacterIssues") then
	--	ptable['message'] = ""
	--end

	-- At this point we are at speach that can be processed via AI.
	PrintDebugInfo("Non-AI speach detected: '" .. identifier .. ", " .. ptable['message'])	
				
	-- Determine if something similar has already been said by this NPC.
	-- Once an NPC says something with an identifier, Barotrauma holds it in prevAiChatMessages until the minimum delay has been reached.
	-- So if the identifier itself or the ai_ prefixed identifier are in the prevAiChatMessages queue, this has already been said recently.
	for ident, ftime in pairs(instance.prevAiChatMessages) do
		if (IsCharacterStatusDialogueIdentifier(tostring(ident)) and IsCharacterStatusDialogueIdentifier(identifier)) or string.find(ident.ToString(), identifier) then --ident == ptable['identifier'] then
			PrintDebugInfo("   " .. tostring(ident) .. ", " .. tostring(ftime))--tostring(string.find(ident.ToString(), ptable['identifier'].ToString())))
			PrintDebugInfo("   " .. Timer.GetTime() .. " - " .. ptable['minDurationBetweenSimilar'] .. " = " .. tostring(Timer.GetTime() - ptable['minDurationBetweenSimilar']))
			if (ftime >= Timer.GetTime() - ptable['minDurationBetweenSimilar']) then
				PrintDebugInfo("   Already said this.")
				
				if string.find(identifier, "CharacterIssues") then
					ptable['message'] = ""
				end
				
				return
			else
				PrintDebugInfo("   Can say this.")
			end
		--elseif IsCharacterStatusDialogueIdentifier(ident) and IsCharacterStatusDialogueIdentifier(identifier) then
		--	PrintDebugInfo("   Already said this.")
		--	ptable['message'] = ""
		--	return
		end
	end

	-- Random chance as determined from the ChanceForNPCSpeach configuration setting.
	-- Just to reduce token use, if desired.	
	if math.random(1, 100) >= AI_NPC.Config.ChanceForNPCSpeach then
		PrintDebugInfo("   Skipping because of random chance.")
		if string.find(identifier, "CharacterIssues") then
			ptable['message'] = ""
		end
		return
	end
	--if (not string.find(identifier, "CharacterIssues")) and math.random(1, 100) >= AI_NPC.Config.ChanceForNPCSpeach then
	--	PrintDebugInfo("   Skipping because of random chance.")
		--if string.find(identifier, "CharacterIssues") then
	--		ptable['message'] = ""
		--end
	--	return
	--end
	
	local probability, delay, msg, extrainfo = GetAdjustedNPCSpeach(ptable['message'], identifier, minDurationBetweenSimilar, instance)
	if math.random(1, 100) >= probability then
		PrintDebugInfo("   Skipping because of low probability.")
		if string.find(identifier, "CharacterIssues") then
			ptable['message'] = ""
		end
		return
	end
	
	local addToHistory = true
	if IsCharacterStatusDialogueIdentifier(identifier) then
		addToHistory = false
	end

	-- Send the message to AI for transformation.
	-- If it returns true, it means the NPC chat has been sent to AI. Once the response has been received, that response function will call this Speak hook again
	-- with the identifier starting with "ai_", which will be ignored by this function.
	PrintDebugInfo("   Attempting to run through AI.")
	--  ptable['messageType']
	local spoke = NPCSpeak(instance, ChatMessageType.Radio, msg, "ai_"..identifier, delay, extrainfo, addToHistory)
	
	-- This prevents the original message from being processed by the Barotrauma.Character.Speak() function.
	-- So it won't be spoken or added to the character's prevAiChatMessageQueue.
	ptable['message'] = ""

end, Hook.HookMethodType.Before)

-- The original C# Speak function, for reference in the hook above.
-- This runs after the hook.
--[[
public void Speak(string message, ChatMessageType? messageType = null, float delay = 0.0f, Identifier identifier = default, float minDurationBetweenSimilar = 0.0f)
{
	if (GameMain.NetworkMember != null && GameMain.NetworkMember.IsClient) { return; }
	if (string.IsNullOrEmpty(message)) { return; }

	if (SpeechImpediment >= 100.0f) { return; }

	if (prevAiChatMessages.ContainsKey(identifier) && 
		prevAiChatMessages[identifier] < Timing.TotalTime - minDurationBetweenSimilar) 
	{ 
		prevAiChatMessages.Remove(identifier);                 
	}

	//already sent a similar message a moment ago
	if (identifier != Identifier.Empty && minDurationBetweenSimilar > 0.0f &&
		(aiChatMessageQueue.Any(m => m.Identifier == identifier) || prevAiChatMessages.ContainsKey(identifier)))
	{
		return;
	}
	aiChatMessageQueue.Add(new AIChatMessage(message, messageType, identifier, delay));
}--]]

local function BuildPlayerPrompt(source, character, msg, orderInfo)
	local prompt_header = AI_NPC.Config.PromptInstructions
	prompt_header = prompt_header .. " <CUSTOM_INSTRUCTIONS>\\n\\n"
	prompt_header = prompt_header .. "<LANGUAGE> <DEMOGRAPHICS> <PROFILE> <MISSIONS> <LOCATION> <ORDERS> <SUBMARINE> <INVENTORY> <HEALTH>\\n\\n<SOURCE> <CONVERSATION_HISTORY>"

	local CustomInstructionsPrompt = BuildCustomInstructionsPrompt(character)
	prompt_header = prompt_header:gsub("<CUSTOM_INSTRUCTIONS>", CustomInstructionsPrompt)

	local LanguagePrompt = BuildLanguagePrompt(character)
	prompt_header = prompt_header:gsub("<LANGUAGE>", LanguagePrompt)
	
	local CharacterProfilePrompt = BuildCharacterProfilePrompt(character)
	prompt_header = prompt_header:gsub("<PROFILE>", CharacterProfilePrompt)
	
	local DemographicsPrompt = BuildDemographicsPrompt(character)
	prompt_header = prompt_header:gsub("<DEMOGRAPHICS>", DemographicsPrompt)
	
	local LocationPrompt = BuildLocationPrompt(character)
	prompt_header = prompt_header:gsub("<LOCATION>", LocationPrompt)
	
	local SubmarinePrompt = BuildSubmarineStatePrompt(character)
	prompt_header = prompt_header:gsub("<SUBMARINE>", SubmarinePrompt)
	
	local InventoryPrompt = BuildInventoryPrompt(character)
	prompt_header = prompt_header:gsub("<INVENTORY>", InventoryPrompt)
	
	if #orderInfo > 0 then
		prompt_header = prompt_header:gsub("<ORDERS>", "")
	else
		local OrdersPrompt = BuildOrdersPrompt(character)
		prompt_header = prompt_header:gsub("<ORDERS>", OrdersPrompt)
	end
	
	local MissionsPrompt = BuildMissionsPrompt(source, character)
	prompt_header = prompt_header:gsub("<MISSIONS>", MissionsPrompt)

	local HealthPrompt = BuildHealthPrompt(character)
	prompt_header = prompt_header:gsub("<HEALTH>", HealthPrompt)

	local SourcePrompt = BuildSourcePrompt(source, character)
	prompt_header = prompt_header:gsub("<SOURCE>", SourcePrompt)
	
	local ConversationHistoryPrompt = BuildConversationHistoryPrompt(character)
	prompt_header = prompt_header:gsub("<CONVERSATION_HISTORY>", ConversationHistoryPrompt)
	
	prompt_header = prompt_header .. "\\n\\nThis is the current line you should respond to" .. orderInfo .. ": "
	prompt_header = prompt_header:gsub("%s+", " ")
	
	prompt_header = prompt_header .. source.Name .. ": \"" .. msg .. "\""
	
	return prompt_header
end

function AI_NPC.Globals.ProcessPlayerSpeach(source, character, msg, chatType, orderInfo)
	local prompt = BuildPlayerPrompt(source, character, msg, orderInfo)
	local JSONData = AI_NPC.Globals.GetPromptJSON(prompt)
	
	File.Write(AI_NPC.Path .. "/Last_Prompt.txt", prompt)
	local savePath = AI_NPC.Path .. "/HTTP_Response.txt" -- Save HTTP response to a file for debugging purposes.
	-- Send the prompt to API and process the output in MakeCharacterSpeak.
	CharacterSpeechInfo[character.Name].IsSpeaking = true
	if Utils.ValidateAPISettings() then
		Networking.HttpPost(AI_NPC.Config.APIEndpoint, function(res) MakeCharacterSpeak(source, msg, character, res, "ai_dialogaffirmative", 0.0, chatType, true) end, JSONData, "application/json", { ["Authorization"] = "Bearer " .. AI_NPC.Config.APIKey }, savePath)
	end
end

local function SendPlayerMessage(client, character, msg, chattype, source)
	if not CharacterSpeechInfo[character.Name] then
		CharacterSpeechInfo[character.Name] = {IsSpeaking = false, LastSpeech = 0.0}
	end

	ModerateInput(source, msg, character, prompt_header, chattype);

	-- Make the chat message prettier in the chatbox.
	if SERVER then
		local firstName = string.match(character.Name, "%S+")
		Game.SendMessage(firstName .. ', ' .. msg, chattype, client, source)
		return true
	elseif AI_NPC.Config.UsePrefixInSP then
		local firstName = string.match(character.Name, "%S+")
		local chat_message = ChatMessage.Create(source.Name, firstName .. ', ' .. msg, chattype, client)
		Game.GameSession.CrewManager.AddSinglePlayerChatMessage(chat_message)
		-- Create the speech bubble if that setting is enabled.
		if GameSettings.CurrentConfig.ChatSpeechBubbles then
			source.ShowSpeechBubble(ChatMessage.MessageColor[chattype+1], chat_message.Text)
		end
		return true;
	end
	
	return false
end

if SERVER then
	-- Using this hook in MP now, because chatMessage hook's chattype does not work for Radio messages in MP.
	Hook.Add("modifyChatMessage", "modifyChatMessages", function(chatMessage, wifiComponentSender)
		if not chatMessage then
			return false
		end

		local message = chatMessage.Text
		local source = chatMessage.Sender
		local chattype = chatMessage.Type
		local client = chatMessage.SenderClient
		
		-- Only radio or chat messages, no orders.
		if chattype ~= ChatMessageType.Radio and chattype ~= ChatMessageType.Default then
			return false
		end

		-- Skip empty messages and messages that don't start with !.
		if #message <= 1 or message:sub(1, 1) ~= "!" then
			return false
		end

		-- Separate the input by spaces, to create a table of words.
		local words = {}
		for word in message:gmatch("%S+") do
			table.insert(words, word)
		end
		
		-- Concatenate words starting from the second word (index 2) to form the message being sent.
		-- Remove double quotes and whitespace from edges.
		local msg = Utils.RemoveQuotes(Utils.TrimLeadingWhitespace(table.concat(words, " ", 2)))
		
		-- Strip "!" designator from the first word to get the NPC name.
		local npcName = words[1]:sub(2)

		-- If first word started with !, NPC name isn't empty, and the message has data, then continue.
		if #npcName > 0 and #msg > 0 then
			local targetname = string.lower(npcName)
			local character = Utils.FindBestBotToSpeakTo(source, targetname)

			-- Continue only if a valid character was found.
			if character then
				local ret = SendPlayerMessage(client, character, msg, chattype, source)
				return ret
			end
		end
		
		return false
	end)
else
	-- Used in SP for Player speach, Player orders, and NPC speach.
	-- Used in MP for Player speach and Player orders but not NPC speach.
	Hook.Add("chatMessage", "AI_NPC.PlayerChatMessage", function (message, client, chattype) 
		local source = client and client.Character or Character.Controlled

		-- Only radio or chat messages, no orders.
		if chattype ~= ChatMessageType.Radio and chattype ~= ChatMessageType.Default then
			return false
		end

		-- Skip empty messages and messages that don't start with !.
		if #message <= 1 or (AI_NPC.Config.UsePrefixInSP and message:sub(1, 1) ~= "!") then
			return false
		end
	
		-- Separate the input by spaces, to create a table of words.
		local words = {}
		for word in message:gmatch("%S+") do
			table.insert(words, word)
		end
		
		-- Concatenate words starting from the second word (index 2) to form the message being sent.
		-- Remove double quotes and whitespace from edges.
		local msg = Utils.RemoveQuotes(Utils.TrimLeadingWhitespace(table.concat(words, " ", 2)))
		
		-- Strip "!" designator from the first word to get the NPC name.
		local npcName = ""
		if AI_NPC.Config.UsePrefixInSP then
			npcName = words[1]:sub(2)
		else
			npcName = words[1]
		end

		-- If first word started with !, NPC name isn't empty, and the message has data, then continue.
		if #npcName > 0 and #msg > 0 then
			local targetname = string.lower(npcName)
			local character = Utils.FindBestBotToSpeakTo(source, targetname)

			-- Continue only if a valid character was found.
			if character then
				local ret = SendPlayerMessage(client, character, msg, chattype, source)
				return ret
			end
		end
		
		return false
	end)
end

-- Patch to prevent speech bubbles showing chat commands, only needed in single player.
-- Speech bubble text comes straight from the text box,
-- so it is not blocked by the return value of the chatMessage hook.
if Game.IsSingleplayer then
	Hook.Patch('Barotrauma.Character', 'ShowSpeechBubble', function(instance, ptable)
		if AI_NPC.Config.UsePrefixInSP and ptable['text']:sub(1,1) == '!' then 
			ptable.PreventExecution = true
		else
			ptable.PreventExecution = false
		end
	end, Hook.HookMethodType.Before)
end

--Game.GameSession.CrewManager.CreateRandomConversation()

--[[if CSActive then 
	LuaUserData.RegisterType("System.ValueTuple`2[Barotrauma.Character, System.String]")
end]]--

-- Block random conversations.
-- TODO: Eventually patch this and use it to generate conversations.
Hook.Patch('Barotrauma.CrewManager', 'CreateRandomConversation', function(instance, ptable) 
	ptable.PreventExecution = true
	return
	--[[if CSActive then 
		--print(instance.pendingConversationLines)
		print("Creating Convo")
		for key in instance.pendingConversationLines do
			print(key.Item1.Name)
			if key.Item1.IsOnPlayerTeam then
				print(key.Item1.Name, " skipping conversation.")
				ptable.PreventExecution = true
				return
			end
		end
		
		ptable.PreventExecution = false
	else
		ptable.PreventExecution = true
		return
	end]]--
end, Hook.HookMethodType.Before)

--[[local basicTimer = 0

Hook.Add("think", "timer", function()
    if basicTimer > Timer.GetTime() then return end -- skip code below

    basicTimer = Timer.GetTime() + 5 -- timer runs every 5 seconds
end)]]--

--[[if CSActive then 
	--TODO: Experimental.
	Hook.Patch('Barotrauma.CrewManager', 'CreateRandomConversation', function(instance, ptable) 
		ptable.PreventExecution = false
		
		--print("CreateRandomConversation")
		--print(instance.pendingConversationLines)
		--for key in instance.pendingConversationLines do
		--	key.Item2 = ""
		--	print(key.Item1.Name)
		--	print(key.Item2)
		--end
		
		local testchar = FindValidCharacter("orval", true)
		if testchar then
			--print(testchar.Name)
			ConversationInterface.AddToConversation(testchar, "test")
		end
		--local str = ConversationInterface.GetPendingConversation()
		--ConversationInterface.ClearCurrentConversations()
		
		--print(str)
	end, Hook.HookMethodType.After)
end]]--