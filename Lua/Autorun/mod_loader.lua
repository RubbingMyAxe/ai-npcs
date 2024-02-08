AI_NPC = {}
AI_NPC.Name = "AI NPCs"
AI_NPC.Version = "0.6"
AI_NPC.Path = table.pack(...)[1]
AI_NPC.Data = AI_NPC.Path .. "/Data"
AI_NPC.ConfigPath = AI_NPC.Path .. "/config.json"
AI_NPC.SaveData = AI_NPC.Path .. "/SaveData"
AI_NPC.CmdPrefix = "ai_"

-- Load configuration file.
if not File.Exists(AI_NPC.ConfigPath) then
	-- Create a new user config from the default script if there is no config file.
	AI_NPC.Config, AI_NPC.ConfigDescription = dofile(AI_NPC.Path .. "/Lua/defaultconfig.lua")
	File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
else
	-- Parse existing config file.
	local success, info = pcall(json.parse, File.Read(AI_NPC.ConfigPath))
	if success then
		
		AI_NPC.Config = info

		local defaultConfig, defaultConfigDescription = dofile(AI_NPC.Path .. "/Lua/defaultconfig.lua")
		AI_NPC.ConfigDescription = defaultConfigDescription;
		
		-- Add missing entries.
		for key, value in pairs(defaultConfig) do
			if AI_NPC.Config[key] == nil then
				AI_NPC.Config[key] = value
			end
		end
		
		-- Write the missing items pulled from the default file into the user's config file.
		File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
	else
		-- Create a new user config from the default script if existing file cannot be parsed.
		print("‖color:gui.red‖Failed to parse existing configuration file. Rewriting with default values.‖end‖")
		AI_NPC.Config, AI_NPC.ConfigDescription = dofile(AI_NPC.Path .. "/Lua/defaultconfig.lua")
		File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
	end
end

-- Commands file always loads.
-- So clients using the mod on a server can have the commands auto-fill.
dofile(AI_NPC.Path.."/Lua/AI_NPCs/Commands.lua")

-- All other files only load if server or in singleplayer.
if (Game.IsMultiplayer and SERVER) or Game.IsSingleplayer then
	dofile(AI_NPC.Path.."/Lua/AI_NPCs/Utils.lua")
	dofile(AI_NPC.Path.."/Lua/AI_NPCs/Missions.lua")
	dofile(AI_NPC.Path.."/Lua/AI_NPCs/CharacterProfiles.lua")
	dofile(AI_NPC.Path.."/Lua/AI_NPCs/Bestiary.lua")
	dofile(AI_NPC.Path.."/Lua/AI_NPCs/AI_NPC.lua")
	
	if string.len(AI_NPC.Config.APIEndpoint) == 0 then
		print(MakeErrorText("API Endpoint not defined in configuration file."))
		print(MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig APIEndpoint [url]\" command to set it!"))
	end

	if string.len(AI_NPC.Config.APIKey) == 0 then
		print(MakeErrorText("API Key not defined in configuration file."))
		print(MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig APIKey [key]>\" command to set it!"))
	end

	if string.len(AI_NPC.Config.Model) == 0 then
		print(MakeErrorText("Model is not defined in the configuration file."))
		print(MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig Model [name]\" command to set it!"))
	end

	if not AI_NPC.Config.EnableAPI then
		print(MakeErrorText("API calls are currently disabled."))
		print(MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig EnableAPI true\" command to enable them!"))
	end
else
	print("‖color:gui.red‖AI NPCs is not running because you are not the host of a multiplayer game or playing a singleplayer game.‖end‖")
	print("‖color:gui.red‖You can still use commands, if the server has granted you permission.‖end‖")
end