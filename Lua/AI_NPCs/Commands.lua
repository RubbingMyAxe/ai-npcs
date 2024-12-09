--[[
	Commands
--]]

local SaveData = AI_NPC.SaveData
local Utils = AI_NPC.Utils

-- Get list of configuration file values for the parameter list.
local function configParameter()
	local configNames = {}
	for key, _ in pairs(AI_NPC.Config) do
		table.insert(configNames, key)
	end
	return {configNames}
end

-- Get list of character names for the parameter list.
local function characterParameter()
	local characterNames = {}
	for c in Character.CharacterList do
		if c.IsHuman and c.IsBot then
			table.insert(characterNames, c.Name)
		end
	end
	return {characterNames}
end

if Game.IsSingleplayer then
	-- Adds the commands to the list of valid commands.
	-- Sets the function that is called client-side when the command is used. Also ads the command to help list and enables autofilling parameters.
	Game.AddCommand(AI_NPC.CmdPrefix .. "setconfig", AI_NPC.CmdPrefix .. "setconfig [setting] [value]: Sets a value in the AI NPCs configuration file.", function(args) setConfig(args) end, configParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "getconfig", AI_NPC.CmdPrefix .. "getconfig [setting]: Gets a value from the AI NPCs configuration file.", function(args) getConfig(args) end, configParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "listconfig", AI_NPC.CmdPrefix .. "listconfig: Lists all of the values in the AI NPCs configuration file.", function(args) listConfig(args) end)
	Game.AddCommand(AI_NPC.CmdPrefix .. "setprofile", AI_NPC.CmdPrefix .. "setprofile [character] [profile]: Sets the profile of a character.", function(args) setProfile(args) end, characterParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "getprofile", AI_NPC.CmdPrefix .. "getprofile [character]: Gets the profile of a character.", function(args) getProfile(args) end, characterParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "clearprofile", AI_NPC.CmdPrefix .. "clearprofile [character]: Clears the profile and style of a character.", function(args) clearProfile(args) end, characterParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "setstyle", AI_NPC.CmdPrefix .. "setstyle [character] [style]: Sets the style of a character.", function(args) setStyle(args) end, characterParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "giverandomprofile", AI_NPC.CmdPrefix .. "giverandomprofile [character]: Gives the character a random profile.", function(args) giveRandomProfile(args) end, characterParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "clearconversationhistory", AI_NPC.CmdPrefix .. "clearconversationhistory [character]: Clears the conversation history of a character.", function(args) clearConversationHistory(args) end, characterParameter)
else
	-- Adds the commands to the list of valid commands.
	-- Functions will be called server-side, so do not set them here. This is only used for adding the command to help list and autofilling parameters.
	Game.AddCommand(AI_NPC.CmdPrefix .. "setconfig", AI_NPC.CmdPrefix .. "setconfig [setting]: Sets a value in the AI NPCs configuration file.", nil, configParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "getconfig", AI_NPC.CmdPrefix .. "getconfig [setting]: Gets a value from the AI NPCs configuration file.", nil, configParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "listconfig", AI_NPC.CmdPrefix .. "listconfig: Lists all of the values in the AI NPCs configuration file.", nil)
	Game.AddCommand(AI_NPC.CmdPrefix .. "setprofile", AI_NPC.CmdPrefix .. "setprofile [character] [profile]: Sets the profile of a character.", nil, characterParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "getprofile", AI_NPC.CmdPrefix .. "getprofile [character]: Gets the profile of a character.", nil, characterParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "clearprofile", AI_NPC.CmdPrefix .. "clearprofile [character]: Clears the profile of a character.", nil, characterParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "setstyle", AI_NPC.CmdPrefix .. "setstyle [character] [style]: Sets the style of a character.", nil, characterParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "giverandomprofile", AI_NPC.CmdPrefix .. "giverandomprofile [character]: Gives the character a random profile.", nil, characterParameter)
	Game.AddCommand(AI_NPC.CmdPrefix .. "clearconversationhistory", AI_NPC.CmdPrefix .. "clearconversationhistory [character]: Clears the conversation history of a character.", nil, characterParameter)
end

-- Sets the functions that get called for the commands when the mod is the running on the server.
-- Has extra permission checks for the client.
if SERVER then

	Game.AssignOnClientRequestExecute(AI_NPC.CmdPrefix .. "setconfig", function(client, mousePosition, args)
		local HasManageSettingsPermission = client.HasPermission(ClientPermissions.ManageSettings)
		
		if HasManageSettingsPermission then
			setConfig(args)
		else
			print(Utils.MakeErrorText("Client does not have permission to manage settings."))
		end
	end)

	Game.AssignOnClientRequestExecute(AI_NPC.CmdPrefix .. "getconfig", function(client, mousePosition, args)
		local HasManageSettingsPermission = client.HasPermission(ClientPermissions.ManageSettings)
		
		if HasManageSettingsPermission then
			getConfig(args)
		else
			print(Utils.MakeErrorText("Client does not have permission to manage settings."))
		end
	end)

	Game.AssignOnClientRequestExecute(AI_NPC.CmdPrefix .. "listconfig", function(client, mousePosition, args)
		local HasManageSettingsPermission = client.HasPermission(ClientPermissions.ManageSettings)
		
		if HasManageSettingsPermission then
			listConfig()
		else
			print(Utils.MakeErrorText("Client does not have permission to manage settings."))
		end
	end)
	
	Game.AssignOnClientRequestExecute(AI_NPC.CmdPrefix .. "setprofile", function(client, mousePosition, args)
		local HasManageSettingsPermission = client.HasPermission(ClientPermissions.ManageSettings)
		
		if HasManageSettingsPermission then
			setProfile(args)
		else
			print(Utils.MakeErrorText("Client does not have permission to manage settings."))
		end
	end)

	Game.AssignOnClientRequestExecute(AI_NPC.CmdPrefix .. "getprofile", function(client, mousePosition, args)
		local HasManageSettingsPermission = client.HasPermission(ClientPermissions.ManageSettings)
		
		if HasManageSettingsPermission then
			getProfile(args)
		else
			print(Utils.MakeErrorText("Client does not have permission to manage settings."))
		end
	end)

	Game.AssignOnClientRequestExecute(AI_NPC.CmdPrefix .. "setstyle", function(client, mousePosition, args)
		local HasManageSettingsPermission = client.HasPermission(ClientPermissions.ManageSettings)
		
		if HasManageSettingsPermission then
			setStyle(args)
		else
			print(Utils.MakeErrorText("Client does not have permission to manage settings."))
		end
	end)
	
	Game.AssignOnClientRequestExecute(AI_NPC.CmdPrefix .. "giverandomprofile", function(client, mousePosition, args)
		local HasManageSettingsPermission = client.HasPermission(ClientPermissions.ManageSettings)
		
		if HasManageSettingsPermission then
			giveRandomProfile(args)
		else
			print(Utils.MakeErrorText("Client does not have permission to manage settings."))
		end
	end)

	Game.AssignOnClientRequestExecute(AI_NPC.CmdPrefix .. "clearprofile", function(client, mousePosition, args)
		local HasManageSettingsPermission = client.HasPermission(ClientPermissions.ManageSettings)
		
		if HasManageSettingsPermission then
			clearProfile(args)
		else
			print(Utils.MakeErrorText("Client does not have permission to manage settings."))
		end
	end)

	Game.AssignOnClientRequestExecute(AI_NPC.CmdPrefix .. "clearconversationhistory", function(client, mousePosition, args)
		local HasManageSettingsPermission = client.HasPermission(ClientPermissions.ManageSettings)
		
		if HasManageSettingsPermission then
			clearConversationHistory(args)
		else
			print(Utils.MakeErrorText("Client does not have permission to manage settings."))
		end
	end)
end

-- Only run server-side in Multiplayer and in Singleplayer.
if (Game.IsMultiplayer and SERVER) or Game.IsSingleplayer then

	-- The local functions that actually perform the command action.
	local function ModifyConfigSetting(setting, newvalue)
		if AI_NPC.Config[setting] ~= nil then
			if not newvalue then
				newvalue = ""
			end
		
			if AI_NPC.ConfigType[setting] == "number" then
				local IsNumber = tonumber(newvalue)
				if IsNumber then
					AI_NPC.Config[setting] = IsNumber
				else
					print(Utils.MakeErrorText(setting .. " requires a numerical value."))
					return
				end
			elseif AI_NPC.ConfigType[setting] == "boolean" then
				if newvalue:lower() == "true" then
					AI_NPC.Config[setting] = true
				elseif newvalue:lower() == "false" then
					AI_NPC.Config[setting] = false
				else
					print(Utils.MakeErrorText(setting .. " requires a true or false value."))
					return
				end
			else
				-- Otherwise treat it as a string.
				AI_NPC.Config[setting] = newvalue
			end

			File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
			print(setting .. " configuration setting has been set to: " .. tostring(AI_NPC.Config[setting]))
			
			if setting == "APIKey" then
				if SERVER then
					print("If the mod was not loaded because the APIKey was not set, use the 'reloadlua' command.")
				elseif Game.IsSingleplayer then
					print("If the mod was not loaded because the APIKey was not set, use the 'cl_reloadlua' command.")
				end
			end
		else
			print(Utils.MakeErrorText(setting .. " not found in configuration file."))
		end
	end

	local function GetConfigSetting(setting)
		if AI_NPC.Config[setting] then
			print(setting .. ": " .. tostring(AI_NPC.Config[setting]))
		else
			print(Utils.MakeErrorText(setting .. " not found in configuration file."))
		end
	end

	local function ListConfigSettings()
		for key, value in pairs(AI_NPC.Config) do
			if AI_NPC.ConfigDescription[key] then
				print("‖color:gui.orange‖" .. key .. " - " .. AI_NPC.ConfigDescription[key]:gsub("\n", " ") .. "‖end‖")
				print(key, ": " , tostring(value))
			end
		end
	end

	local function SetProfile(character, str)
		if not AI_NPC.Config.UseCharacterProfiles then
			print(Utils.MakeErrorText("Character Profiles are not enabled."))
			print(Utils.MakeErrorText("Use the  \"" .. AI_NPC.CmdPrefix .. "setconfig UseCharacterProfiles true\" command to enable them!"))
			return
		end
		
		AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())].Description = str
		-- Write this profile into the profiles file to preserve it.
		File.Write(SaveData.SavedCharactersFile, json.serialize(AI_NPC.CharacterProfiles))
		print(character.Name .. " profile has been set to: " .. str)
	end

	local function GetProfile(character)
		if not AI_NPC.Config.UseCharacterProfiles then
			print(Utils.MakeErrorText("Character Profiles are not enabled."))
			print(Utils.MakeErrorText("Use the  \"" .. AI_NPC.CmdPrefix .. "setconfig UseCharacterProfiles true\" command to enable them!"))
			return
		end
		
		local Profile = ""
		if AI_NPC.UniqueProfiles[character.Name] then
			-- If it's a unique character's name.
			Profile = AI_NPC.UniqueProfiles[character.Name].Description
			print(character.Name .. "'s Profile: " .. Profile)
			return
		elseif AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())] then
			Profile = AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())].Description
			print(character.Name .. "'s Profile: " .. Profile)
			return
		else
			print(Utils.MakeErrorText("No profile found for " .. character.Name .. "."))
		end
	end

	local function ClearProfile(character)
		if not AI_NPC.Config.UseCharacterProfiles then
			print(Utils.MakeErrorText("Character Profiles are not enabled."))
			print(Utils.MakeErrorText("Use the  \"" .. AI_NPC.CmdPrefix .. "setconfig UseCharacterProfiles true\" command to enable them!"))
			return
		end

		SetProfile(character, "")
	end
	
	local function SetStyle(character, str)
		if not AI_NPC.Config.UseCharacterProfiles then
			print(Utils.MakeErrorText("Character Profiles are not enabled."))
			print(Utils.MakeErrorText("Use the  \"" .. AI_NPC.CmdPrefix .. "setconfig UseCharacterProfiles true\" command to enable them!"))
			return
		end
		
		AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())].Style = str
		-- Write this profile into the profiles file to preserve it.
		File.Write(SaveData.SavedCharactersFile, json.serialize(AI_NPC.CharacterProfiles))
		print(character.Name .. " style has been set to: " .. str)
	end

	local function GiveRandomProfile(character)
		if not AI_NPC.Config.UseCharacterProfiles then
			print(Utils.MakeErrorText("Character Profiles are not enabled."))
			print(Utils.MakeErrorText("Use the  \"" .. AI_NPC.CmdPrefix .. "setconfig UseCharacterProfiles true\" command to enable them!"))
			return
		end

		AssignProfile(character, true)
		
		if AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())] then
			print(character.Name .. " profile has been set.")
			print("Description: " .. AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())].Description)
			print("Style: " .. AI_NPC.CharacterProfiles[tostring(character.Info.GetIdentifierUsingOriginalName())].Style)
		else
			print(Utils.MakeErrorText("Character profile not set."))
		end
	end

	local function ClearConversationHistory(character)
		local filename = string.format("%s/%s - %s.txt", SaveData.CurrentSaveDirectory, tostring(character.Info.GetIdentifierUsingOriginalName()), character.Info.OriginalName)
		if File.Exists(filename) then
			File.Delete(filename)
			print(character.Name .. "'s conversation history has been deleted.")
		else
			print(Utils.MakeErrorText("No conversation history found for " .. character.Name .. "."))
		end
	end

	-- The global functions that validate the argument list and call the local functions.
	function setConfig(args)
		if args and args[1] then
			ModifyConfigSetting(args[1], args[2])
		else
			print(Utils.MakeErrorText("Invalid argument list. Usage: " .. AI_NPC.CmdPrefix .. "setconfig [setting] [value]"))
		end
	end

	function getConfig(args)
		if args and args[1] then
			GetConfigSetting(args[1])
		else
			print(Utils.MakeErrorText("Invalid argument list. Usage: " .. AI_NPC.CmdPrefix .. "getconfig [setting]"))
		end
	end

	function listConfig(args)
		ListConfigSettings()
	end

	function setProfile(args)
		if not args or not args[1] then
			print(Utils.MakeErrorText("Invalid argument list. Usage: " .. AI_NPC.CmdPrefix .. "setprofile [character] [profile]"))
			return
		end
		
		local targetname = string.lower(Utils.RemoveQuotes(args[1]))
		
		local profile = ""
		if args[2] then
			profile = TrimLeadingWhitespace(table.concat(args, " ", 2))
		end
		
		local character = Utils.FindValidCharacter(targetname, false)
		if character then
			SetProfile(character, profile)
		else
			print(Utils.MakeErrorText("Character not found. Usage: " .. AI_NPC.CmdPrefix .. "setprofile [character] [profile]"))
		end
	end

	function getProfile(args)
		if not args or not args[1] then
			print(Utils.MakeErrorText("Invalid argument list. Usage: " .. AI_NPC.CmdPrefix .. "getprofile [character]"))
			return
		end
		
		local targetname = string.lower(Utils.RemoveQuotes(args[1]))
		local character = Utils.FindValidCharacter(targetname, false)
		if character then
			GetProfile(character)
		else
			print(Utils.MakeErrorText("Character not found. Usage: " .. AI_NPC.CmdPrefix .. "getprofile [character]"))
		end
	end

	function clearProfile(args)
		if not args or not args[1] then
			print(Utils.MakeErrorText("Invalid argument list. Usage: " .. AI_NPC.CmdPrefix .. "clearprofile [character]"))
			return
		end
		
		local targetname = string.lower(Utils.RemoveQuotes(args[1]))
		local character = Utils.FindValidCharacter(targetname, false)
		if character then
			ClearProfile(character)
		else
			print(Utils.MakeErrorText("Character not found. Usage: " .. AI_NPC.CmdPrefix .. "clearprofile [character]"))
		end
	end
	
	function setStyle(args)
		if not args or not args[1] then
			print(Utils.MakeErrorText("Invalid argument list. Usage: " .. AI_NPC.CmdPrefix .. "setstyle [character] [style]"))
			return
		end
		
		local targetname = string.lower(Utils.RemoveQuotes(args[1]))
		
		local style = ""
		if args[2] then
			style = TrimLeadingWhitespace(table.concat(args, " ", 2))
		end
		
		local character = Utils.FindValidCharacter(targetname, false)
		if character then
			SetStyle(character, style)
		else
			print(Utils.MakeErrorText("Character not found. Usage: " .. AI_NPC.CmdPrefix .. "setstyle [character] [style]"))
		end
	end
	
	function giveRandomProfile(args)
		if not args or not args[1] then
			print(Utils.MakeErrorText("Invalid argument list. Usage: " .. AI_NPC.CmdPrefix .. "giverandomprofile [character]"))
			return
		end
		
		local targetname = string.lower(Utils.RemoveQuotes(args[1]))
		local character = Utils.FindValidCharacter(targetname, false)
		if character then
			GiveRandomProfile(character)
		else
			print(Utils.MakeErrorText("Character not found. Usage: " .. AI_NPC.CmdPrefix .. "giverandomprofile [character]"))
		end
	end
	
	function clearConversationHistory(args)
		if not args or not args[1] then
			print(Utils.MakeErrorText("Invalid argument list. Usage: " .. AI_NPC.CmdPrefix .. "clearconversationhistory [character]"))
			return
		end
		
		local targetname = string.lower(Utils.RemoveQuotes(args[1]))
		local character = Utils.FindValidCharacter(targetname, false)
		if character then
			ClearConversationHistory(character)
		else
			print(Utils.MakeErrorText("Character not found. Usage: " .. AI_NPC.CmdPrefix .. "clearconversationhistory [character]"))
		end
	end
end