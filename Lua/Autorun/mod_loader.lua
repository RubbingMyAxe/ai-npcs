AI_NPC = {}
AI_NPC.Name = "AI NPCs"
AI_NPC.Version = "0.8"
AI_NPC.Path = table.pack(...)[1]
AI_NPC.Data = AI_NPC.Path .. "/Data"
AI_NPC.ConfigPath = AI_NPC.Path .. "/config.json"
AI_NPC.SavePath = AI_NPC.Path .. "/SaveData"
AI_NPC.CmdPrefix = "ai_"

-- Variables to hold global variables to prevent conflicts with other mods.
AI_NPC.Globals = {}
-- Variable to keep track of token usage.
-- Resets when LUA is reloaded.
AI_NPC.Globals.tokens_used_this_session = 0

AI_NPC.UniqueCharacterProfiles = {}
AI_NPC.CharacterProfiles = {}
AI_NPC.Missions = {}
AI_NPC.Bestiary = {}
AI_NPC.Orders = {}
AI_NPC.Utils = {}
AI_NPC.SaveData = {}
AI_NPC.SaveData.CurrentSaveDirectory = ""

-- Load configuration file.
if not File.Exists(AI_NPC.ConfigPath) then
	-- Create a new user config from the default script if there is no config file.
	AI_NPC.Config, AI_NPC.ConfigDescription, AI_NPC.ConfigType = dofile(AI_NPC.Path .. "/Lua/defaultconfig.lua")
	AI_NPC.DefaultConfig = AI_NPC.Config
	File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
else
	-- Parse existing config file.
	local success, info = pcall(json.parse, File.Read(AI_NPC.ConfigPath))
	if success then
		
		AI_NPC.Config = info

		local defaultConfig, defaultConfigDescription, defaultConfigType = dofile(AI_NPC.Path .. "/Lua/defaultconfig.lua")
		AI_NPC.DefaultConfig = defaultConfig
		AI_NPC.ConfigDescription = defaultConfigDescription;
		AI_NPC.ConfigType = defaultConfigType;
		
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
		AI_NPC.DefaultConfig = AI_NPC.Config
		File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
	end
end

-- Commands file always loads.
-- So clients using the mod on a server can have the commands auto-fill.
dofile(AI_NPC.Path.."/Lua/AI_NPCs/Commands.lua")

-- All other files only load if server or in singleplayer.
if (Game.IsMultiplayer and SERVER) or Game.IsSingleplayer then
	-- Utils usually needs to load first because it has the Utils.MakeErrorText function to color code errors in the console.
	dofile(AI_NPC.Path.."/Lua/AI_NPCs/Utils.lua")
	
	-- Only supporting single player for the Options screen until networking can be added.
	if Game.IsSingleplayer then
		AI_NPC.MultiLineTextBox = dofile(AI_NPC.Path.."/Lua/AI_NPCs/MultiLineTextBox.lua")
		dofile(AI_NPC.Path.."/Lua/AI_NPCs/OptionsScreen.lua")
	end
	
	dofile(AI_NPC.Path.."/Lua/AI_NPCs/Missions.lua")
	dofile(AI_NPC.Path.."/Lua/AI_NPCs/CharacterProfiles.lua")
	dofile(AI_NPC.Path.."/Lua/AI_NPCs/Bestiary.lua")
	dofile(AI_NPC.Path.."/Lua/AI_NPCs/Orders.lua")
	dofile(AI_NPC.Path.."/Lua/AI_NPCs/AI_NPC.lua")
	
	if string.len(AI_NPC.Config.APIEndpoint) == 0 then
		print(AI_NPC.Utils.MakeErrorText("API Endpoint not defined in configuration file."))
		print(AI_NPC.Utils.MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig APIEndpoint [url]\" command to set it!"))
	end

	if string.len(AI_NPC.Config.APIKey) == 0 then
		print(AI_NPC.Utils.MakeErrorText("API Key not defined in configuration file."))
		print(AI_NPC.Utils.MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig APIKey [key]>\" command to set it!"))
	end

	if string.len(AI_NPC.Config.Model) == 0 then
		print(AI_NPC.Utils.MakeErrorText("Model is not defined in the configuration file."))
		print(AI_NPC.Utils.MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig Model [name]\" command to set it!"))
	end

	if not AI_NPC.Config.EnableAPI then
		print(AI_NPC.Utils.MakeErrorText("API calls are currently disabled."))
		print(AI_NPC.Utils.MakeErrorText("Use the \"" .. AI_NPC.CmdPrefix .. "setconfig EnableAPI true\" command to enable them!"))
	end
else
	print("‖color:gui.red‖AI NPCs is not running because you are not the host of a multiplayer game or playing a singleplayer game.‖end‖")
	print("‖color:gui.red‖You can still use commands, if the server has granted you permission.‖end‖")
end