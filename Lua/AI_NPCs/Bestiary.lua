--[[
	Bestiary
--]]

-- Lets this run if on the server-side, if it's multiplayer, doesn't let it run on the client, and if it's singleplayer, lets it run on the client.
if CLIENT and Game.IsMultiplayer then return end

AI_NPC.Bestiary = json.parse(File.Read(AI_NPC.Data .. "/Bestiary.json"))