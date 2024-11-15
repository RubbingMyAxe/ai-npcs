--[[
	Utils - Short utility functions.
--]]

-- Lets this run if on the server-side, if it's multiplayer, doesn't let it run on the client, and if it's singleplayer, lets it run on the client.
if CLIENT and Game.IsMultiplayer then return end

-- Color the error string to make it more obvious on the console.
function MakeErrorText(str)
	return "‖color:gui.red‖" .. str .. "‖end‖"
end

function EscapeQuotes(str)
	return str:gsub("\"", "\\\"")
end

-- Removes double quotes which break HTTP Request.
function RemoveQuotes(str)
	return str:gsub("\"", "")
end

function CapitalizeFirstLetter(str)
  return str:gsub("^%l", string.upper)
end

-- Copies a table.
function ShallowCopyTable(originalTable)
	local copiedTable = {}
	for key, value in pairs(originalTable) do
		copiedTable[key] = value
	end
	return copiedTable
end

-- Returns true if the table contains the string.
function FindStringInTable(tbl, str)
	for _, element in ipairs(tbl) do
		if (element == str) then
			return true
		end
	end
	return false
end

function TrimLeadingWhitespace(str)
	return str:match("^%s*(.-)$")
end

function TrimSurroundingWhitespace(str)
  return string.match(str, "^%s*(.-)%s*$")
end

-- Count keys in a dictionary.
function CountKeys(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Function to check if a variable matches a specific flag.
function HasFlag(variable, flagValue)
    return (variable % (flagValue * 2)) >= flagValue
end

-- Function to print a table recursively.
function PrintTable(tab, indent)
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
-- TODO: Add range parameter if default chat?
-- TODO: Proritize player crew?
function FindValidCharacter(targetname, canspeak)
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

function ExtractTextBetweenSecondQuotes(message)
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

-- Splits a block of text into more manageable size chunks. Attempts to split on periods or question marks.
function SplitBySentences(text, max_length)
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
        local last_period = text:sub(start, end_pos):match(".*()[%.?]")
        if last_period then
            last_period = start + last_period - 1 -- Adjust relative index to absolute.
        else
            -- If no period found, extend search to the next period beyond max_length.
            local extended_end = text:sub(end_pos + 1):match("()[%.?]") 
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

    -- Check if API endpoint is not set.
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
