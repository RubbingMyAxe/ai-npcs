--[[
	Character Profiles
--]]

-- Lets this run if on the server-side, if it's multiplayer, doesn't let it run on the client, and if it's singleplayer, lets it run on the client.
if CLIENT and Game.IsMultiplayer then return end

-- Register HashSet<Identifier> so that it can be used when removing unlocked talents.
--LuaUserData.RegisterType("System.Collections.Generic.HashSet`1[[Barotrauma.Identifier,BarotraumaCore]]")

local Utils = AI_NPC.Utils
local SaveData = AI_NPC.SaveData

SaveData.SavedCharactersFile = "" 

--TODO: Possibly add map seed for non-crew and non-special NPCs.
if AI_NPC.Config.UseCharacterProfiles then 

	-- Load the pre-generated NPC profiles.
	local Profiles = json.parse(File.Read(AI_NPC.Data .. "/CharacterProfiles.json"))
	AI_NPC.UniqueProfiles = json.parse(File.Read(AI_NPC.Data .. "/UniqueCharacterProfiles.json"))

	-- Gets a random selection of styles from the list, up to the limit.
	local function GetRandomStyle(list, minimum, limit)
		if #list == 0 or limit == 0 then
			return ""
		end
		
		-- Make a shallow copy of the list to preserve the original list.
		local listCopy = Utils.ShallowCopyTable(list)

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
		
		 -- 15% chance to use "any" profiles.
		local UseAnyProfiles = (math.random(1, 100) <= 15)
		
		-- Get all of the profiles that match the role/personality.
		local matchingProfiles = {}
		for _, data in ipairs(Profiles) do
			if data.Personality == personality and data.Role == role then
				table.insert(matchingProfiles, data)
			-- Add applicable "any" profiles.
			elseif UseAnyProfiles and (data.Personality == personality or data.Personality == "any") and (data.Role == role or data.Role == "any") then
				table.insert(matchingProfiles, data)
			end
		end
		
		-- Broken English needs a style to work properly.
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
			AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())] =
			{
				["Description"] = "",
				["Style"] = ""
				--["MapSeed"] = ""
			}
			
			-- Write this profile into the SavedCharactersFile to preserve it.
			File.Write(SaveData.SavedCharactersFile, json.serialize(AI_NPC.CharacterProfiles))
			return
		end
		
		local role = AI_NPC.Utils.GetRole(character)

		-- TODO: Experimental code for saving character with map seed.
		--[[local map_seed = ""
		-- If it's a random non-special NPC, save the map seed.
		if CLIENT or Game.ServerSettings.GameModeIdentifier == "multiplayercampaign" then
			if not character.IsOnPlayerTeam and not UniqueProfiles[character.Name] then
				map_seed = Game.GameSession.GameMode.Map.Seed
			end
		end]]--

		local personality = string.lower(character.Info.PersonalityTrait.DisplayName.Value)
		local profile, style = GetRandomProfile(personality, string.lower(role), character.IsOnPlayerTeam, guaranteed)

		AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())] =
		{
			["Description"] = profile,
			["Style"] = style
			--["MapSeed"] = map_seed
		}
		
		-- Give talent.
		--character.GiveTalent("mytalent", true)
		--character.Info.UnlockedTalents.Remove("mytalent")
		--if SERVER then
		--	Networking.CreateEntityEvent(character, UpdateTalentsEventData);
		--end
		
		-- Write this profile into the SavedCharactersFile to preserve it.
		File.Write(SaveData.SavedCharactersFile, json.serialize(AI_NPC.CharacterProfiles))
	end
end