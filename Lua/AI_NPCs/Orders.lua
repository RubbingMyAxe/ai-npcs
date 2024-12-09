--[[
	Orders
--]]

-- Lets this run if on the server-side, if it's multiplayer, doesn't let it run on the client, and if it's singleplayer, lets it run on the client.
if CLIENT and Game.IsMultiplayer then return end

local Utils = AI_NPC.Utils
--AI_NPC.Orders.OrderQueue = {}

-- Make fabricationRecipes accessible so that recipes can be looked up.
LuaUserData.MakeFieldAccessible(Descriptors["Barotrauma.Items.Components.Fabricator"], "fabricationRecipes")
-- Make StartFabricating() accessible so that it can be used to start the fabricator.
LuaUserData.MakeMethodAccessible(Descriptors["Barotrauma.Items.Components.Fabricator"], "StartFabricating")
-- Make CanBeFabricated accessible so that it can be used to determine if the ingredients for a recipe are available.
LuaUserData.MakeMethodAccessible(Descriptors["Barotrauma.Items.Components.Fabricator"], "CanBeFabricated")
-- Make availableIngredients accessible and register its type, so that it can be used to call CanBeFabricated().
LuaUserData.MakeFieldAccessible(Descriptors["Barotrauma.Items.Components.Fabricator"], "availableIngredients")
LuaUserData.RegisterType("System.Collections.Generic.Dictionary`2[[Barotrauma.Identifier,BarotraumaCore],[System.Collections.Generic.List`1[[Barotrauma.Item]]]]")
-- Make RefreshAvailableIngredients accessible so that it can be called before checking ingredients in MP.
LuaUserData.MakeMethodAccessible(Descriptors["Barotrauma.Items.Components.Fabricator"], "RefreshAvailableIngredients")
-- Make user accessible so that the user of the fabricator can be set.
LuaUserData.MakeFieldAccessible(Descriptors["Barotrauma.Items.Components.Fabricator"], "user")
-- TODO: Was going to use the state to determine when the fabricator was done fabricating, but couldn't get that to work yet.
--LuaUserData.MakeFieldAccessible(Descriptors["Barotrauma.Items.Components.Fabricator"], "state")

-- Registering this type because it's a parameter to TryPutItem, which is used in GiveItem.
LuaUserData.RegisterType('System.Collections.Generic.IEnumerable`1[[Barotrauma.InvSlotType]]')
-- Registering and creating a static OrderChatMessage so that these can be created when running as a server.
LuaUserData.RegisterType("Barotrauma.Networking.OrderChatMessage")
local OrderChatMessage = LuaUserData.CreateStatic("Barotrauma.Networking.OrderChatMessage", true)

LuaUserData.MakeMethodAccessible(Descriptors["Barotrauma.AIObjectiveManager"], "DismissSelf")

--LuaUserData.MakeMethodAccessible(Descriptors["Barotrauma.AIObjectiveIdle"], "SetTargetTimerHigh")
--LuaUserData.MakePropertyAccessible(Descriptors["Barotrauma.AIObjectiveIdle"], "AllowAutomaticItemUnequipping")

--LuaUserData.MakeMethodAccessible(Descriptors["Barotrauma.AIObjectiveIdle"], "get_AllowAutomaticItemUnequipping")


--[[local OrderQueueTimer = 0
Hook.Add("think", "OrderQueueTimer", function()
    if OrderQueueTimer > Timer.GetTime() then return end -- skip code below

	for i = #AI_NPC.Orders.OrderQueue, 1, -1 do
		local queued_order = AI_NPC.Orders.OrderQueue[i]
		if queued_order.order_time > Timer.GetTime() then
			ProcessOrder(queued_order.order[1], queued_order.order[2], queued_order.order[3])
			table.remove(AI_NPC.Orders.OrderQueue, i)
		end
	end

    OrderQueueTimer = Timer.GetTime() + 2
end)

local function Wait(source, character, target, remaining_orders)
	local orderPrefab = OrderPrefab.Prefabs["wait"]
	local order = Order(orderPrefab, Identifier.Empty, nil, nil).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
	character.SetOrder(order, true, false, true)
	
	if tonumber(target) and next(remaining_orders) then
		local order_time = Timer.GetTime() + tonumber(target)
		table.insert(AI_NPC.Orders.OrderQueue, {order_time = order_time, order = {source, character, remaining_orders})
	end
end]]--

-- More verbose console output for orders debug mode.
local function PrintOrdersDebugInfo(msg)
	if AI_NPC.Config.DebugOrders then
		print(msg)
	end
end

local function SetOrder(order, character, source, speak)
	character.SetOrder(order, true, speak or false, true)

	if SERVER then
		local msg = OrderChatMessage(order, speak and nil or "", character, source, true)
		Game.Server.SendOrderChatMessage(msg)
	end
end

-- Dismiss orders. If movementOnly is true, will only dismiss movement related orders like Follow or Wait.
local function DismissOrders(character, movementOnly)
	if character.CurrentOrders then
		for order in character.CurrentOrders do
			if not movementOnly or (movementOnly and order.Category == OrderCategory.Movement) then
				local manager = character.AIController.ObjectiveManager
				manager.DismissSelf(order)
				--private void DismissSelf(Order order)
				--SetOrder(order.GetDismissal(), character, source, false)
			end
		end
	end
end

-- Gives the character the Wait order. Optional parameter will make it continue to the next order after a number of seconds.
local function Wait(source, character, target, remaining_orders, first_order)
	local orderPrefab = OrderPrefab.Prefabs["wait"]
	local order = Order(orderPrefab, Identifier.Empty, nil, nil).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
	SetOrder(order, character, source, first_order and not AI_NPC.Config.EnableChat)

	local wait_time = tonumber(target)
	if wait_time and wait_time > 0 then
		if next(remaining_orders) then
			Timer.Wait(function () AI_NPC.Orders.ProcessOrder(source, character, remaining_orders) end, wait_time * 1000)
		else
			Timer.Wait(function () DismissOrders(character, true) end, wait_time * 1000)
		end
	end
end

-- Gives the character the Follow order.
local function Follow(source, character, target, remaining_orders, first_order)
	local found_target = nil
	
	if target == "me" then
		found_target = source
	elseif target ~= "unknown" then
		-- Find a friendly character by name.
		for _, entity in pairs(Character.CharacterList) do
			if entity ~= character and entity.Submarine and Character.IsOnFriendlyTeam(character, entity) and character.Submarine.IsConnectedTo(entity.Submarine) then
				if string.find(string.lower(entity.Name), target) then
					found_target = entity
				end
			end
		end
	end
	
	if found_target then
		PrintOrdersDebugInfo(found_target.Name)
		local orderPrefab = OrderPrefab.Prefabs["follow"]
		local order = Order(orderPrefab, found_target, nil, found_target).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
		SetOrder(order, character, source, first_order and not AI_NPC.Config.EnableChat)
	end
end

-- Sets an objective to go to a certain place, structure, or character. Will continue to the next order afterward.
local function GoTo(source, character, target, remaining_orders, first_order)
	local found_target = nil
	
	-- Variable that decides how close to get before stopping.
	local CloseEnoughMultiplier = 1
	
	if target == "me" or target == "here" then
		found_target = source
		-- Let them stop a little further away from people.
		CloseEnoughMultiplier = 1.5
	end
	
	if character.Submarine and target ~= "unknown" then
		-- Find a location on the current submarine.
		if not found_target then
			for hull in character.Submarine.GetHulls(false) do
				if string.find(string.lower(hull.DisplayName.Value), target) then
					found_target = hull
					break
				end
			end
		end
		
		-- Find a structure on the current submarine.
		if not found_target then
			for repairable in Item.RepairableItems do
				if string.find(string.lower(repairable.Name), target) and character.Submarine.IsEntityFoundOnThisSub(repairable, false) then
					found_target = repairable
					break
				end
			end
		end
		
		-- Find a character by name.
		if not found_target then
			for _, entity in pairs(Character.CharacterList) do
				if entity ~= character and entity.Submarine and Character.IsOnFriendlyTeam(character, entity) and character.Submarine.IsConnectedTo(entity.Submarine) then
					if string.find(string.lower(entity.Name), target) then
						found_target = entity
						-- Let them stop a little further away from people.
						CloseEnoughMultiplier = 1.5
						break
					end
				end
			end
		end
		
		-- Find a character by title.
		if not found_target then
			for _, entity in pairs(Character.CharacterList) do
				if entity ~= character and entity.Submarine and Character.IsOnFriendlyTeam(character, entity) and character.Submarine.IsConnectedTo(entity.Submarine) then
					if entity.Info.Title and string.find(string.lower(entity.Info.Title.Value), target) then
						found_target = entity
						break
					end
				end
			end
		end
	end

	if found_target then
		PrintOrdersDebugInfo(found_target)
		DismissOrders(character, true)
		
		local manager = character.AIController.ObjectiveManager
		local gotoObjective = AIObjectiveGoTo(found_target, character, manager)
		gotoObjective.BasePriority = 100
		gotoObjective.CloseEnoughMultiplier = CloseEnoughMultiplier
		
		gotoObjective.Completed.add(function ()
			if next(remaining_orders) then
				AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
			else
				Wait(source, character, target, remaining_orders)
			end
		end)
		
		gotoObjective.Abandoned.add(function ()
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
		end)	
		
		manager.AddObjective(gotoObjective)
	else
		AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
	end
end

-- Sets a repair order or objective. Will continue to the next order.
-- If no target is found or is unknown, set a general repair order.
-- If a target is found, set a repair objective.
local function Repair(source, character, target, remaining_orders, first_order)
	local found_item = nil
	
	if target ~= "unknown" and character.Submarine then
		-- Find by name.
		for repairable in Item.RepairableItems do
			if string.find(string.lower(repairable.Name), target) and character.Submarine.IsEntityFoundOnThisSub(repairable, false) and repairable.ConditionPercentage < 50.0 then
				found_item = repairable
			end
		end
		
		-- Find by tag.
		if not found_item then
			for repairable in Item.RepairableItems do
				if repairable.HasTag(target) and character.Submarine.IsEntityFoundOnThisSub(repairable, false) and repairable.ConditionPercentage < 50.0 then
					found_item = repairable
				end
			end
		end
	end

	if found_item then
		PrintOrdersDebugInfo(found_item)
		DismissOrders(character, true)
		local manager = character.AIController.ObjectiveManager
		local getRepairObjective = AIObjectiveRepairItem(character, found_item, manager, 1, true)
		getRepairObjective.BasePriority = 100
		getRepairObjective.Completed.add(function ()
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
		end)
		
		getRepairObjective.Abandoned.add(function ()
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
		end)	
		
		manager.AddObjective(getRepairObjective)

	else
		local repairPrefab = OrderPrefab.Prefabs["repairsystems"]
		local repairOrder = Order(repairPrefab, nil, character).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
		SetOrder(repairOrder, character, source, first_order and not AI_NPC.Config.EnableChat)
		
		local fixleaksPrefab = OrderPrefab.Prefabs["fixleaks"]
		local fixleaksOrder = Order(fixleaksPrefab, nil, character).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
		SetOrder(fixleaksOrder, character, source, false)
		
		AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
	end
end

-- Used to locate an item that can be picked up by name or tag.
local function FindItemOnAnyFriendlySubmarine(character, target, includingConnectedSubs, allowIllegitimate, includeAmmo, useInventory)
	local found_items = {}
	
	if not character or not character.Submarine or not target or target == "unknown" then
        return found_items
    end
	
	local distance = nil
	--local possible_items = {}
	
	local exact_match = nil
	
	-- Iterate over all items.
	for _, item in ipairs(Item.ItemList) do
		
		-- Skip items that can't be picked up or are attached to the submarine.
		local pickable = item.GetComponent(Components.Pickable)
		local projectile = item.GetComponent(Components.Projectile)
		--local holdable = item.GetComponentString("Holdable") -- This excludes body armor.
		
		if not pickable or pickable.IsAttached then goto continue end

		-- Exclude doors.
		if pickable.GetType() == Components.Door then goto continue end

		-- Skip if ammo is excluded and the item is ammo.
		-- TODO: If character already has the gun, maybe pick the ammo?
		-- This looks for bullets in gun magazines like assaultrifleround.
		if projectile and
			item.ParentInventory and
			LuaUserData.IsTargetType(item.ParentInventory, "Barotrauma.ItemInventory") and
			item.ParentInventory.Container and
			item.ParentInventory.Container.DrawInventory == false then
			goto continue 
		end
		if not includeAmmo and item.HasTag("handheldammo") then goto continue end

		-- Check if there is an item with an exact match to the search text, by name or identifier.
		if not exact_match then
			if string.lower(item.Name) == target or string.lower(item.Prefab.Identifier.Value) == target then
				exact_match = item.Prefab.Identifier.Value
			end
		end

		if exact_match and item.Prefab.Identifier.Value ~= exact_match then
			goto continue
		end
		
		-- Check if the item's name or tags match the target.
		if not exact_match and not string.find(string.lower(item.Name), target) and not item.HasTag(target) then
			goto continue
		end
		
		if useInventory then
			-- If there's a match in their own inventory, use that one.
			if item.GetRootInventoryOwner() == character then
				table.insert(found_items, {item = item, distance = 1.0})
			end
		else
			-- Skip items in own inventory.
			if item.GetRootInventoryOwner() == character then
				goto continue
			end
		end

		-- Skip items the character cannot access.
		if not item.HasAccess(character) then goto continue end

		-- Skip if item is in someone else's inventory.
		if character.IsItemTakenBySomeoneElse(item) then goto continue end

		-- Check for illegitimacy if required.
		if item.Illegitimate and not allowIllegitimate then goto continue end

		-- Check if the item is on a friendly submarine.
		if not item.Submarine then goto continue end
		if not character.IsOnFriendlyTeam(item.Submarine.TeamID) then goto continue end
		
		distance = AIObjective.GetDistanceFactor(character.WorldPosition, item.WorldPosition, 0.0, 5.0, 5000.0, 1.0)

		table.insert(found_items, {item = item, distance = distance})
		
		::continue::
	end
	
	-- Print all the found items in debug mode. Remove any non-exact matches if an exact match was found.
	for i = #found_items, 1, -1 do
		if exact_match and found_items[i].item.Prefab.Identifier.Value ~= exact_match then
			table.remove(found_items, i)
		--else
		--	PrintOrdersDebugInfo(found_items[i].item.ToString() .. ", " .. tostring(found_items[i].distance))
		end
	end

	-- Sort the items so that the closest one is on top.
	table.sort(found_items, function(a, b)
		return a.distance > b.distance
	end)

	return found_items
end

local function GetItem(source, character, target, remaining_orders, first_order)
	-- TODO: Prioritize ammo for a gun if already has gun?
	-- TODO: Ability to get an item if one is already in inventory?
	local found_items = {}
	
	if target ~= "unknown" then
		found_items = FindItemOnAnyFriendlySubmarine(character, target, true, false, false, false)
	end
	
	if #found_items > 0 then
		PrintOrdersDebugInfo(found_items[1].item)
		DismissOrders(character, true)
		local manager = character.AIController.ObjectiveManager

		-- Try to let the character find and get the closest item of the same type.
		--local getItemObjective = AIObjectiveGetItem(character, found_items[1].item.Prefab.Identifier, manager, true) --, true, 99, false)
		local getItemObjective = AIObjectiveGetItem(character, found_items[1].item, manager, true) --, true, 99, false)
		getItemObjective.BasePriority = 100
		getItemObjective.Wear = true
		getItemObjective.Equip = true
		getItemObjective.AllowVariants = true
		
		-- If it successfully gets the item.
		getItemObjective.Completed.add(function ()
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
		end)
		
		-- If it abandons the objective, it's because it couldn't find the item. Possibly because it's on a station.
		getItemObjective.Abandoned.add(function ()
		
				-- Manually go to the exact item we found and try to take it.
				local gotoItemObjective = AIObjectiveGoTo(found_items[1].item, character, manager)
				gotoItemObjective.Completed.add(function ()
					local ai = character.AIController
					ai.TakeItem(found_items[1].item, character.Inventory, true, true, true, true, true)
					
				AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
				end)

				manager.AddObjective(gotoItemObjective)
		end)
		
		manager.AddObjective(getItemObjective)
	else
		AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
	end
end

local function Fight(source, character, target, remaining_orders, first_order)
	local found_target = nil
	
	if target == "me" then
		found_target = source
	elseif target ~= "unknown" then
		-- Find a character by name.
		for _, entity in pairs(Character.CharacterList) do
			if entity ~= character and entity.Submarine and character.Submarine.IsConnectedTo(entity.Submarine) then
				if string.find(string.lower(entity.Name), target) then
					found_target = entity
				end
			end
		end
		
		-- Find a character by title.
		if not found_target then
			for _, entity in pairs(Character.CharacterList) do
				if entity ~= character and entity.Submarine and character.Submarine.IsConnectedTo(entity.Submarine) then
					if entity.Info.Title and string.find(string.lower(entity.Info.Title.Value), target) then
						found_target = entity
					end
				end
			end
		end
	end

	if found_target then
		PrintOrdersDebugInfo(found_target)
		DismissOrders(character, true)
		
		local manager = character.AIController.ObjectiveManager
		local gotoItemObjective = AIObjectiveGoTo(found_target, character, manager)
		gotoItemObjective.Completed.add(function ()
			local ai = character.AIController
			ai.AddCombatObjective(AIObjectiveCombat.CombatMode.Offensive, found_target)
		end)
		
		manager.AddObjective(gotoItemObjective)
	else
		local orderPrefab = OrderPrefab.Prefabs["fightintruders"]
		local order = Order(orderPrefab, nil, source).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
		SetOrder(order, character, source, first_order and not AI_NPC.Config.EnableChat)
	end
end

local function DropItem(source, character, target, remaining_orders, first_order)
	local found_item = nil
	local priority = 0
	
	if target ~= "unknown" then
		for item in character.Inventory.AllItems do
			if item.HasAccess(character) then
				local current_priority = 0

				-- Determine priority level.
				if string.lower(item.Name) == target or string.lower(item.Prefab.Identifier.Value) == target then
					found_item = item -- Exact match, no need to search further.
					break
				elseif string.find(string.lower(item.Name), target) and not item.HasTag("handheldammo") then
					current_priority = 2
				elseif item.HasTag(target) and not item.HasTag("handheldammo") then
					current_priority = 1 -- Lowest priority
				end

				-- Update found item if this has higher priority.
				if current_priority > priority then
					found_item = item
					priority = current_priority
				end
			end
		end
	end

	if found_item then
		PrintOrdersDebugInfo(found_target)
		found_item.DontCleanUp = true
		found_item.Drop(character)
	end

	AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
end

local function GiveItem(source, character, target, remaining_orders, first_order)
	-- Find by name.
	local found_item = nil
	local priority = 0

	for item in character.Inventory.AllItems do
		if item.HasAccess(character) then
			local current_priority = 0

			-- Determine priority level.
			if string.lower(item.Name) == target or string.lower(item.Prefab.Identifier.Value) == target then
				found_item = item -- Exact match, no need to search further.
				break
			elseif string.find(string.lower(item.Name), target) and not item.HasTag("handheldammo") then
				current_priority = 2
			elseif item.HasTag(target) and not item.HasTag("handheldammo") then
				current_priority = 1 -- Lowest priority
			end

			-- Update found item if this has higher priority.
			if current_priority > priority then
				found_item = item
				priority = current_priority
			end
		end
	end

	if found_item then
		PrintOrdersDebugInfo(found_item)
		DismissOrders(character, true)
		local manager = character.AIController.ObjectiveManager
		local gotoObjective = AIObjectiveGoTo(source, character, manager)
		gotoObjective.BasePriority = 100

		gotoObjective.Completed.add(function ()
			
			if found_item.ParentInventory == character.Inventory then
				character.SelectCharacter(source)

				if SERVER then 
					character.SelectedCharacter.Inventory.TryPutItem(found_item, source, found_item.AllowedSlots);
				else
					local ai = source.AIController
					ai.TakeItem(found_item, source.Inventory, false, false)
				end
			end
			
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
		end)
		
		
		gotoObjective.Abandoned.add(function ()
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
		end)
		
		manager.AddObjective(gotoObjective)
	else
		AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
	end
end


local function Fabricate(source, character, target, remaining_orders, first_order)

	-- Gets a craftable
	local function GetCraftableRecipe(fabricator_component, itemToCraft, character)
		local found_recipe = nil

		if not fabricator_component then return nil end

		fabricator_component.user = character
		
		if SERVER then 
			fabricator_component.RefreshAvailableIngredients()
		end

		for _, recipe in pairs(fabricator_component.fabricationRecipes) do
			local recipe_name = string.lower(recipe.DisplayName.Value)
			local recipe_id = string.lower(recipe.TargetItemPrefabIdentifier.ToString())

			-- Determine priority level
			if recipe_name == itemToCraft or recipe_id == itemToCraft then
				if fabricator_component.CanBeFabricated(recipe, fabricator_component.availableIngredients, character) then
					found_recipe = recipe
					break
				end
			elseif string.find(recipe_name, itemToCraft) or string.find(recipe_id, itemToCraft) then
				if fabricator_component.CanBeFabricated(recipe, fabricator_component.availableIngredients, character) then
					found_recipe = recipe
				end
			end
		end

		-- Look for exact match by name or identifier first.
		--[[for key, value in pairs(fabricator_component.fabricationRecipes) do
			if (string.lower(value.DisplayName.Value) == itemToCraft or string.lower(value.TargetItemPrefabIdentifier.ToString()) == itemToCraft) and fabricator_component.CanBeFabricated(value, fabricator_component.availableIngredients, character) then
				recipe = value
				break
			end
		end
		
		-- Look for a partial match.
		if not recipe then
			for key, value in pairs(fabricator_component.fabricationRecipes) do
				if (string.find(string.lower(value.TargetItemPrefabIdentifier.ToString()), itemToCraft) or string.find(string.lower(value.DisplayName.Value), itemToCraft)) and fabricator_component.CanBeFabricated(value, fabricator_component.availableIngredients, character) then
					recipe = value
					break
				end
			end
		end]]--
		
		return found_recipe
	end
	
	-- Starts the fabrication process.
	local function TurnOnFabricator(fabricator_component, amount, recipe, character)
		fabricator_component.AmountToFabricate = amount
		fabricator_component.StartFabricating(recipe, character)
		return true
	end

	local found_fabricator = nil
	local found_medical_fabricator = nil
	
	if character.Submarine and target ~= "unknown" then
		-- Find a fabricator on the current submarine.
		for repairable in Item.RepairableItems do
			if character.Submarine.IsEntityFoundOnThisSub(repairable, false) then
				if repairable.HasTag("fabricator") then
					found_fabricator = repairable
				elseif repairable.HasTag("medicalfabricator") then
					found_medical_fabricator = repairable
				end
			end
		end
		
		-- Find a fabricator on attached submarine.
		if not found_fabricator or not found_medical_fabricator then
			for repairable in Item.RepairableItems do
				if not found_fabricator and repairable.HasTag("fabricator") and character.Submarine.IsEntityFoundOnThisSub(repairable, true) then
					found_fabricator = repairable
				elseif not found_medical_fabricator and repairable.HasTag("medicalfabricator") and character.Submarine.IsEntityFoundOnThisSub(repairable, true) then
					found_medical_fabricator = repairable
				end
			end
		end
	end

	if found_fabricator or found_medical_fabricator then
		PrintOrdersDebugInfo("Fabricator: " .. found_fabricator.ToString())
		PrintOrdersDebugInfo("Medical Fabricator: " .. found_medical_fabricator.ToString())
		DismissOrders(character, true)
		
		local fabricator_to_use = nil
		local component_to_use = nil
		local fabricator_component = found_fabricator and found_fabricator.GetComponentString("Fabricator") or nil
		local recipe = GetCraftableRecipe(fabricator_component, target, character)
		
		if recipe then
			fabricator_to_use = found_fabricator
			component_to_use = fabricator_component
		else
			local medical_fabricator_component = found_medical_fabricator and  found_medical_fabricator.GetComponentString("Fabricator") or nil
			recipe = GetCraftableRecipe(medical_fabricator_component, target, character)

			if recipe then	
				fabricator_to_use = found_medical_fabricator
				component_to_use = medical_fabricator_component
			else
				AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
				return
			end
		end
		
		PrintOrdersDebugInfo("Recipe: " .. recipe.DisplayName.Value)

		local manager = character.AIController.ObjectiveManager

		
		--[[local operateItemObjective = AIObjectiveOperateItem(fabricator_component, character, manager, "fab", false)
		operateItemObjective.BasePriority = 10
		operateItemObjective.Repeat = false
		--operateItemObjective.completionCondition = function() return fabricator_component.state == 1 end
		operateItemObjective.completionCondition = function (a) return fabricator_component.state == 1 end
		--operateItemObjective.CanBeCompleted = true
		operateItemObjective.Completed.add(function ()
		
		--fabricator_componentState == 1 --FabricatorState.Active;
	
			TurnOnFabricator(fabricator_component, 1, target, character)
		
			if next(remaining_orders) then
				AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
			else
				local orderPrefab = OrderPrefab.Prefabs["wait"]
				local order = Order(orderPrefab, Identifier.Empty, nil, nil).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
				character.SetOrder(order, true, false, true)
				
				UpdateClientOrders(order, character, source, false)
			end
		end)
		
		manager.AddObjective(operateItemObjective)]]
		
		
		local gotoItemObjective = AIObjectiveGoTo(fabricator_to_use, character, manager)
		gotoItemObjective.BasePriority = 100
		
		gotoItemObjective.Completed.add(function ()
			--local operateItemObjective = AIObjectiveOperateItem(fabricator_component, character, manager, "fab", false)
		
			--manager.AddObjective(operateItemObjective)
			TurnOnFabricator(component_to_use, 1, recipe, character)
		
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
			--else
				--Wait(source, character, target, remaining_orders)
				--manager.AddObjective(operateItemObjective)
				--local orderPrefab = OrderPrefab.Prefabs["wait"]
				--local order = Order(orderPrefab, Identifier.Empty, nil, nil).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
				--character.SetOrder(order, true, false, true)
				
				--UpdateClientOrders(order, character, source, false)
		end)
		
		manager.AddObjective(gotoItemObjective)
	end

end


local function Operate(source, character, target, remaining_orders, first_order)
	-- Function used to see if anyone else is operating or ordered to operate an item.
	local function IsAnyoneElseOperatingItem(character, item_component)
		for key, other in pairs(Character.CharacterList) do
			if other ~= character then
				-- Check if a bot is already ordered to operate the turret.
				if other.IsBot then
					if other.TeamID == character.TeamID and other.IsHuman and not other.IsIncapacitated then
						if LuaUserData.IsTargetType(other.AIController.ObjectiveManager.GetActiveObjective(), "Barotrauma.AIObjectiveOperateItem") and other.AIController.ObjectiveManager.GetActiveObjective().operateTarget == item_component then
							return true
						end
					end
				-- Check if a player is operating the turret.
				elseif other.SelectedItem and other.SelectedItem.HasTag("periscope") then
					for turret_component in character.SelectedItem.GetConnectedComponents(Components.Turret) do
						if turret_component == item_component then
							return true
						end
					end
				end
					
					-- Check if a player is operating the reactor.
					--[[if other.SelectedItem.HasTag("reactor") then
						if turret_component == item_component then
							return true
						end
					end]]--
			end
		end
		
		return false
	end


	local found_target = nil
	
	if target ~= "unknown" then
		for key, value in pairs(Submarine.MainSub.GetItems(true)) do
			if string.find(string.lower(value.Prefab.Identifier.Value), target) then
			
				if value.HasTag("turret") and not IsAnyoneElseOperatingItem(character, value.GetComponentString("Turret")) then
					found_target = value
				end
				
				if value.HasTag("reactor") and not IsAnyoneElseOperatingItem(character, value.GetComponentString("Reactor")) then
					found_target = value
				end
			end
		end
	end

	if found_target then
		if found_target.HasTag("turret") then
			local orderPrefab = OrderPrefab.Prefabs["operateweapons"]
			local order = Order(orderPrefab, found_target, found_target.GetComponentString("Turret")).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
			SetOrder(order, character, source, first_order and not AI_NPC.Config.EnableChat)
		elseif found_target.HasTag("reactor") then
			local orderPrefab = OrderPrefab.Prefabs["operatereactor"]
			local order = Order(orderPrefab, "powerup", found_target, found_target.GetComponentString("Reactor")).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
			SetOrder(order, character, source, first_order and not AI_NPC.Config.EnableChat)
		end
	end
end

local function ReturnToSubmarine(source, character, target, remaining_orders, first_order)
	DismissOrders(character, true)
	
	--[[local orderPrefab = OrderPrefab.Prefabs["return"]
	local order = Order(orderPrefab, Identifier.Empty, nil, nil).WithManualPriority(CharacterInfo.HighestManualOrderPriority))
	character.SetOrder(order, true, false, true)]]--
	
	local manager = character.AIController.ObjectiveManager
	local returnObjective = AIObjectiveReturn(character, source, manager)
	
	returnObjective.Completed.add(function ()
		AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
	end)
	
	manager.AddObjective(returnObjective)
end

local function StoreItem(source, character, target, remaining_orders, first_order)
	local found_item = nil
	local priority = 0

	for item in character.Inventory.AllItems do
		if item.HasAccess(character) then
			local current_priority = 0

			-- Determine priority level.
			if string.lower(item.Name) == target or string.lower(item.Prefab.Identifier.Value) == target then
				found_item = item -- Exact match, no need to search further.
				break
			elseif string.find(string.lower(item.Name), target) and not item.HasTag("handheldammo") then
				current_priority = 2
			elseif item.HasTag(target) and not item.HasTag("handheldammo") then
				current_priority = 1 -- Lowest priority.
			end

			-- Update found item if this has higher priority.
			if current_priority > priority then
				found_item = item
				priority = current_priority
			end
		end
	end

	if found_item then
		PrintOrdersDebugInfo(found_item)
		found_item.DontCleanUp = false
		
		local manager = character.AIController.ObjectiveManager
		local cleanupObjective = AIObjectiveCleanupItem(found_item, character, manager)
		cleanupObjective.BasePriority = 100
		
		cleanupObjective.Completed.add(function ()
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
		end)
	
		cleanupObjective.Abandoned.add(function ()
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
		end)
		
		manager.AddObjective(cleanupObjective)
	else
		AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
	end
end

local function Rescue(source, character, target, remaining_orders, first_order)
	local found_target = nil
	
	if target == "me" then
		found_target = source
	end

	-- Find a character by name.
	if not found_target then
		for _, entity in pairs(Character.CharacterList) do
			if entity ~= character and entity.Submarine and Character.IsOnFriendlyTeam(character, entity) and character.Submarine.IsConnectedTo(entity.Submarine) then
				if string.find(string.lower(entity.Name), target) then
					found_target = entity
				end
			end
		end
	end
	
	-- Find a character by title.
	if not found_target then
		for _, entity in pairs(Character.CharacterList) do
			if entity ~= character and entity.Submarine and Character.IsOnFriendlyTeam(character, entity) and character.Submarine.IsConnectedTo(entity.Submarine) then
				if entity.Info.Title and string.find(string.lower(entity.Info.Title.Value), target) then
					found_target = entity
				end
			end
		end
	end

	if found_target then
		PrintOrdersDebugInfo(found_target)
		DismissOrders(character, true)
		
		local manager = character.AIController.ObjectiveManager
		local rescueObjective = AIObjectiveRescue(character, found_target, manager)
		rescueObjective.BasePriority = 100
		
		rescueObjective.Completed.add(function ()
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
		end)
		
		rescueObjective.Abandoned.add(function ()
			local orderPrefab = OrderPrefab.Prefabs["rescue"]
			local order = Order(orderPrefab, "rescue all", nil, nil).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
			SetOrder(order, character, source, first_order and not AI_NPC.Config.EnableChat)
			
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
		end)
		
		manager.AddObjective(rescueObjective)
	else
		local orderPrefab = OrderPrefab.Prefabs["rescue"]
		local order = Order(orderPrefab, "rescue all", nil, nil).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
		SetOrder(order, character, source, first_order and not AI_NPC.Config.EnableChat)
	
		AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
	end
end

-- Did not like the idea of the bots grabbing the wrong thing and deconstructing it.
--[[local AIObjectiveDeconstructItem = LuaUserData.CreateStatic("Barotrauma.AIObjectiveDeconstructItem")
local function DeconstructItem(source, character, target, remaining_orders, first_order)
	-- TODO: Prioritize ammo for a gun if already has gun?
	-- TODO: Ability to get an item if one is already in inventory?
	local found_items = {}
	
	if target ~= "unknown" then
		found_items = FindItemOnAnyFriendlySubmarine(character, target, true, false, false, false)
	end
	
	if #found_items > 0 then
		PrintOrdersDebugInfo(found_items[1].item)
		DismissOrders(character, true)
		local manager = character.AIController.ObjectiveManager

		-- Try to let the character find and get the closest item of the same type.
		--local getItemObjective = AIObjectiveGetItem(character, found_items[1].item.Prefab.Identifier, manager, true) --, true, 99, false)
		local deconstructItemObjective = AIObjectiveDeconstructItem(found_items[1].item, character, manager)
		deconstructItemObjective.BasePriority = 100
		
		-- If it successfully gets the item.
		deconstructItemObjective.Completed.add(function ()
			AI_NPC.Orders.ProcessNextOrder(source, character)
		end)
		
		-- If it abandons the objective, it's because it couldn't find the item. Possibly because it's on a station.
		deconstructItemObjective.Abandoned.add(function ()
			AI_NPC.Orders.ProcessNextOrder(source, character)
		end)
		
		manager.AddObjective(deconstructItemObjective)
	else
		AI_NPC.Orders.ProcessNextOrder(source, character)
	end
end]]--

-- Gives the character the Deconstruct marked items order.
local function DeconstructItem(source, character, target, remaining_orders, first_order)
	local orderPrefab = OrderPrefab.Prefabs["deconstructitems"]
	local order = Order(orderPrefab, Identifier.Empty, nil, nil).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
	SetOrder(order, character, source, first_order and not AI_NPC.Config.EnableChat)

	AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
end

-- Gives the character the Extinguish Fire order.
local function ExtinguishFires(source, character, target, remaining_orders, first_order)
	local orderPrefab = OrderPrefab.Prefabs["extinguishfires"]
	local order = Order(orderPrefab, Identifier.Empty, nil, nil).WithManualPriority(CharacterInfo.HighestManualOrderPriority)
	SetOrder(order, character, source, first_order and not AI_NPC.Config.EnableChat)

	AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
end

-- This only works for hospital beds, not regular beds.
--[[local function Rest(source, character, target, remaining_orders, first_order)
	local found_bed = nil
	local found_distance = 0
	local found_priority = 0

	for _, item in ipairs(Item.ItemList) do
		if character.Submarine and item.Submarine and character.IsOnFriendlyTeam(item.Submarine.TeamID) and not item.ParentInventory then
			-- Check if it's interactable, already being used, and not a prison bed.
			local item_identifier = string.lower(item.Prefab.Identifier.Value)
			local controller = item.GetComponent(Components.Controller)
			if item.IsInteractable(character) and (controller and controller.User == nil) and not string.find(item_identifier, "prison") then
				local bed_name = string.lower(item.Name)
				local current_priority = 0
				local current_distance = 0

				-- Determine priority level. Prioritize beds on the current submarine.	
				if item_identifier == "opdeco_hospitalbed" or (string.find(bed_name, "hospital") or string.find(item_identifier, "hospital")) then
					current_distance = AIObjective.GetDistanceFactor(character.WorldPosition, item.WorldPosition, 0.0, 5.0, 5000.0, 1.0)
					if character.Submarine == item.Submarine then
						current_priority = 4 -- Highest priority.
					else
						current_priority = 3
					end
				elseif string.find(bed_name, "bed") or string.find(bed_name, "bunk") or string.find(item_identifier, "bed") or string.find(item_identifier, "bunk") then
					current_distance = AIObjective.GetDistanceFactor(character.WorldPosition, item.WorldPosition, 0.0, 5.0, 5000.0, 1.0)
					if character.Submarine == item.Submarine then
						current_priority = 2.
					else
						current_priority = 1 -- Lowest priority.
					end
				end

				-- If they have the same priority, only update found_item if this one is closer.
				if current_priority == found_priority and found_distance > current_distance then
					found_bed = item
					found_priority = current_priority
					found_distance = current_distance
				-- Update found_item if this has higher priority.
				elseif current_priority > found_priority then
					found_bed = item
					found_distance = current_distance
					found_priority = current_priority
				end
			end
		end
	end

	if found_bed then
		PrintOrdersDebugInfo(found_bed)
		DismissOrders(character, true)
		local manager = character.AIController.ObjectiveManager
		local gotoObjective = AIObjectiveGoTo(found_bed, character, manager)
		gotoObjective.BasePriority = 100
		
		gotoObjective.Completed.add(function ()
			found_bed.TryInteract(character, false, true, false);
			--Wait(source, character, remaining_orders)
		end)
		
		gotoObjective.Abandoned.add(function ()
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
		end)	
		
		manager.AddObjective(gotoObjective)
	end
end]]--

-- This order doesn't seem to do anything.
--[[LuaUserData.RegisterType("Barotrauma.AIObjectiveInspectNoises")
local AIObjectiveInspectNoises = LuaUserData.CreateStatic("Barotrauma.AIObjectiveInspectNoises", true)
local function IdentifyNoise(source, character, target, remaining_orders, first_order)
	DismissOrders(character, true)
	
	local manager = character.AIController.ObjectiveManager
	local inspectNoiseObjective = AIObjectiveInspectNoises(character, manager, 1)
	inspectNoiseObjective.Priority = 100
	inspectNoiseObjective.Completed.add(function ()
		AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
	end)
	
	inspectNoiseObjective.Abandoned.add(function ()
		AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
	end)
	
	manager.AddObjective(inspectNoiseObjective)
end]]--

--LuaUserData.MakePropertyAccessible(Descriptors["Barotrauma.AIObjectiveGetItem"], "Abandoned")
--LuaUserData.RegisterType("System.MulticastDelegate")
--LuaUserData.RegisterType("System.Action")
-- Cancels all orders and current object. Deletes remaining orders/objectives in queue.
local function CancelOrders(source, character, target, remaining_orders, first_order)
	--AI_NPC.Orders.OrdersQueue[character.Info.GetIdentifierUsingOriginalName()] = {}
	--print("canceling order")
	DismissOrders(character, false)
	
	--print("abandoning objective")
	local manager = character.AIController.ObjectiveManager
	local currentObjective = manager.GetCurrentObjective()
	if currentObjective then
		--print("setting abandon")
		--currentObjective.Abandoned = nil
		--currentObjective.Abandoned.add(function () print("new abandon") end)
		--print(currentObjective.Abandoned.GetInvocationList())
		currentObjective.Abandon = true
	end
	
	--AI_NPC.Orders.ProcessNextOrder(source, character)
end

function AI_NPC.Orders.ProcessOrder(source, character, remaining_orders, first_order)
	
	--[[local manager = character.AIController.ObjectiveManager
	local idleObjective = manager.GetObjective(AIObjectiveIdle)
	if idleObjective then
		print("test")
		idleObjective.Priority = 0
		--idleObjective.Behavior = AIObjectiveIdle.BehaviorType.StayInHull
		--idleObjective.TargetHull = character.CurrentHull
		--idleObjective.AllowAutomaticItemUnequipping = false
		--idleObjective.SetTargetTimerHigh()
		--idleObjective.Reset()
	end]]--
	

	if not next(remaining_orders) then
		return ""
	end

	local order = string.upper(remaining_orders[1].order)
	local target = string.lower(remaining_orders[1].target)

	PrintOrdersDebugInfo("Order: " .. (order or "") .. ", Target: " .. (target or ""))
	table.remove(remaining_orders, 1)

	-- If the message was not an order or no matching order type was found.
	if order == "UNKNOWN" then
		return ""
	end

	if order == "REPAIR" and not character.LockHands then
		Repair(source, character, target, remaining_orders, first_order)
	elseif order == "GET" and target and not character.LockHands then
		GetItem(source, character, target, remaining_orders, first_order)
	elseif order == "FOLLOW" and target then
		Follow(source, character, target, remaining_orders, first_order)
	elseif order == "GOTO" and target then
		GoTo(source, character, target, remaining_orders, first_order)
	elseif order == "FIGHT" then
		Fight(source, character, target, remaining_orders, first_order)
	elseif order == "DROP" and target and not character.LockHands then
		DropItem(source, character, target, remaining_orders, first_order)
	elseif order == "GIVE_ME" and target and not character.LockHands then
		GiveItem(source, character, target, remaining_orders, first_order)
	--elseif order == "BRING" and target then
	--	table.insert(remaining_orders, 1, {order = "GET", target = target})
	--	table.insert(remaining_orders, 2, {order = "GIVE_ME", target = target})
	--	AI_NPC.Orders.ProcessOrder(source, character, remaining_orders)
	elseif order == "CRAFT" and target and not character.LockHands then
		Fabricate(source, character, target, remaining_orders, first_order)
	elseif order == "WAIT" then
		Wait(source, character, target, remaining_orders, first_order)
	elseif order == "OPERATE" and target and not character.LockHands then
		Operate(source, character, target, remaining_orders, first_order)
	elseif order == "GO_TO_SUBMARINE" then
		ReturnToSubmarine(source, character, target, remaining_orders, first_order)
	elseif order == "STORE" and target and not character.LockHands then
		StoreItem(source, character, target, remaining_orders, first_order)
	elseif order == "RESCUE" and target then
		Rescue(source, character, target, remaining_orders, first_order)
	elseif order == "DECONSTRUCT" and not character.LockHands then
		DeconstructItem(source, character, target, remaining_orders, first_order)
	elseif order == "EXTINGUISH_FIRE" and not character.LockHands then
		ExtinguishFires(source, character, target, remaining_orders, first_order)
	--elseif order == "REST" then
	--	Rest(source, character, target, remaining_orders, first_order)
	--elseif order == "IDENTIFY_NOISE" then
	--	IdentifyNoise(source, character, target, remaining_orders, first_order)
	else
		if next(remaining_orders) then
			AI_NPC.Orders.ProcessOrder(source, character, remaining_orders, false)
		else
			return ""
		end
	end
	
	--return ", it contains an order that you will accept and then strive to achieve"
	return ", it contains an order that,in this instance, you will accept and then strive to achieve"
end

local function AssignOrder(source, character, msg, chatType, res)
	local message = Utils.GetAPIResponse(res)
	local OrderInfo = ""
	
	if #message > 0 then
		local messages = {}
		-- Split the message into lines and store them in the messages table
		for line in message:gmatch("[^\r\n]+") do
			table.insert(messages, line)
		end

		-- Initialize the orders table
		local orders = {}
		
		-- Process each line to extract the order and target
		for _, line in ipairs(messages) do
			local words = {}
			
			line = Utils.RemoveArticles(line):gsub("[%[%]<>]", "")
			
			-- Split the line into words
			for word in line:gmatch("%S+") do
				table.insert(words, word)
			end

			-- Extract the order and target
			local order = words[1]
			local target = words[2] and string.lower(words[2]) or "unknown"
			local target_type = words[3] and string.lower(words[3]) or "unknown"
			-- Store the order and target in the orders table
			table.insert(orders, {order = order, target = target})
		end
		
		-- Got rid of the wait because I wanted to be able to use the return value in the chat prompt.
		---- Process the first order. Wait a little bit so it's not instant.
		----local randomMilliseconds = math.random(1000, 3000)
		----Timer.Wait(function () AI_NPC.Orders.ProcessOrder(source, character, orders) end, randomMilliseconds)
		OrderInfo = AI_NPC.Orders.ProcessOrder(source, character, orders, true)
	end
	
	if AI_NPC.Config.EnableChat then
		AI_NPC.Globals.ProcessPlayerSpeach(source, character, msg, chatType, OrderInfo)
	end
end

function AI_NPC.Orders.DetermineOrder(source, character, msg, chatType)
	local prompt_header = ""
	if #AI_NPC.Config.OrderInstructions > 0 then
		prompt_header = AI_NPC.Config.OrderInstructions
	else
		-- Default prompt.
		prompt_header = [[Task:
Analyze the message and identify actions from these predefined types:
- FIGHT <target>
- FOLLOW [target]
- REPAIR <target>
- GET [item]
- GOTO [target]
- DROP [item]
- GIVE_ME [item]
- CRAFT [item]
- WAIT <seconds>
- OPERATE [turret or reactor]
- GO_TO_SUBMARINE
- STORE [item]
- RESCUE <target>
- DECONSTRUCT
- EXTINGUISH_FIRE

Guidelines:
1. Format: Respond with the exact action followed by its parameter (if any). Use uppercase. Required parameters are in [ ], optional ones in < >.
   - Unknown parameters → UNKNOWN
   - E.g., "Fix it" → REPAIR UNKNOWN
2. Multiple Actions: For multiple actions or parameters, output each step on a new line.
3. Unknown or Complex Actions:
   - Break unknown actions into one or more predefined actions (e.g., "Bring me X" → GET X, GIVE_ME X).
   - For requests giving (GIVE_ME) multiple items, retrieve (GET) each item before executing GIVE_ME.
4. Ignore: Ignore temporal cues (e.g., "quickly") and casual phrases (e.g., "please").
5. Clarify Ambiguity: If unclear, replace references like "it" or "that" with UNKNOWN.

Examples:
- "bring me an SMG, 2 shotguns, and knife and then get a revolver and go to the command room"
  GET smg
  GET shotgun
  GET shotgun
  GET knife
  GIVE_ME smg
  GIVE_ME shotgun
  GIVE_ME shotgun
  GIVE_ME knife
  GET revolver
  GOTO command

- "Fix the engine and follow John"
  REPAIR engine
  FOLLOW john

- "Come here!"
  GOTO me
  
- "follow me"
  FOLLOW me
  
- "Wait at the airlock for a few seconds."
  GOTO airlock
  WAIT 3

- "help"
  RESCUE me
  
- "wait here"
  GOTO me
  WAIT

Message: ]]
	end
	
	local prompt = prompt_header .. "\"" .. msg .. "\""
	
	local OrdersJSONData = AI_NPC.Globals.GetPromptJSON(prompt)

	File.Write(AI_NPC.Path .. "/Last_Prompt_Orders.txt", prompt)
	local savePath = AI_NPC.Path .. "/HTTP_Response_Orders.txt" -- Save HTTP response to a file for debugging purposes.
	if Utils.ValidateAPISettings() then
		Networking.HttpPost(AI_NPC.Config.APIEndpoint, function(res) AssignOrder(source, character, msg, chatType, res) end, OrdersJSONData, "application/json", { ["Authorization"] = "Bearer " .. AI_NPC.Config.APIKey }, savePath)
	end
end