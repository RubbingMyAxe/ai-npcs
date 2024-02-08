--[[
	Character Profiles
--]]

-- Lets this run if on the server-side, if it's multiplayer, doesn't let it run on the client, and if it's singleplayer, lets it run on the client.
if CLIENT and Game.IsMultiplayer then return end

SavedCharactersFile = ""
CharacterProfiles = {}

if AI_NPC.Config.UseCharacterProfiles then 

	-- Load the pre-generated NPC profiles.
	local Profiles = json.parse(File.Read(AI_NPC.Data .. "/CharacterProfiles.json"))
	UniqueProfiles = json.parse(File.Read(AI_NPC.Data .. "/UniqueCharacterProfiles.json"))

	-- Gets a random selection of styles from the list, up to the limit.
	local function GetRandomStyle(list, minimum, limit)
		if #list == 0 or limit == 0 then
			return ""
		end
		
		-- Make a shallow copy of the list to preserve the original list.
		local listCopy = ShallowCopyTable(list)

		-- Randomize the copy of the list.
		for i = #listCopy, 2, -1 do
			local j = math.random(1, i)
			listCopy[i], listCopy[j] = listCopy[j], listCopy[i]
		end

		-- Randomly decide the number of items to pick, between minimum and limit.
		local numItemsToPick = math.random(minimum, limit)

		-- Take up to numItemsToPick from the shuffled list.
		local selectedStrings = {}
		for i = 1, numItemsToPick do
			table.insert(selectedStrings, listCopy[i])
		end
		
		return table.concat(selectedStrings, ", ")
	end

	-- Gets a random profile.
	-- If guaranteed is true, a profile will be returned if one is available.
	function GetRandomProfile(personality, role, crew, guaranteed)
		
		local rand = math.random(1, 100)
		
		-- Get all of the profiles that match the role/personality.
		local matchingProfiles = {}
		for _, data in ipairs(Profiles) do
			if data.Personality == personality and data.Role == role then
				table.insert(matchingProfiles, data)
			end
		end
		
		-- Broken English really needs a style to work properly.
		local minimum_styles = 0
		if personality == "broken english" then
			minimum_styles = 1
		end
		
		-- If there is only one matching profile, lower the chance of getting it.
		if #matchingProfiles == 1 then
			if not guaranteed and crew and rand <= 70 then
				-- 70% chance to not get a profile.
				return "", ""
			elseif not guaranteed and not crew and rand <= 80 then
				-- 80% chance to not get a profile.
				return "", ""
			else		
				return matchingProfiles[1].Description, GetRandomStyle(matchingProfiles[1].Style, minimum_styles, 3)
			end
		-- If there are multiple matching profiles, increase the chance of getting one.
		elseif #matchingProfiles > 1 then
			if not guaranteed and crew and rand <= 40 then
				-- 40% chance to not get a profile.
				return "", ""
			elseif not guaranteed and not crew and rand <= 60 then
				-- 60% chance to not get a profile.
				return "", ""
			else
				local selected_profile = math.random(1, #matchingProfiles)
				print(matchingProfiles[selected_profile].Style)
				return matchingProfiles[selected_profile].Description, GetRandomStyle(matchingProfiles[selected_profile].Style, minimum_styles, 3)
			end
		else
			-- No matching profile found.
			return "", ""
		end
	end
	
	-- Gets the information required to select a profile from a character, calls GetRandomProfile() to get the profile, and then
	-- writes it to the SavedCharactersFile.
	function AssignProfile(character, guaranteed)
		if not character.Info.PersonalityTrait or not character.Info.PersonalityTrait.DisplayName then
			
			CharacterProfiles[character.Name] =
			{
				["Description"] = "",
				["Style"] = "" 
			}
			
			-- Write this profile into the SavedCharactersFile to preserve it.
			File.Write(SavedCharactersFile, json.serialize(CharacterProfiles))
			return
		end
		
		local role = ""

		-- If it's an outpost NPC, get their role from their attire.
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
		
		-- If it's not an outpost NPC, use their role.
		if string.len(role) == 0 then
			if character.IsMedic then
				role = "medic"
			elseif character.IsSecurity then
				role = "security"
			elseif character.IsMechanic then
				role = "mechanic"
			elseif character.IsEngineer then
				role = "electrician"
			elseif character.IsCaptain then
				role = "captain"
			else
				role = "assistant"
			end
		end

		local personality = string.lower(character.Info.PersonalityTrait.DisplayName.Value)
		local profile, style = GetRandomProfile(personality, string.lower(role), character.IsOnPlayerTeam, guaranteed)

		CharacterProfiles[character.Name] =
		{
			["Description"] = profile,
			["Style"] = style 
		}
		
		-- Write this profile into the SavedCharactersFile to preserve it.
		File.Write(SavedCharactersFile, json.serialize(CharacterProfiles))
	end
end