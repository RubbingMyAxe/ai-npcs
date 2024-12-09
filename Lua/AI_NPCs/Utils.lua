--[[
	Utils - Short utility functions.
--]]

-- Lets this run if on the server-side, if it's multiplayer, doesn't let it run on the client, and if it's singleplayer, lets it run on the client.
if CLIENT and Game.IsMultiplayer then return end

local HumanAIController = LuaUserData.CreateStatic("Barotrauma.HumanAIController", false)

-- Color the error string to make it more obvious on the console.
function AI_NPC.Utils.MakeErrorText(str)
	return "‖color:gui.red‖" .. str .. "‖end‖"
end

function AI_NPC.Utils.EscapeQuotes(str)
	return str:gsub("\"", "\\\"")
end

function AI_NPC.Utils.RemoveArticles(str)
    -- Pattern to match "a", "an", or "the" (case insensitive) followed by a space, at any position
    str = str:gsub("(%s)[Aa][Nn]?%s", "%1")  -- Matches " a " or " an " with trailing space
    str = str:gsub("(%s)[Tt][Hh][Ee]%s", "%1")  -- Matches " the " with trailing space
    return str
end

-- Removes double quotes which break HTTP Request.
function AI_NPC.Utils.RemoveQuotes(str)
	str = str:gsub("\"", "")
	str = str:gsub("[“”]", "")
	return str
end

function AI_NPC.Utils.CapitalizeFirstLetter(str)
  return str:gsub("^%l", string.upper)
end

-- Copies a table.
function AI_NPC.Utils.ShallowCopyTable(originalTable)
	local copiedTable = {}
	for key, value in pairs(originalTable) do
		copiedTable[key] = value
	end
	return copiedTable
end

-- Returns true if the table contains the string.
function AI_NPC.Utils.FindStringInTable(tbl, str)
	for _, element in ipairs(tbl) do
		if (element == str) then
			return true
		end
	end
	return false
end

function AI_NPC.Utils.TrimLeadingWhitespace(str)
	return str:match("^%s*(.-)$")
end

function AI_NPC.Utils.TrimSurroundingWhitespace(str)
  return string.match(str, "^%s*(.-)%s*$")
end

-- Count keys in a dictionary.
function AI_NPC.Utils.CountKeys(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Function to check if a variable matches a specific flag.
function AI_NPC.Utils.HasFlag(variable, flagValue)
    return (variable % (flagValue * 2)) >= flagValue
end

-- Function to print a table recursively.
function AI_NPC.Utils.PrintTable(tab, indent)
    indent = indent or 0
    for key, value in pairs(tab) do
        if type(value) == "table" then
            print(string.rep("  ", indent) .. key .. ":")
            PrintTable(value, indent + 1)
        else
            print(string.rep("  ", indent) .. key .. ": " .. tostring(value))
        end
    end
end

-- More verbose console output in debug mode.
function PrintDebugInfo(msg)
	if AI_NPC.Config.DebugMode then
		print(msg)
	end
end

-- Returns a character whose name contains targetname.
-- If canspeak is true, it only looks for characters who are able to speak.
function AI_NPC.Utils.FindValidCharacter(targetname, canspeak)
	for _, entity in pairs(Character.CharacterList) do
		local nameMatch = string.find(string.lower(entity.Name), targetname)
		-- Only look for human bots with a partial name match.
		if nameMatch and entity.IsHuman and entity.IsBot then
			-- Only look at characters that are alive and can speak, if canspeak is true.
			if not canspeak or (not entity.IsDead and not entity.IsUnconscious and entity.CanSpeak) then
				return entity
			end
		end
	end
	return nil
end

function AI_NPC.Utils.FindBestBotToSpeakTo(source, target)
	local best_character = nil
	local best_character_priority = 0

	for _, entity in pairs(Character.CharacterList) do
		local nameMatch = string.find(string.lower(entity.Name), target)
		
		-- Find a matching human bot that's alive and can speak and can hear the message.
		if nameMatch and entity.IsHuman and entity.IsBot and not entity.IsDead 
		and not entity.IsUnconscious and entity.CanSpeak and entity.CanHearCharacter(source) then
			local current_priority = 0

			local sameRoom = entity.IsInSameRoomAs(source)
			local sameCrew = HumanAIController.IsFriendly(source, entity, true) -- Checks only same team.
			local friendly = HumanAIController.IsFriendly(source, entity, false)
			
			local firstName, lastName = string.match(string.lower(entity.Name), "(%S+)%s*(%S*)")
			if firstName == "" then firstName = nil end
			if lastName == "" then lastName = nil end
			
			-- Crewmembers with exact matching first or last name have top priority.
			if sameCrew and ((firstName and firstName == target) or (lastName and lastName == target)) then
				current_priority = 6
			-- Followed by friendly NPCs with exact matching first or last name.
			elseif friendly and ((firstName and firstName == target) or (lastName and lastName == target)) then
				current_priority = 5
			-- Followed by crewmembers in the same room.
			elseif sameCrew and sameRoom then
				current_priority = 4
			-- Followed by other crew members.
			elseif sameCrew then
				current_priority = 3
			-- Followed by friendly NPCs.
			elseif friendly then
				current_priority = 2
			-- And lastly, anyone with a matching name.
			else
				current_priority = 1
			end

			-- Update best character.
			if current_priority > best_character_priority then
				best_character = entity
				best_character_priority = current_priority
			end
		end
	end
	
	return best_character
end

function AI_NPC.Utils.ExtractTextBetweenSecondQuotes(message)
    local quoteCount = 0
    local startPos, endPos
    for pos = 1, #message do
        if message:sub(pos, pos) == "\"" then
            quoteCount = quoteCount + 1
            if quoteCount == 3 then
                startPos = pos + 1
            elseif quoteCount == 4 then
                endPos = pos - 1
                break
            end
        end
    end

    if quoteCount == 4 then
        return message:sub(startPos, endPos)
    else
        return message
    end
end

-- Splits a block of text into more manageable size chunks. Attempts to split on periods, question marks, or exclamation points.
function AI_NPC.Utils.SplitBySentences(text, max_length)
    local chunks = {}
    local start = 1
    local text_length = #text

    while start <= text_length do
        if text_length - start + 1 <= max_length then
            -- If remaining text is less than or equal to max_length, take it whole.
            chunks[#chunks + 1] = text:sub(start, text_length)
            break
        end

        -- Define the initial search range.
        local end_pos = math.min(start + max_length - 1, text_length)
        
        -- Look for the last period within this range.
        local last_period = text:sub(start, end_pos):match(".*()[%.?!]")
        if last_period then
            last_period = start + last_period - 1 -- Adjust relative index to absolute.
        else
            -- If no period found, extend search to the next period beyond max_length.
            local extended_end = text:sub(end_pos + 1):match("()[%.?!]") 
            if extended_end then
                last_period = end_pos + extended_end -- Adjust index as it's from end_pos.
            else
                last_period = text_length -- Take the rest if no more periods or question marks found.
            end
        end

        -- Add the chunk to the list.
        chunks[#chunks + 1] = text:sub(start, last_period)
        start = last_period + 2 -- Skip the period and any space after it.
    end

    return chunks
end

function AI_NPC.Utils.GetRole(character)
	local role = ""

	if character.HumanPrefab and character.HumanPrefab.NpcSetIdentifier then
		local identifier = character.HumanPrefab.NpcSetIdentifier

		if identifier == "outpostnpcs1" then
			-- Wanted to use character.Info.HumanPrefabIds to determine what kind of outpost NPC,
			-- but that is not possible in Lua so I have to go by their clothing...
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
	-- Get their role from their job, if it's not a hidden NPC job like 'structuredefender'.
	elseif character.Info.Job and not character.Info.Job.Prefab.HiddenJob then
		local role = character.JobIdentifier.Value
	
		-- Change these to be more AI friendly.
		if identifier == "engineer" then
			role = "electrician"
		elseif identifier == "securityofficer" then
			role = "security officer"
		elseif identifier == "medicaldoctor" then
			role = "doctor"
		end
	-- If it's a bandit.
	elseif character.Info and character.Info.Prefab.Identifier == "bandit" then
		role = "bandit"
	end
	
	return role
end

-- Parse the HTTP reponse to get the data from the API.
function AI_NPC.Utils.GetAPIResponse(str)
	local success, data = pcall(json.parse, str)
	if not success then
		print(AI_NPC.Utils.MakeErrorText("Error parsing JSON: " .. data))
		print(AI_NPC.Utils.MakeErrorText("Reason: " .. str))
		return ""
	end
	
	if data["error"] then
		print(AI_NPC.Utils.MakeErrorText("Error received from API: " .. data["error"]["message"]))
		if data["error"]["code"] and data["error"]["code"] == "insufficient_quota" then
			print(AI_NPC.Utils.MakeErrorText("This means you have to add credits to your API account. It is not a bug with the AI NPCs mod."))
		end
		return ""
	end

	local content = data["choices"][1]["message"]["content"]

	if data["usage"] and data["usage"]["prompt_tokens"] and data["usage"]["completion_tokens"] then
		local prompt_tokens = data["usage"]["prompt_tokens"]
		local completion_tokens = data["usage"]["completion_tokens"]
		AI_NPC.Globals.tokens_used_this_session = AI_NPC.Globals.tokens_used_this_session + prompt_tokens + completion_tokens
		
		-- Print token usage information to console.
		print("Prompt Tokens: " .. prompt_tokens)
		print("Result Tokens: " .. completion_tokens)
		print("Total: " .. prompt_tokens + completion_tokens)
		print("Total for Session: " .. AI_NPC.Globals.tokens_used_this_session)
	end

	return content
end

function AI_NPC.Utils.ValidateAPISettings()
    -- Check if the session token cap has been exceeded.
    if AI_NPC.Config.SessionTokenCap ~= -1 and AI_NPC.Globals.tokens_used_this_session >= AI_NPC.Config.SessionTokenCap then
        print(AI_NPC.Utils.MakeErrorText("Token limit for this session has been exceeded."))
		print(AI_NPC.Utils.MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig SessionTokenCap [value]\" command to increase it!"))
		if Game.IsSingleplayer then
			print(AI_NPC.Utils.MakeErrorText("Or reset the current usage for this session by reloading Lua with the \"cl_reloadlua\" command."))
		else
			print(AI_NPC.Utils.MakeErrorText("Or reset the current usage for this session by reloading Lua with the \"reloadlua\" command."))
		end
        return false
    end

    -- Check if API endpoint is not set.
    if string.len(AI_NPC.Config.APIEndpoint) == 0 then
        print(AI_NPC.Utils.MakeErrorText("No API Endpoint has been set, call to API will not be executed."))
		print(AI_NPC.Utils.MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig APIEndpoint [url]\" command to set it!"))
        return false
    end

    -- Check if API key is not set.
    if string.len(AI_NPC.Config.APIKey) == 0 then
        print(AI_NPC.Utils.MakeErrorText("No API Key has been set, call to API will not be executed."))
		print(AI_NPC.Utils.MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig APIKey [key]\" command to set it!"))
        return false
    end

    -- Check if model is not set.
    if string.len(AI_NPC.Config.Model) == 0 then
        print(AI_NPC.Utils.MakeErrorText("No Model has been set, call to API will not be executed."))
		print(AI_NPC.Utils.MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig Model [name]\" command to set it!"))
        return false
    end

    -- Check if API calls are disabled.
    if not AI_NPC.Config.EnableAPI then
        print(AI_NPC.Utils.MakeErrorText("API calls are currently disabled."))
		print(AI_NPC.Utils.MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig EnableAPI true\" command to enable them!"))
        return false
    end

    return true
end
