--[[
	Missions
--]]

-- Lets this run if on the server-side, if it's multiplayer, doesn't let it run on the client, and if it's singleplayer, lets it run on the client.
if CLIENT and Game.IsMultiplayer then return end

AI_NPC.Globals.MissionsFile = ""
AI_NPC.Globals.CurrentMissions = ""

-- Delete or replace problematic parts of mission descriptions.
local function FixMissionText(input)
	-- Define a regular expression pattern to match text between ‖
	local pattern = "‖(.-)‖"

	-- Replace the matched text with an empty string
	local result = string.gsub(input, pattern, "")

	-- Escape double quotes.
	result = EscapeQuotes(result)
	
	-- Also replace percent symbols.
	result = result:gsub("%%", " percent")

	return result
end

-- Returns a list of mission descriptions.
local function GetMissionsList()

	local unfinished_missions = {}

	for mission in Game.GameSession.Missions do
		if not mission.Completed and not mission.Failed then
			local mission_description = FixMissionText(mission.Description.Value)
			table.insert(unfinished_missions, "'" .. mission_description .. "'")
		end
	end
	
	return unfinished_missions
end

-- Writes the mission summaries from the AI endpoint to the MissionsFile.
local function GetMissionSummaries(res)

	local missions = GetAPIResponse(res)
	
	if string.len(missions) > 0 then
		AI_NPC.Globals.CurrentMissions = missions
		
		-- Write to file.
		if File.DirectoryExists(AI_NPC.Globals.CurrentSaveDirectory) then
			File.Write(AI_NPC.Globals.MissionsFile, AI_NPC.Globals.CurrentMissions)
		end
	end
		
end

-- Sends the current missions to the AI endpoint and requests a brief summary of them.
-- If fromFile is true, attempts to load from MissionsFile if it exists.
function LoadMissions(filename, fromFile)
	AI_NPC.Globals.MissionsFile = filename

	local UnfinishedMissions = GetMissionsList()

	-- Default to the full mission text, incase there is a problem getting the summary.
	AI_NPC.Globals.CurrentMissions = table.concat(UnfinishedMissions, ", ")

	-- If there's only one mission, don't bother trying to get a summary or writing the file.
	if #UnfinishedMissions > 1 then
		
		-- If file exists, load from file.
		if fromFile and File.DirectoryExists(AI_NPC.Globals.CurrentSaveDirectory) and File.Exists(AI_NPC.Globals.MissionsFile) then
			print("Reading missions from file.")
			AI_NPC.Globals.CurrentMissions = File.Read(AI_NPC.Globals.MissionsFile)
		elseif ValidateAPISettings() then
			local prompt_header = "Summarize these barotrauma missions, remove location names. One taciturn sentence each, avoid list structures: "
				
			local data = {
				model = AI_NPC.Config.Model,
				messages = {{
					role = "user",
					content = prompt_header .. AI_NPC.Globals.CurrentMissions
				}},
				temperature = 0.5,
				frequency_penalty = 0.4
			}
			
			JSONData = json.serialize(data)
			
			Networking.HttpPost(AI_NPC.Config.APIEndpoint, function(res) GetMissionSummaries(res) end, JSONData, "application/json", { ["Authorization"] = "Bearer " .. AI_NPC.Config.APIKey }, savePath)
		end
	else
		-- Delete missions file.
		if File.DirectoryExists(AI_NPC.Globals.CurrentSaveDirectory) and File.Exists(AI_NPC.Globals.MissionsFile) then
			File.Delete(AI_NPC.Globals.MissionsFile)
		end
	end
end