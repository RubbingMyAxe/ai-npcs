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