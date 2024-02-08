--[[
	Default Configuration Settings
--]]

-- Don't change anything here! Run the game with the mod to generate a config, and use the chat commands to modify it.

local config = {}
local configDescription = {}

config.APIEndpoint = "https://api.openai.com/v1/chat/completions"
configDescription.APIEndpoint = "The API Endpoint."

config.APIKey = ""
configDescription.APIKey = "The API Key."

config.Model = "gpt-3.5-turbo-0125"
configDescription.Model = "The AI Model."

config.Moderation = true
configDescription.Moderation = "Passes input to OpenAI's moderation API first to prevent violations of OpenAI's usage policies. Also regulates player names in Multiplayer. Only works for OpenAI's endpoint. May add delay to responses. Does not use extra tokens."

config.Language = "English"
configDescription.Language = "The language the AI should respond with."

config.EnableAPI = true
configDescription.EnableAPI = "Enable API calls. Set to false to test prompts without sending them to the API."

config.ConversationHistoryToUse = 10
configDescription.ConversationHistoryToUse = "The amount of chat history to use in API calls. Higher number uses more tokens, but gives more 'memory' to the NPCs."

config.SessionTokenCap = -1
configDescription.SessionTokenCap = "A soft-cap on the max amount of tokens to use per session. Use -1 for unlimited. Actual token usage might exceed this cap slightly."

config.DebugMode = false
configDescription.DebugMode = "Enables more verbose console output."

config.EnableForNPCs = true
configDescription.EnableForNPCs = "Allows NPCs to initiate AI messages."

config.ChanceForNPCSpeach = 20
configDescription.ChanceForNPCSpeach = "The chance for NPCs to initiate AI messages if EnableForNPCs is turned on. Higher number uses more tokens."

config.UseCharacterProfiles = true
configDescription.UseCharacterProfiles = "Has a chance of giving NPCs a profile and style to make their responses more consistent. Uses more tokens."

config.UseMultipleMessages = false
configDescription.UseMultipleMessages = "Experimental internal setting that changes the way the API request is formed."

return config, configDescription