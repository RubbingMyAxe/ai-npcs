--[[
	Missions
--]]

-- Lets this run if on the server-side, if it's multiplayer, doesn't let it run on the client, and if it's singleplayer, lets it run on the client.
if CLIENT and Game.IsMultiplayer then return end

local Utils = AI_NPC.Utils
local Missions = AI_NPC.Missions
local SaveData = AI_NPC.SaveData

Missions.MissionsFile = ""
Missions.CurrentMissions = ""

-- Delete or replace problematic parts of mission descriptions.
local function FixMissionText(input)
	-- Define a regular expression pattern to match text between ‖
	local pattern = "‖(.-)‖"

	-- Replace the matched text with an empty string
	local result = string.gsub(input, pattern, "")

	-- Escape double quotes.
	result = Utils.EscapeQuotes(result)
	
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

	local missions = Utils.GetAPIResponse(res)
	
	if string.len(missions) > 0 then
		Missions.CurrentMissions = missions
		
		-- Write to file.
		if File.DirectoryExists(SaveData.CurrentSaveDirectory) then
			File.Write(Missions.MissionsFile, Missions.CurrentMissions)
		end
	end
		
end

-- Sends the current missions to the AI endpoint and requests a brief summary of them.
-- If fromFile is true, attempts to load from MissionsFile if it exists.
function Missions.LoadMissions(filename, fromFile)
	Missions.MissionsFile = filename

	local UnfinishedMissions = GetMissionsList()

	-- Default to the full mission text, incase there is a problem getting the summary.
	Missions.CurrentMissions = table.concat(UnfinishedMissions, ", ")

	-- If there's only one mission, don't bother trying to get a summary or writing the file.
	if #UnfinishedMissions > 1 then
		
		-- If file exists, load from file.
		if fromFile and File.DirectoryExists(SaveData.CurrentSaveDirectory) and File.Exists(Missions.MissionsFile) then
			print("Reading missions from file.")
			Missions.CurrentMissions = File.Read(Missions.MissionsFile)
		elseif ValidateAPISettings() then
			local prompt_header = "Summarize these barotrauma missions, remove location names. One taciturn sentence each, avoid list structures: "
				
			local data = {
				model = AI_NPC.Config.Model,
				messages = {{
					role = "user",
					content = prompt_header .. Missions.CurrentMissions
				}},
				temperature = 0.5,
				frequency_penalty = 0.4
			}
			
			JSONData = json.serialize(data)
			
			Networking.HttpPost(AI_NPC.Config.APIEndpoint, function(res) GetMissionSummaries(res) end, JSONData, "application/json", { ["Authorization"] = "Bearer " .. AI_NPC.Config.APIKey }, savePath)
		end
	else
		-- Delete missions file.
		if File.DirectoryExists(SaveData.CurrentSaveDirectory) and File.Exists(Missions.MissionsFile) then
			File.Delete(Missions.MissionsFile)
		end
	end
end