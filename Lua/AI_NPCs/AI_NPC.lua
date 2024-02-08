--[[
	AI NPC
--]]

-- Lets this run if on the server-side, if it's multiplayer, doesn't let it run on the client, and if it's singleplayer, lets it run on the client.
if CLIENT and Game.IsMultiplayer then return end

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

--TODO: Put globals in AI_NPC namespace.
CurrentSaveDirectory = ""

-- Table to store data about when each character last spoke through AI.
local CharacterSpeechInfo = {}
LastSpeech = 0.0

-- Variable to keep track of token usage.
-- Resets when LUA is reloaded.
local tokens_used_this_session = 0

-- TODO: Fix errors with this save/load code with sub editor. Not very important.

-- Load data and create folders in case Lua was reloaded mid-session.
if Game.GameSession then

	if CLIENT or Game.ServerSettings.GameModeIdentifier == "multiplayercampaign" then
		PrintDebugInfo("Reloaded campaign mid-session: " .. Game.GameSession.GameMode.Map.Seed)
		CurrentSaveDirectory = AI_NPC.SaveData .. "/" .. Game.GameSession.GameMode.Map.Seed
	else
		PrintDebugInfo("Reloaded other multiplayer match mid-session: " .. Game.ServerSettings.GameModeIdentifier.ToString() .. ", " .. Game.GameSession.Level.Seed)
		CurrentSaveDirectory = AI_NPC.SaveData .. "/" .. Game.GameSession.Level.Seed
	end
	
	SavedCharactersFile = CurrentSaveDirectory .. "/SavedCharacters.json"
	if File.DirectoryExists(CurrentSaveDirectory) then
		-- If there is an existing profiles file, load it.
		if AI_NPC.Config.UseCharacterProfiles and File.Exists(SavedCharactersFile) then
			CharacterProfiles = json.parse(File.Read(SavedCharactersFile))
		end
	else
		File.CreateDirectory(CurrentSaveDirectory)
	end
	
	LoadMissions(CurrentSaveDirectory .. "/Missions.txt", true)
end

-- Loading data if it's campaign and previous data exists.
-- Creating folders at the start if previous data does not exist.
Hook.Add("roundStart", "LoadNPCData", function()

	if CLIENT or Game.ServerSettings.GameModeIdentifier == "multiplayercampaign" then
		PrintDebugInfo("Loaded campaign: " .. Game.GameSession.GameMode.Map.Seed)
		CurrentSaveDirectory = AI_NPC.SaveData .. "/" .. Game.GameSession.GameMode.Map.Seed
	else
		PrintDebugInfo("Loaded other multiplayer match: " .. Game.ServerSettings.GameModeIdentifier.ToString() .. ", " .. Game.GameSession.Level.Seed)
		CurrentSaveDirectory = AI_NPC.SaveData .. "/" .. Game.GameSession.Level.Seed
	end
	
	SavedCharactersFile = CurrentSaveDirectory .. "/SavedCharacters.json"
	
	if File.DirectoryExists(CurrentSaveDirectory) then
		-- If there is an existing profiles file, load it.
		if AI_NPC.Config.UseCharacterProfiles and File.Exists(SavedCharactersFile) then
			CharacterProfiles = json.parse(File.Read(SavedCharactersFile))
		end
	else
		File.CreateDirectory(CurrentSaveDirectory)
	end	
	
	LoadMissions(CurrentSaveDirectory .. "/Missions.txt", false)
end)

-- Cleaning up on round end.
-- This function only runs server-side.
Hook.Add("roundEnd", "DeleteNPCData", function()

	if CLIENT or Game.ServerSettings.GameModeIdentifier == "multiplayercampaign" then
		PrintDebugInfo("Ended campaign: " .. Game.GameSession.GameMode.Map.Seed)
		
		-- Delete missions file.
		if File.DirectoryExists(CurrentSaveDirectory) and File.Exists(MissionsFile) then
			File.Delete(MissionsFile)
		end
	else
		-- If was a temporary game mode, delete entire directory.
		PrintDebugInfo("Ended other multiplayer match: " .. Game.ServerSettings.GameModeIdentifier.ToString() .. ", " .. Game.GameSession.Level.Seed)
		if File.DirectoryExists(CurrentSaveDirectory) then
			File.DeleteDirectory(CurrentSaveDirectory)
		end
	end
end)

-- Runs player input through OpenAI's moderation API first to check that it will not be flagged for violating OpenAI's usage policies.
-- Only used if endpoint is set to OpenAI and the Moderation configuration setting is enabled.
local function ModerateInput(data, source, msg, character)

	local input = {input = msg}
	local JSONinput = json.serialize(input)

	Networking.HttpPost("https://api.openai.com/v1/moderations", 
	function(response)
		
		local success, info = pcall(json.parse, response)
		if not success then
			print(MakeErrorText("Error parsing moderation JSON: " .. info))
			print(MakeErrorText("Reason: " .. response))
			return
		end
		
		if info["error"] then
			print(MakeErrorText("Error received from moderation API: " .. info["error"]["message"]))
			return
		end

		if not info["results"][1]["flagged"] then
			local savePath = AI_NPC.Path .. "/HTTP_Response.txt" -- Save HTTP response to a file for debugging purposes.
			-- Send the prompt to API and process the output in MakeCharacterSpeak.
			CharacterSpeechInfo[character.Name].IsSpeaking = true
			Networking.HttpPost(AI_NPC.Config.APIEndpoint, function(res) MakeCharacterSpeak(source, msg, character, res, nil, 0.0) end, data, "application/json", { ["Authorization"] = "Bearer " .. AI_NPC.Config.APIKey }, savePath)
		else
			local flags = {}
			for key, val in pairs(info["results"][1].categories) do
				if val then
					table.insert(flags, key)
				end
			end
		
			print(MakeErrorText(character.Name .. "'s message disallowed by OpenAI." ))
			print(MakeErrorText("Message: " .. msg))
			print(MakeErrorText("Reasons: " .. table.concat(flags,", ")))
		end
	end, JSONinput, "application/json", { ["Authorization"] = "Bearer " .. AI_NPC.Config.APIKey }, nil)
end

-- Prevents players from changing their character name to something that would be flagged by OpenAI.
Hook.Add("tryChangeClientName", "PreventDisallowedNameChanges", function(client, newName, newJob, newTeam)
	-- Only do moderation for OpenAI API calls.
	if AI_NPC.Config.Moderation and ValidateAPISettings() and string.find(AI_NPC.Config.APIEndpoint, "api.openai.com") then
	
		local oldName = client.Name
		local input = {input = newName}
		local JSONinput = json.serialize(input)
		
		Networking.HttpPost("https://api.openai.com/v1/moderations", 
		function(response)
		
			local success, info = pcall(json.parse, response)
			if not success then
				print(MakeErrorText("Error parsing moderation JSON: " .. info))
				print(MakeErrorText("Reason: " .. response))
				return
			end
			
			if info["error"] then
				print(MakeErrorText("Error received from moderation API: " .. info["error"]["message"]))
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
	
	message = ExtractTextBetweenSecondQuotes(message)
	
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
	message = TrimLeadingWhitespace(RemoveQuotes(message))
	
	return message
end

--TODO: Add more ignored identifiers.
--TODO: Maybe combine with GetAdjustedNPCSpeach() and add a probability return value?
local function IsIgnoredSpeach(identifier)
	-- Used for this script's AI messages. Ignore these.
	if string.find(identifier, "dialogaffirmative") then
		return true
	end

	-- Used when an NPC can't get somewhere.
	-- Example: "Can't get there!"
	if string.find(identifier, "dialogcannotreachplace") then
		return true
	end

	if string.find(identifier, "getdivinggear") then
		return true
	end

	-- Spammed when NPC is firing a turret.
	-- Example: "Firing!"
	if string.find(identifier, "fireturret") then
		return true
	end

	return false
end

-- Some vanilla speech is very vague and does not generate good results with AI.
-- For example: "Target down!" and "I think I got it!"
local function GetAdjustedNPCSpeach(msg, identifier, character)

	-- killedtarget + ID
	-- Used when the NPC kills a target.
	-- Example: "Target down!"
	if string.find(identifier, "killedtarget") then
		-- Remove the killedtarget from the string to get the ID.
		local targetID = identifier:gsub("killedtarget", "")
		-- Conver the ID to a number, then use it to find the character.
		targetID = tonumber(targetID)
		if targetID then
			local target = Entity.FindEntityByID(targetID)
			if target then
				if target.IsHuman then
					return "I just killed " .. target.Name, ""
				else
					local message = ""
					local extrainfo = ""
					
					local bestiaryinfo = Bestiary[string.lower(target.SpeciesName.Value)]
					if bestiaryinfo then
						-- TODO: Experimental, if it is a creature let's include some information about that creature in the prompt.
						message = "I just killed a " .. bestiaryinfo.Name .. "!"
						extrainfo = extrainfo .. "A" .. bestiaryinfo.Name .. " is a " .. bestiaryinfo.Size .. ", " .. bestiaryinfo.Description .. "."
					else
						message = "I just killed a " .. target.SpeciesName.Value .. "!"
					end

					return message, extrainfo
				end
			end
		end
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
		return "I have spotted an ice spire, I will shoot it if we get any closer!", ""
	end
	
	-- leaksfixed doesn't need any changes.
	-- Example: "All leaks repaired in [roomname]!"
	if string.find(identifier, "leakfixed") then
		return msg, ""
	end
	
	return msg, ""
end

-- Tell the character what language it speaks.
local function BuildLanguagePrompt(character)
	local LanguagePrompt = ""
	
	if AI_NPC.Config.Language ~= "English" then
		LanguagePrompt = "You speak " .. AI_NPC.Config.Language .. "."
	end

	return LanguagePrompt
end

-- Tell the character about itself.
local function BuildDemographicsPrompt(character)
	local DemographicsPrompt = "Embody the character of <NPC_NAME>, a<PERSONALITY> <GENDER> <SKILL> <ROLE> <SUBMARINE> in a region called <REGION>.<BROKEN_ENGLISH>"

	-- Tell the character its name.
	DemographicsPrompt = DemographicsPrompt:gsub("<NPC_NAME>", character.Name)
	
	-- Tell the character what gender it is.
	local gender = character.Info.IsMale and "male" or "female"
	DemographicsPrompt = DemographicsPrompt:gsub("<GENDER>", gender)

	local role = ""

	if character.HumanPrefab and character.HumanPrefab.NpcSetIdentifier then
		local identifier = character.HumanPrefab.NpcSetIdentifier

		if identifier == "outpostnpcs1" then
		
			-- Wanted to use character.Info.HumanPrefabIds to determine what kind of outpost NPC,
			-- but that is not possible in Lua so I have to use another less clean method...
			local clothing = character.Inventory.GetItemInLimbSlot(InvSlotType.InnerClothes)
			local helmet = character.Inventory.GetItemInLimbSlot(InvSlotType.Head)
			
			local commoner_attire = { "commonerclothes1", "commonerclothes2", "commonerclothes3", "commonerclothes4", "commonerclothes5" }
			local miner_attire = { "minerclothes" }
			local clown_attire = { "clowncostume" }
			local clown_mask = { "clownmask" }
			local researcher_attire = { "researcherclothes" }
			local husk_attire = { "cultistrobes", "zealotrobes" }

			if clothing then
				if clothing.HasIdentifierOrTags(commoner_attire) then
					role = "civilian"
				elseif clothing.HasIdentifierOrTags(miner_attire) then
					role = "miner"
				elseif clothing.HasIdentifierOrTags(clown_attire) or (helmet and helmet.HasIdentifierOrTags(clown_mask)) then
					role = "clown"
				elseif clothing.HasIdentifierOrTags(researcher_attire) then
					role = "researcher"
				elseif clothing.HasIdentifierOrTags(husk_attire) then
					role = "husk cultist"
				end
			end
		end
	end

	if string.len(role) == 0 then
		-- Tell the character the skill level of their primary job.
		-- Assistants might not have primary jobs.
		if character.Info.Job.PrimarySkill then
			local skillLevel = character.GetSkillLevel(character.Info.Job.PrimarySkill.Identifier)

			local skillLevels = {"frighteningly incompetent", "mediocre", "unremarkable", "expert", "legendary"}
			local skill = skillLevels[math.floor(skillLevel / 25) + 1] or "novice"
			
			DemographicsPrompt = DemographicsPrompt:gsub("<SKILL>", skill)
		else
			DemographicsPrompt = DemographicsPrompt:gsub("<SKILL>", "")
		end

		-- Tell the character their role.
		if character.IsMedic then
			role = "medic"
		elseif character.IsSecurity then
			role = "security officer"
		elseif character.IsMechanic then
			role = "mechanic"
		elseif character.IsEngineer then
			role = "electrician"
		elseif character.IsCaptain then
			role = "captain"
		else
			role = "assistant"
		end
	else
		DemographicsPrompt = DemographicsPrompt:gsub("<SKILL>", "")
	end

	DemographicsPrompt = DemographicsPrompt:gsub("<ROLE>", role)
	
	-- Tell the character the name of their submarine.
	SubmarinePrompt = ""	
	character_submarine = nil
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
				local Profile = UniqueProfiles[character.Name] or CharacterProfiles[character.Name]

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
	
		if UniqueProfiles[character.Name] then
			-- If it's a unique character's name, use their profile.
			CharacterProfile = ShallowCopyTable(UniqueProfiles[character.Name])
			CharacterProfile.Style = table.concat(CharacterProfile.Style, ", ")
		elseif CharacterProfiles[character.Name] then
			-- If we already have a profile, use that.
			CharacterProfile = CharacterProfiles[character.Name]
		else
			-- Haven't attempted to get a profile yet, try to get one.
			AssignProfile(character, false)
			CharacterProfile = CharacterProfiles[character.Name]
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
	character_submarine = nil
	for submarine in Submarine.Loaded do
		if submarine.TeamID == character.TeamID then
			character_submarine = submarine
		end
	end
	
	if character_submarine and character_submarine == character.Submarine then
		-- If the character is on their own submarine, just get the room information.
		if character.CurrentHull then
			-- TODO: Currently all rooms on outposts are named "Upper aft side", so just ignore these until this bug is fixed.
			-- Rooms on outposts with items like reactors and airlocks still work.
			if character.Submarine.Info.IsOutpost and character.CurrentHull.DisplayName.Value ~= "Upper aft side" then
				LocationPrompt = "You are currently in the " .. string.lower(character.CurrentHull.DisplayName.Value) .. "."
			end
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
			-- TODO: Currently all rooms on outposts are named "Upper aft side", so just ignore these until this bug is fixed.
			-- Rooms on outposts with items like reactors and airlocks still work.
			if character.Submarine.Info.IsOutpost and character.CurrentHull.DisplayName.Value ~= "Upper aft side" then
				room = " in the " .. string.lower(character.CurrentHull.DisplayName.Value)
			end
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
		if not FindStringInTable(important_inventory, string.lower(item.Name)) and item.HasTag("weapon") or item.HasTag("tool") and not item.HasTag("mobilecontainer") then
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
	
	-- TODO: Maybe tell what pressure depth their suit protects from?
	-- <StatusEffect type="OnWearing" target="Character" LowPassMultiplier="0.2" HideFace="true" ObstructVision="true" PressureProtection="10000.0"
	
	-- Tell the character if they're wearing a diving suit or body armor.
	local OuterClothing = character.Inventory.GetItemInLimbSlot(InvSlotType.OuterClothes)
	if OuterClothing then
		if string.lower(OuterClothing.Name) == "exosuit" then
			ClothingPrompt = ClothingPrompt .. "You are wearing a large, heavy, well-armored, nuclear powered, mechanical exosuit."
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

	local TurretTypes = {
		["chaingun"] = "fast-firing chain gun",
		["coilgun"] = "standard coil gun",
		["doublecoilgun"] = "burst-fire double coil gun",
		["flakcannon"] = "flak cannon",
		["pulselaser"] = "pulse laser",
		["railgun"] = "rail gun" }

	CurrentActionsPrompt = ""
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

	return OrdersPrompt .. " " .. CurrentActionsPrompt
end

-- Tell the character the current missions.
local function BuildMissionsPrompt(source, character)

	local DestinationPrompt = ""
	if Game.GameSession.Level.EndLocation then
		-- Get the destination name.
		DestinationPrompt = "Your crew is enroute to " .. Game.GameSession.Level.EndLocation.DisplayName.Value .. "."
	end

	local MissionsPrompt = ""
	-- If the character is not on a player team, it won't have a mission.
	if (character.IsOnPlayerTeam) then
		-- Only use this prompt if missions are found.
		if string.len(CurrentMissions) > 0 then
			MissionsPrompt = "Your crew's current missions are: " .. CurrentMissions .. "."
		else
			MissionsPrompt = "Your crew is just passing through."
		end
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

-- Tell the character about its health status.
local function BuildHealthPrompt(character)

	-- Tell the character its vitality, if injured.
	local healthLevels = {"You are seriously injured, close to death.", "You are heavily injured.", "You are very injured.", "You are slightly injured.", ""}
	HealthLevelPrompt = healthLevels[math.floor(character.HealthPercentage / 25) + 1] or ""

	-- Tell the character if it has psychosis.
	local PsychosisPrompt = ""
	local affliction = character.CharacterHealth.GetAffliction("psychosis")
    if affliction ~= nil then
		if affliction.Strength > 10 and affliction.Strength <= 25 then
			PsychosisPrompt = "You are hallucinating slightly."
		elseif affliction.Strength > 25 and affliction.Strength <= 50 then
			PsychosisPrompt = "You are moderately hallucinating."
		elseif affliction.Strength > 50 and affliction.Strength <= 75 then
			PsychosisPrompt = "You are severely hallucinating."
		elseif affliction.Strength > 75 then
			PsychosisPrompt = "You are severely hallucinating, but aren't aware of it. You don't know what's real or illusion. You could be seeing fires, floods, and enemies. You could be hearing strange sounds or the reactor meltdown alarms."
		end
    end

	-- List any afflictions.
	local serious_afflictions = {}
	for affliction in character.CharacterHealth.GetAllAfflictions(function(a) end) do
		local afflictiondata = ""
		
		-- Exclude psychosis since we handle it elsewhere.
		if affliction.Prefab.Name.Value ~= "Psychosis" then
			-- Some afflictions are always present even if their strength is at 0, filter these out.
			if affliction.Strength > 0 then
				afflictiondata = affliction.GetStrengthText().Value .. " " .. affliction.Prefab.Name.Value
				if affliction.Source and affliction.Source ~= character then
					afflictiondata = afflictiondata .. " caused by " .. affliction.Source.Name
				end
				-- Only add this affliction if it doesn't already exist in the list.
				if not FindStringInTable(serious_afflictions, afflictiondata) then
					-- Limit to 4 afflictions because this list can get long.
					if #serious_afflictions < 4 then
						table.insert(serious_afflictions, afflictiondata)
					end
				end
			end
		end
	end

	AfflictionPrompt = ""
	-- Only list afflictions if they were found.
	if #serious_afflictions > 0 then
		 AfflictionPrompt = "This is a list of your current injuries: " .. table.concat(serious_afflictions, ", ") .. "."
	end

	return HealthLevelPrompt .. " " .. PsychosisPrompt .. " " .. AfflictionPrompt
end

-- Tell the character who is speaking to it.
local function BuildSourcePrompt(source, character)
	local SourcePrompt = "Speaking to you is <CREW> <NAME>, a<PERSONALITY> <GENDER> <SKILL> <ROLE>."

	-- Tell the character if the source is part of their crew.
	if source.TeamID == character.TeamID then
		SourcePrompt = SourcePrompt:gsub("<CREW>", "a crewmate named")
	else
		local disposition = ""
		-- TODO: Is this even useful? Can't hear enemy NPCs on the radio anyway?
		-- Tell the character if the source is an enemy.
		--if not character.IsFriendly(source) then
		--	disposition = "hostile and dangerous "
		--end
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
	
	-- Tell the character the skill level of the source at their primary job.
	-- Assistants might not have primary jobs.
	if source.Info.Job.PrimarySkill then
		local skillLevel = source.GetSkillLevel(source.Info.Job.PrimarySkill.Identifier)

		local skillLevels = {"frighteningly incompetent", "mediocre", "unremarkable", "expert", "legendary"}
		local skill = skillLevels[math.floor(skillLevel / 25) + 1] or "novice"
				
		SourcePrompt = SourcePrompt:gsub("<SKILL>", skill)
	else
		SourcePrompt = SourcePrompt:gsub("<SKILL>", "")
	end

	-- Tell the character what role the source is.
	local role = ""
	if source.IsMedic then
		role = "medic"
	elseif source.IsSecurity then
		role = "security officer"
	elseif source.IsMechanic then
		role = "mechanic"
	elseif source.IsEngineer then
		role = "electrician"
	elseif source.IsCaptain then
		role = "captain"
	else
		role = "assistant"
	end
	
	SourcePrompt = SourcePrompt:gsub("<ROLE>", role)
	
	return SourcePrompt
end

-- Tell the character about their submarine's state.
local function BuildSubmarineStatePrompt(character)

	-- Ignore this for NPCs that aren't on a player's crew.
	if not character.IsOnPlayerTeam then
		return ""
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
	character_submarine = nil
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
			if not FindStringInTable(damaged_hulls, gap.FlowTargetHull.DisplayName.Value) and not (#damaged_hulls > 5) then
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
		
		--for firesource in hull.FireSources do
		--	--TODO: Not sure what to do here.
		--	print(firesource.Size.X)
		--end
		
		if not hull.IsWetRoom then
			TotalNonWetRooms = TotalNonWetRooms + 1
			if hull.WaterPercentage > 25 and not FindStringInTable(flooded_rooms, hull.DisplayName.Value) then
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
			local electric = HasFlag(repairable.Prefab.Category, ElectricCategory)
			local machine = HasFlag(repairable.Prefab.Category, MachineCategory)

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
	OuterHullStatus = ""
	if #damaged_hulls > 0 then
		if isMechanic then
			OuterHullStatus = OuterHullStatus .. "The outer hull is breached in the following areas: " .. table.concat(damaged_hulls, ", ") .. "."
		else
			OuterHullStatus = OuterHullStatus .. "The outer hull is breached."
		end
	end
	
	-- Everyone knows if the sub is flooded, engineers know specific details.
	FloodedStatus = ""
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
	ElectricStatus = ""
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
	MechanicalStatus = ""
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
	
	-- TODO: Say if there is a fire.
	
	return OuterHullStatus .. " " .. FloodedStatus .. " " .. ElectricStatus .. " " .. MechanicalStatus
end

-- Parse the HTTP reponse to get the data from the API.
function GetAPIResponse(str)
	local success, data = pcall(json.parse, str)
	if not success then
		print(MakeErrorText("Error parsing JSON: " .. data))
		print(MakeErrorText("Reason: " .. str))
		return ""
	end
	
	if data["error"] then
		print(MakeErrorText("Error received from API: " .. data["error"]["message"]))
		if data["error"]["code"] and data["error"]["code"] == "insufficient_quota" then
			print(MakeErrorText("This means you have to add credits to your API account. It is not a bug with the AI NPCs mod."))
		end
		return ""
	end

	local content = data["choices"][1]["message"]["content"]

	if data["usage"] and data["usage"]["prompt_tokens"] and data["usage"]["completion_tokens"] then
		local prompt_tokens = data["usage"]["prompt_tokens"]
		local completion_tokens = data["usage"]["completion_tokens"]
		tokens_used_this_session = tokens_used_this_session + prompt_tokens + completion_tokens
		
		-- Print token usage information to console.
		print("Prompt Tokens: " .. prompt_tokens)
		print("Result Tokens: " .. completion_tokens)
		print("Total: " .. prompt_tokens + completion_tokens)
		print("Total for Session: " .. tokens_used_this_session)
	end

	return content
end

-- Make the character speak the data from API.
function MakeCharacterSpeak(source, msg, character, str, identifier, delay)	
	local speach = GetAPIResponse(str)
	
	if identifier == nil then
		identifier = Identifier.Empty
	end
	
	if string.len(speach) > 0 then
	
		if source != character and str then
			-- Add the original message from the player to the NPC's conversation log.
			AddToConversationHistory(source, character, msg)
		end
	
		speach = SanitizeNPCSpeach(character, speach)
	
		-- Add this line from the NPC to the player to the NPC's conversation history.
		AddToConversationHistory(nil, character, speach)

		if source.Inventory.GetItemInLimbSlot(InvSlotType.Headset) and character.Inventory.GetItemInLimbSlot(InvSlotType.Headset) then
			-- If they both have radios, use the radio.
			character.Speak(speach, ChatMessageType.Radio, 0.0, identifier, delay)
		else
			-- Otherwise use local chat.
			character.Speak(speach, ChatMessageType.Default, 0.0, identifier, delay)
		end
	end
	
	CharacterSpeechInfo[character.Name].IsSpeaking = false
end

-- Used to refine canned speach from NPCs with AI.
local function NPCSpeak(character, messageType, message, identifier, delay, extrainfo)
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

	-- Build the prompt header.
	prompt_header = "Let's roleplay in the universe of Barotrauma. "
	prompt_header = prompt_header .. "Responses should be conversational and from a first person perspective, without prefixes, emotes, actions, or narration of internal dialogue. "
	prompt_header = prompt_header .. "When referencing the character traits or prompt, use unique words and phrases to convey the ideas without copying them exactly. "
	prompt_header = prompt_header .. "Dialogue should be fresh, avoiding repetition. Responses should be consistent with what your character knows and believes.\\n\\n"
	--[[---local prompt_header = "Let's roleplay in the universe of Barotrauma. "
	---prompt_header = prompt_header .. "You speak in a conversational manner, always from a first person perspective. "
	--prompt_header = prompt_header .. "You don't describe things or actions, just chat as your character. "
	--prompt_header = prompt_header .. "Do not prefix your response with your name, your response should only be what your character would speak. "
	---prompt_header = prompt_header .. "Keep your responses short, up to three sentences. "
	local prompt_header = "Let's roleplay in the universe of Barotrauma. "
	prompt_header = prompt_header .. "You speak in a conversational manner, always from a first person perspective. "
	--prompt_header = prompt_header .. "Remember, no repeating past dialogue or introducing unknown facts or actions. Everything you say should be consistent with what your character knows and believes. "
	--prompt_header = prompt_header .. "You don't describe things or actions, just chat as your character. "
	prompt_header = prompt_header .. "Limit your response to 200 characters. Do not say anything you've said before. "]]--
	prompt_header = prompt_header .. "<LANGUAGE> <DEMOGRAPHICS> <PROFILE> <LOCATION> <MISSIONS> <ORDERS> <SUBMARINE><INVENTORY> <HEALTH> <EXTRA_INFO> <CONVERSATION_HISTORY> "
	
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

	-- This hasn't been very useful so far.
	--local NearbyCrewPrompt = BuildNearbyCrewPrompt(character)
	--prompt_header = prompt_header:gsub("<NEARBY_CREW>", NearbyCrewPrompt)

	local HealthPrompt = BuildHealthPrompt(character)
	prompt_header = prompt_header:gsub("<HEALTH>", HealthPrompt)

	local ExtraInfoPrompt = extrainfo
	prompt_header = prompt_header:gsub("<EXTRA_INFO>", ExtraInfoPrompt)

	local ConversationHistoryPrompt = BuildConversationHistoryPrompt(character)
	prompt_header = prompt_header:gsub("<CONVERSATION_HISTORY>", ConversationHistoryPrompt)

	prompt_header = prompt_header .. "\\n\\nThis what you are trying to say next, but you need to transform it into the style of your character using only known information: "

	-- Save some tokens by replacing consecutive spaces with a single space.
	prompt_header = prompt_header:gsub("%s+", " ")

	-- Write the full prompt to a file for debugging purposes.
	File.Write(AI_NPC.Path .. "/Last_Prompt.txt", prompt_header .. "\\\"" .. message .. "\\\"")
	
	local data = {
		model = AI_NPC.Config.Model,
		messages = {{
			role = "user",
			content = prompt_header .. "\\\"" .. message .. "\\\""
		}},
		temperature = 0.7,
		--frequency_penalty = 0.4
	}

	local JSONData = json.serialize(data)

	-- Concatenate the header prompt with the player message and insert it into the JSON data of the HTTP request.
	PrintDebugInfo(data["messages"][1]["content"])

	local savePath = AI_NPC.Path .. "/HTTP_Response.txt" -- Save HTTP response to a file for debugging purposes.

	if ValidateAPISettings() then
		-- Send the prompt to API and process the output in MakeCharacterSpeak.
		-- Comment this line out to test prompt formation without sending to API.
		CharacterSpeechInfo[character.Name].IsSpeaking = true
		Networking.HttpPost(AI_NPC.Config.APIEndpoint, function(res) MakeCharacterSpeak(character, nil, character, res, identifier, delay) end, JSONData, "application/json", { ["Authorization"] = "Bearer " .. AI_NPC.Config.APIKey }, savePath)
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
	if not AI_NPC.Config.EnableForNPCs then
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
	if #identifier >= 3 and string.sub(identifier, 1, 3) == "ai_" then
		PrintDebugInfo("AI Speach detected: " .. identifier)
		return
	end

	-- Skip identifiers that should be ignored.
	if IsIgnoredSpeach(identifier) then
		return
	end

	-- At this point we are at speach that can be processed via AI.
	PrintDebugInfo("Non-AI speach detected: '" .. ptable['message'] .. ", " .. identifier)	
				
	-- Determine if something similar has already been said by this NPC.
	-- Once an NPC says something with an identifier, Barotrauma holds it in prevAiChatMessages until the minimum delay has been reached.
	-- So if the identifier itself or the ai_ prefixed identifier are in the prevAiChatMessages queue, this has already been said recently.
	for ident, ftime in pairs(instance.prevAiChatMessages) do
		--PrintDebugInfo("   " .. ptable['identifier'].ToString() .. ", " .. tostring(ident) .. " = " .. tostring(string.find(ident.ToString(), ptable['identifier'].ToString())))
		if string.find(ident.ToString(), identifier) then --ident == ptable['identifier'] then
			PrintDebugInfo("   Already said this.")
			return
		end
	end

	-- Random chance as determined from the ChanceForNPCSpeach configuration setting.
	-- Just to reduce token use, if desired.
	if math.random(1, 100) > AI_NPC.Config.ChanceForNPCSpeach then
		return
	end
	
	PrintDebugInfo("   Attempting to run through AI.")
	local msg, extrainfo = GetAdjustedNPCSpeach(ptable['message'], identifier, instance)
	-- Send the message to AI for transformation.
	-- If it returns true, it means the NPC chat has been sent to AI. Once the response has been received, that response function will call this Speak hook again
	-- with the identifier starting with "ai_", which will be ignored by this function.
	-- TODO: Set delay to 60 seconds, might change later to be variable depending on the type of message.
	local spoke = NPCSpeak(instance, ptable['messageType'], msg, "ai_"..identifier, 60.0, extrainfo) --ptable['minDurationBetweenSimilar'])
	if spoke then
		CharacterSpeechInfo[instance.Name].LastSpeech = Timer.GetTime()
		LastSpeech = CharacterSpeechInfo[instance.Name].LastSpeech
	end
	
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

-- Save data to an NPC's conversation history file.
-- source = Who spoke to the NPC to trigger the reply, if any.
-- target = The NPC saying the reply.
-- message = The message text.
function AddToConversationHistory(source, target, message)
	local filename = string.format("%s/%s.txt", CurrentSaveDirectory, target.Name)
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
	local filename = string.format("%s/%s.txt", CurrentSaveDirectory, target.Name)
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
			ConversationHistoryPrompt = ConversationHistoryPrompt .. "\\n" .. EscapeQuotes(item) .. " "
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

function ValidateAPISettings()
    -- Check if the session token cap has been exceeded.
    if AI_NPC.Config.SessionTokenCap ~= -1 and tokens_used_this_session >= AI_NPC.Config.SessionTokenCap then
        print(MakeErrorText("Token limit for this session has been exceeded."))
		print(MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig SessionTokenCap [value]\" command to increase it!"))
		if Game.IsSingleplayer then
			print(MakeErrorText("Or reset the current usage for this session by reloading Lua with the \"cl_reloadlua\" command."))
		else
			print(MakeErrorText("Or reset the current usage for this session by reloading Lua with the \"reloadlua\" command."))
		end
        return false
    end

    -- Check if API key is not set.
    if string.len(AI_NPC.Config.APIEndpoint) == 0 then
        print(MakeErrorText("No API Endpoint has been set, call to API will not be executed."))
		print(MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig APIEndpoint [url]\" command to set it!"))
        return false
    end

    -- Check if API key is not set.
    if string.len(AI_NPC.Config.APIKey) == 0 then
        print(MakeErrorText("No API Key has been set, call to API will not be executed."))
		print(MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig APIKey [key]\" command to set it!"))
        return false
    end

    -- Check if model is not set.
    if string.len(AI_NPC.Config.Model) == 0 then
        print(MakeErrorText("No Model has been set, call to API will not be executed."))
		print(MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig Model [name]\" command to set it!"))
        return false
    end

    -- Check if API calls are disabled.
    if not AI_NPC.Config.EnableAPI then
        print(MakeErrorText("API calls are currently disabled."))
		print(MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig EnableAPI true\" command to enable them!"))
        return false
    end

    return true
end

local function BuildPlayerPromptAndSend(client, character, msg, chattype, source)
	if CharacterSpeechInfo[character.Name] == nil then
		CharacterSpeechInfo[character.Name] = {IsSpeaking = false, LastSpeech = 0.0}
	end

	--TODO: Experiment with different variations of this.
	-- Build the prompt header.
	prompt_header = "Let's roleplay in the universe of Barotrauma. "
	prompt_header = prompt_header .. "Responses should be conversational and from a first person perspective, without prefixes, emotes, actions, or narration of internal dialogue. "
	prompt_header = prompt_header .. "When referencing the character traits or prompt, use unique words and phrases to convey the ideas without copying them exactly. "
	prompt_header = prompt_header .. "Dialogue should be fresh, avoiding repetition. Responses should be consistent with what your character knows and believes.\\n\\n"
	--[[local prompt_header = "Let's roleplay in the universe of Barotrauma. "
	--prompt_header = prompt_header .. "You speak in a conversational manner, always from a first person perspective. "
	prompt_header = prompt_header .. "You don't describe things or actions, just chat as your character from a first person perspective. "
	prompt_header = prompt_header .. "Do not prefix your response with your name, your response should only be what your character would speak. "
	prompt_header = prompt_header .. "Be creative in your choice of words, do not use the same phrasing provided to you in the prompt. "
	--prompt_header = prompt_header .. "Limit your response to 200 characters. Do not say anything you've said before, and do not add any unknown information. "
	prompt_header = prompt_header .. "Remember, no repeating past dialogue or introducing unknown facts or actions. Everything you say should be consistent with what your character knows and believes. "]]--
	prompt_header = prompt_header .. "<LANGUAGE> <DEMOGRAPHICS> <PROFILE> <LOCATION> <MISSIONS> <ORDERS> <SUBMARINE><INVENTORY> <HEALTH> <SOURCE> <CONVERSATION_HISTORY>"

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

	-- This hasn't been very useful so far.
	--local NearbyCrewPrompt = BuildNearbyCrewPrompt(character)
	--prompt_header = prompt_header:gsub("<NEARBY_CREW>", NearbyCrewPrompt)

	local HealthPrompt = BuildHealthPrompt(character)
	prompt_header = prompt_header:gsub("<HEALTH>", HealthPrompt)

	local SourcePrompt = BuildSourcePrompt(source, character)
	prompt_header = prompt_header:gsub("<SOURCE>", SourcePrompt)
	
	-- Determine if the character is close enough to hear the source.
	-- For now, if the character isn't close enough to hear even the garbled message we aren't going to send to API,
	-- otherwise we send the message as if the NPC heard it ungarbled.
	local CanHear = false
	local GarbledMsg = ChatMessage.ApplyDistanceEffect(msg, chattype, source, character)
	if GarbledMsg ~= nil and #GarbledMsg > 0 then
		CanHear = true
		-- TODO: Experimental, passing garbled messages doesn't work well.
		--[[if GarbledMsg ~= msg then
			if chattype ~= ChatMessageType.Radio then
				GarbledPrompt = ", it is coming in over the radio broken up"
			else
				GarbledPrompt = ","
			end
		end]]--
	end
	
	local JSONData = nil
	if AI_NPC.Config.UseMultipleMessages then
		-- Split the data into multiple messages.
		prompt_header = prompt_header:gsub("<CONVERSATION_HISTORY>", "")
		prompt_header = prompt_header:gsub("%s+", " ")
		
		local prompt_messages = BuildJSONMessages(prompt_header, character, source, msg)
		
		local data = {
			model = AI_NPC.Config.Model,
			messages = prompt_messages,
			temperature = 0.7,
			--frequency_penalty = 0.4
		}
		
		--PrintTable(data)
		
		JSONData = json.serialize(data)
	else
		-- Put everything into a single user message.
		local ConversationHistoryPrompt = BuildConversationHistoryPrompt(character)
		prompt_header = prompt_header:gsub("<CONVERSATION_HISTORY>", ConversationHistoryPrompt)
		
		prompt_header = prompt_header .. "\\n\\nThis is the current line you should respond to: "
		prompt_header = prompt_header:gsub("%s+", " ")
		
		File.Write(AI_NPC.Path .. "/Last_Prompt.txt", prompt_header .. source.Name .. ": \"" .. msg .. "\"")
		
		local data = {
			model = AI_NPC.Config.Model,
			messages = {{
				role = "user",
				content = prompt_header .. source.Name .. ": \"" .. msg .. "\""
			}},
			temperature = 0.7,
			--frequency_penalty = 0.4
		}
		
		PrintDebugInfo(data["messages"][1]["content"])
		
		JSONData = json.serialize(data)
	end
	
	local savePath = AI_NPC.Path .. "/HTTP_Response.txt" -- Save HTTP response to a file for debugging purposes.

	if ValidateAPISettings() and CanHear then
		-- Only do moderation for OpenAI API calls if the Moderation setting is active.
		if AI_NPC.Config.Moderation and string.find(AI_NPC.Config.APIEndpoint, "api.openai.com")  then
			ModerateInput(JSONData, source, msg, character);
		else
			-- Send the prompt to API and process the output in MakeCharacterSpeak.
			CharacterSpeechInfo[character.Name].IsSpeaking = true
			Networking.HttpPost(AI_NPC.Config.APIEndpoint, function(res) MakeCharacterSpeak(source, msg, character, res, "dialogaffirmative", 0.0) end, JSONData, "application/json", { ["Authorization"] = "Bearer " .. AI_NPC.Config.APIKey }, savePath)
		end
	end
	
	-- Make the chat message prettier in the chatbox.
	if SERVER then
		local firstName = string.match(character.Name, "%S+")
		Game.SendMessage(firstName .. ', ' .. msg, chattype, client, source)
		return true
	else
		local firstName = string.match(character.Name, "%S+")
		local chat_message = ChatMessage.Create(source.Name, firstName .. ', ' .. msg, chattype, client);
		Game.GameSession.CrewManager.AddSinglePlayerChatMessage(chat_message);
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
		if #message <= 1 or string.sub(message, 1, 1) ~= "!" then
			return false
		end

		-- Separate the input by spaces, to create a table of words.
		local words = {}
		for word in message:gmatch("%S+") do
			table.insert(words, word)
		end
		
		-- Concatenate words starting from the second word (index 2) to form the message being sent.
		-- Remove double quotes and whitespace from edges.
		local msg = RemoveQuotes(TrimLeadingWhitespace(table.concat(words, " ", 2)))
		
		-- Strip "!" designator from the first word to get the NPC name.
		local npcName = words[1]:sub(2)

		-- If first word started with !, NPC name isn't empty, and the message has data, then continue.
		if #npcName > 0 and #msg > 0 then
			local targetname = string.lower(npcName)
			local character = FindValidCharacter(targetname, true)

			-- Continue only if a valid character was found.
			if character then
				local ret = BuildPlayerPromptAndSend(client, character, msg, chattype, source)
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
		if #message <= 1 or string.sub(message, 1, 1) ~= "!" then
			return false
		end
	
		-- Separate the input by spaces, to create a table of words.
		local words = {}
		for word in message:gmatch("%S+") do
			table.insert(words, word)
		end
		
		-- Concatenate words starting from the second word (index 2) to form the message being sent.
		-- Remove double quotes and whitespace from edges.
		local msg = RemoveQuotes(TrimLeadingWhitespace(table.concat(words, " ", 2)))
		
		-- Strip "!" designator from the first word to get the NPC name.
		local npcName = words[1]:sub(2)

		-- If first word started with !, NPC name isn't empty, and the message has data, then continue.
		if #npcName > 0 and #msg > 0 then
			local targetname = string.lower(npcName)
			local character = FindValidCharacter(targetname, true)

			-- Continue only if a valid character was found.
			if character then
				local ret = BuildPlayerPromptAndSend(client, character, msg, chattype, source)
				return ret
			end
		end
		
		return false
	end)
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