--[[
	OptionsScreen - GUI screen for editing config settings.
--]]

--[[if Game.IsMultiplayer then
	-- Receive ping from server
	Networking.Receive("pingServerToClient", function (message, client)
		if FG.clientConnectingToServer and (not FG.clientConnectedToServer) then
			print('[!] Received ping from server.')
			FG.clientConnectingToServer = false
			FG.clientConnectedToServer = true
			-- Answer ping from server (incase, for example, the server did "reloadlua")
			Networking.Receive("pingServerToClientAgain", function (message, client)
				print('[!] Sending ping to server again.')
				FG.clientConnectingToServer = true
				FG.clientConnectedToServer = false
				local message = Networking.Start("pingClientToServer")
				Networking.Send(message)
			end)
		end
	end)
end

-- Receive config file from admins
Networking.Receive("loadClientConfig", function (message, client)
	if not SERVER then return end
	if client.HasPermission(ClientPermissions.ConsoleCommands) then
		print('[!] Received config from a client.')
		if not pcall(function ()
			File.Write(FG.path .. '/config.json', message.ReadString())
		end) then
			print('[!] Error when saving settings presets to config!')
		end
		
		loadSettingsPresets()
		
		messageClient(client, 'text-general', string.localize('settingsApplied', nil, client.Language))
	end
end)]]--

-- GUI code only works client-side.
if SERVER then return end

-- main frame
local frame = GUI.Frame(GUI.RectTransform(Vector2(1, 1)), nil)
frame.CanBeFocused = false

-- menu frame
local menu = GUI.Frame(GUI.RectTransform(Vector2(1, 1), frame.RectTransform, GUI.Anchor.Center), nil)
menu.CanBeFocused = false
menu.Visible = false

-- Make it so the GUI is updated in lobby, game and sub editor
Hook.Patch("Barotrauma.NetLobbyScreen", "AddToGUIUpdateList", function()
    frame.AddToGUIUpdateList()
end, Hook.HookMethodType.After)
Hook.Patch("Barotrauma.GameScreen", "AddToGUIUpdateList", function()
    frame.AddToGUIUpdateList()
end)
Hook.Patch("Barotrauma.SubEditorScreen", "AddToGUIUpdateList", function()
    frame.AddToGUIUpdateList()
end)

-- returns the children of a component
local function GetChildren(comp)
    local tbl = {}
    for value in comp.GetAllChildren() do
        table.insert(tbl, value)
    end
    return tbl
end

-- Setup config menu
local function setupConfigMenu()
	
	-- put a button that goes behind the menu content, so we can close it when we click outside
	local closeButton = GUI.Button(GUI.RectTransform(Vector2(1, 1), menu.RectTransform, GUI.Anchor.Center), "", GUI.Alignment.Center, nil)
	closeButton.OnClicked = function ()
		menu.Visible = not menu.Visible
        --GUI.GUI.TogglePauseMenu()
	end

	-- Menu frame and menu list
	local menuContent = GUI.Frame(GUI.RectTransform(Vector2(0.57, 0.83), menu.RectTransform, GUI.Anchor.Center))
	local menuList = GUI.ListBox(GUI.RectTransform(Vector2(0.95, 0.9), menuContent.RectTransform, GUI.Anchor.Center))
	
	-- Text
	local text = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.05), menuContent.RectTransform), "AI NPCs Options", nil, nil, GUI.Alignment.Center)
	text.CanBeFocused = false
	text.textScale = 1.25
	
	for configSetting, configValue in pairs(AI_NPC.Config) do
		if AI_NPC.ConfigType[configSetting] == "string" then
		
			if type(AI_NPC.Config[configSetting]) ~= "string" then
				print(MakeErrorText("Invalid value for " .. configSetting .. ", reverting to default."))
				AI_NPC.Config[configSetting] = AI_NPC.DefaultConfig[configSetting]
				File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
			end
		
			-- Title text.
			local text = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.06), menuList.Content.RectTransform), configSetting .. ' - ' .. AI_NPC.ConfigDescription[configSetting], nil, nil, GUI.Alignment.BottomLeft)
			text.CanBeFocused = false
		
			local row = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.04), menuList.Content.RectTransform), nil)
			row.isHorizontal = true
			local buttonSize = 0.13
		
			-- Textbox for strings.
			local input = GUI.TextBox(GUI.RectTransform(Vector2(1 - buttonSize, 0.05), row.RectTransform), tostring(configValue), nil, nil, GUI.Alignment.CenterLeft)
			input.OnTextChangedDelegate = function (guiComponent)
				local value = guiComponent.Text
				AI_NPC.Config[configSetting] = value
				File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
			end
		elseif AI_NPC.ConfigType[configSetting] == "multiline-string" then
		
			if type(AI_NPC.Config[configSetting]) ~= "string" then
				print(MakeErrorText("Invalid value for " .. configSetting .. ", reverting to default."))
				AI_NPC.Config[configSetting] = AI_NPC.DefaultConfig[configSetting]
				File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
			end
		
			-- Title text.
			local text = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.06), menuList.Content.RectTransform), configSetting .. ' - ' .. AI_NPC.ConfigDescription[configSetting], nil, nil, GUI.Alignment.BottomLeft)
			text.CanBeFocused = false
		
			--local row = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.04), menuList.Content.RectTransform), nil)
			--row.isHorizontal = true
			--local buttonSize = 0.13
		
		
		    --[[local clientHighPriorityItems = MultiLineTextBox(config.Content.RectTransform, "", 0.2)

			clientHighPriorityItems.Text = table.concat(NT.Config.clientItemHighPriority, ",")

			clientHighPriorityItems.OnTextChangedDelegate = function (textBox)
				NT.Config.clientItemHighPriority = CommaStringToTable(textBox.Text)
			end]]--

		
			-- Textbox for strings.
			--local input = GUI.TextBox(GUI.RectTransform(Vector2(1 - buttonSize, 0.05), row.RectTransform), tostring(configValue), nil, nil, GUI.Alignment.CenterLeft)
			local input = AI_NPC.MultiLineTextBox(menuList.Content.RectTransform, tostring(configValue), 0.1) --GUI.TextBox(GUI.RectTransform(Vector2(1 - buttonSize, 0.05), row.RectTransform), tostring(configValue), nil, nil, GUI.Alignment.CenterLeft)
			input.OnTextChangedDelegate = function (guiComponent)
				local value = guiComponent.Text
				AI_NPC.Config[configSetting] = value
				File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
			end
		elseif AI_NPC.ConfigType[configSetting] == "number" then
		
			if type(AI_NPC.Config[configSetting]) ~= "number" then
				print(MakeErrorText("Invalid value for " .. configSetting .. ", reverting to default."))
				AI_NPC.Config[configSetting] = AI_NPC.DefaultConfig[configSetting]
				File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
			end
		
			-- Title text.
			local text = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.06), menuList.Content.RectTransform), configSetting .. ' - ' .. AI_NPC.ConfigDescription[configSetting], nil, nil, GUI.Alignment.BottomLeft)
			text.CanBeFocused = false
			
			local row = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.04), menuList.Content.RectTransform), nil)
			row.isHorizontal = true
			local buttonSize = 0.13
			
			-- Number box for numbers.
			local input = GUI.NumberInput(GUI.RectTransform(Vector2(0.25, 0.05), row.RectTransform), NumberType.Int, "", GUI.Alignment.CenterLeft)-- tostring(configValue), nil, nil, GUI.Alignment.CenterLeft)
			
			-- Max Values
			if configSetting == "ChanceForNPCSpeach" then
				input.MaxValueInt = 100
			end
			
			-- Min Values
			if configSetting == "SessionTokenCap" or configSetting == "ResponseChunkSize" then
				input.MinValueInt = -1
			else
				input.MinValueInt = 0
			end
			
			input.IntValue = tonumber(configValue)
			
			input.OnValueChanged = function (guiComponent)
				AI_NPC.Config[configSetting] = input.IntValue
				File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
			end
		elseif AI_NPC.ConfigType[configSetting] == "boolean" then
		
			if type(AI_NPC.Config[configSetting]) ~= "boolean" then
				print(MakeErrorText("Invalid value for " .. configSetting .. ", reverting to default."))
				AI_NPC.Config[configSetting] = AI_NPC.DefaultConfig[configSetting]
				File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
			end
		
			-- Title text.
			local text = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.06), menuList.Content.RectTransform), configSetting, nil, nil, GUI.Alignment.BottomLeft)
			text.CanBeFocused = false
		
			local row = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.04), menuList.Content.RectTransform), nil)
			row.isHorizontal = true
			local buttonSize = 0.13
			
			-- Checkbox for booleans.
			local input = GUI.TickBox(GUI.RectTransform(Vector2(1, 1), row.RectTransform), AI_NPC.ConfigDescription[configSetting])
			--input.RectTransform.AbsoluteOffset = Point(25, 55)
			input.Selected = configValue
			input.OnSelected = function ()
				if input.Selected then
					AI_NPC.Config[configSetting] = true
				else
					AI_NPC.Config[configSetting] = false
				end
				File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
			end
		elseif string.find(AI_NPC.ConfigType[configSetting], "dropdown") then
			-- Get the items for the dropdown list.
			local dropDownItems = {}
			-- Using string.gmatch to iterate over the substrings separated by commas
			for substring in AI_NPC.ConfigType[configSetting]:gmatch("([^:,]+)") do
				-- Skip the first substring (dropdown:)
				if substring ~= "dropdown" then
					table.insert(dropDownItems, substring)
				end
			end
		
			-- If there's no items to display, something is wrong with the setup so don't display anything.
			if #dropDownItems == 0 then
				return
			end
			
			if type(AI_NPC.Config[configSetting]) != "string" then
				print(MakeErrorText("Invalid value for " .. configSetting .. ", reverting to default."))
				AI_NPC.Config[configSetting] = AI_NPC.DefaultConfig[configSetting]
				File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
			end
			
			-- Title text.
			local text = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.06), menuList.Content.RectTransform), configSetting .. ' - ' .. AI_NPC.ConfigDescription[configSetting], nil, nil, GUI.Alignment.BottomLeft)
			text.CanBeFocused = false
		
			local row = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.04), menuList.Content.RectTransform), nil)
			row.isHorizontal = true
			local buttonSize = 0.13

			local dropdown = GUI.DropDown(GUI.RectTransform(Vector2(0.25, 0.9), row.RectTransform), AI_NPC.Config[configSetting], #dropDownItems, nil, false)
			dropdown.MustSelectAtLeastOne = true
			--dropdown.ButtonTextColor = Color(169, 212, 187)
			
			-- Add the dropdown list items.
			for item in dropDownItems do
				dropdown.AddItem(tostring(item),item)
			end
			
			dropdown.OnSelected = function (guiComponent, object)
				AI_NPC.Config[configSetting] = object
				File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
			end
		end
	end

	-- Spacing
	local text = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.015), menuList.Content.RectTransform), '', nil, nil, GUI.Alignment.BottomLeft)
	text.CanBeFocused = false

	-- Reset to default button.
	local button = GUI.Button(GUI.RectTransform(Vector2(1, 0.015),  menuList.Content.RectTransform), "Reset to Defaults", GUI.Alignment.Center, "GUITextBox")
	button.OnClicked = function ()
		AI_NPC.Config, AI_NPC.ConfigDescription = dofile(AI_NPC.Path .. "/Lua/defaultconfig.lua")
		AI_NPC.DefaultConfig = AI_NPC.Config
		File.Write(AI_NPC.ConfigPath, json.serialize(AI_NPC.Config))
		-- TODO: Repopulate the config settings on options screen without reloading lua.
		setupConfigMenu();
	end
	button.TextColor = Color(255, 100, 100)
	button.HoverTextColor = Color(255, 150, 150)
	button.SelectedTextColor = Color(200, 0, 0)
	button.Color = Color(255, 100, 100)
	button.HoverColor = Color(255, 150, 150)
	button.PressedColor = Color(200, 50, 50)
	
	
	
	-- TODO: Apply button for client/server?

	-- Close Button.
	local closeButton = GUI.Button(GUI.RectTransform(Vector2(1, 0.05), menuList.Content.RectTransform), "Close", GUI.Alignment.Center, "GUIButton")
	closeButton.OnClicked = function ()
		menu.Visible = not menu.Visible
        --GUI.GUI.TogglePauseMenu()
	end
end

setupConfigMenu()

-- Show button to open menu
Hook.Patch("Barotrauma.GUI", "TogglePauseMenu", {}, function ()
    if GUI.GUI.PauseMenuOpen then
		menu.Visible = false
        local frame = GUI.GUI.PauseMenu
        local list = GetChildren(GetChildren(frame)[2])[1]
		local button = GUI.Button(GUI.RectTransform(Vector2(1, 0.1), list.RectTransform), 'AI NPCs Options', GUI.Alignment.Center, "GUIButton")
		button.OnClicked = function ()
			GUI.GUI.TogglePauseMenu()
			menu.Visible = true
		end
	end
end, Hook.HookMethodType.After)