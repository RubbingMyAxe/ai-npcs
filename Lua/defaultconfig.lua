--[[
	Default Configuration Settings
--]]

-- Don't change anything here! Run the game with the mod to generate a config, and use the console commands to modify it.

local config = {}
local configDescription = {}
local configType = {}

config.APIEndpoint = "https://api.openai.com/v1/chat/completions"
configDescription.APIEndpoint = "The API Endpoint."
configType.APIEndpoint = "string"

config.APIKey = ""
configDescription.APIKey = "The API Key."
configType.APIKey = "string"

config.Model = "gpt-4o-mini"
configDescription.Model = "The AI Model."
configType.Model = "string"

config.Moderation = true
configDescription.Moderation = "Passes input to OpenAI's moderation API first to prevent violations of OpenAI's usage policies.\nAlso regulates player names in Multiplayer. Only works for OpenAI's endpoint. May add delay to responses. Does not use extra tokens."
configType.Moderation = "boolean"

config.PromptInstructions = "Let's roleplay in the universe of Barotrauma. "
config.PromptInstructions = config.PromptInstructions .. "Responses should be conversational and from a first-person perspective, without prefixes, emotes, actions, or narration of internal dialogue. "
config.PromptInstructions = config.PromptInstructions .. "When referencing the character traits or prompt, use unique words and phrases to convey the ideas without copying them exactly. "
config.PromptInstructions = config.PromptInstructions .. "Dialogue should be direct and immersive, staying true to the character’s perspective. "
config.PromptInstructions = config.PromptInstructions .. "Avoid asking questions or prompting for further information; instead, develop the narrative through the character’s actions and dialogue. "
config.PromptInstructions = config.PromptInstructions .. "Ensure that all responses are consistent with what the character knows and believes, and avoid introducing external information."
configDescription.PromptInstructions = "The instructions for the LLM to follow. The header of every prompt involving NPC conversations."
configType.PromptInstructions = "multiline-string"

config.CustomInstructions = ""
configDescription.CustomInstructions = "Custom instructions to add to every prompt."
configType.CustomInstructions = "multiline-string"

config.Language = "English"
configDescription.Language = "The language the AI should respond with."
configType.Language = "string"

config.EnableAPI = true
configDescription.EnableAPI = "Enable API calls. Set to false to test prompts without sending them to the API."
configType.EnableAPI = "boolean"

config.ConversationHistoryToUse = 10
configDescription.ConversationHistoryToUse = "The amount of chat history to use in API calls. Higher number uses more tokens, but gives more 'memory' to the NPCs."
configType.ConversationHistoryToUse = "number"

config.SessionTokenCap = -1
configDescription.SessionTokenCap = "A soft-cap on the max amount of tokens to use per session. Use -1 for unlimited. Actual token usage might exceed this cap slightly."
configType.SessionTokenCap = "number"

config.DebugMode = false
configDescription.DebugMode = "Enables more verbose console output."
configType.DebugMode = "boolean"

config.EnableForNPCs = true
configDescription.EnableForNPCs = "Allows NPCs to initiate AI messages."
configType.EnableForNPCs = "boolean"

config.ChanceForNPCSpeach = 80
configDescription.ChanceForNPCSpeach = "The chance for NPCs to initiate AI messages if EnableForNPCs is turned on. Higher number uses more tokens."
configType.ChanceForNPCSpeach = "number"

config.UseForCharacterIssues = "off"
configDescription.UseForCharacterIssues = "Experimental feature that lets NPCs use AI when reporting health issues. Can use lots of tokens. Three choices: full, mixed, off"
configType.UseForCharacterIssues = "dropdown:full,mixed,off"

config.UseCharacterProfiles = true
configDescription.UseCharacterProfiles = "Has a chance of giving NPCs a profile and style to make their responses more consistent. Uses more tokens."
configType.UseCharacterProfiles = "boolean"

config.ResponseChunkSize = 200
configDescription.ResponseChunkSize = "Attempts to split long responses into multiple chunks with this value as a soft-cap on each chunk's size. Use -1 for no chunking."
configType.ResponseChunkSize = "number"

config.UseMultipleMessages = false
configDescription.UseMultipleMessages = "Experimental internal setting that changes the way the API request is formed."
configType.UseMultipleMessages = "boolean"

return config, configDescription, configType