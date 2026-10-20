dofile(ModPath .. "lua/core.lua")

-- ModPath is only valid while this file is executing, so keep a copy for the callbacks
local mod_path = ModPath

local main_menu_id = "wdc_menu"
local configured_menu_id = "wdc_configured_menu"
local add_menu_id = "wdc_add_menu"
local add_cat_prefix = "wdc_add_cat_"
local add_item_prefix = "wdc_add_"
local slider_prefix = "wdc_cfg_s_"
local remove_prefix = "wdc_cfg_r_"

-- this file loads after the LocalizationManager is created, so add the strings directly
local function load_localization()
	local file = io.open(mod_path .. "loc/en.txt", "r")
	if not file then
		return
	end
	local ok, strings = pcall(json.decode, file:read("*all"))
	file:close()
	if ok and type(strings) == "table" then
		managers.localization:add_localized_strings(strings)
	end
end

local function weapon_name(id)
	local td = tweak_data.weapon[id]
	local loc = managers.localization
	if td and td.name_id and loc:exists(td.name_id) then
		return loc:text(td.name_id)
	end
	return id
end

-- weapon ids grouped by category, each group sorted by display name
local function collect_weapons()
	local groups = {}
	for id, td in pairs(tweak_data.weapon) do
		if WeaponDamageControl:is_player_weapon(id, td) then
			local cat = WeaponDamageControl:get_category(td)
			groups[cat] = groups[cat] or {}
			table.insert(groups[cat], { id = id, name = weapon_name(id) })
		end
	end
	for _, list in pairs(groups) do
		table.sort(list, function(a, b)
			if a.name ~= b.name then
				return a.name < b.name
			end
			return a.id < b.id
		end)
	end
	return groups
end

local function damage_text(id, mul)
	local base = WeaponDamageControl:get_base_damage(id)
	if not base then
		return string.format("x%.2f", mul)
	end
	return string.format("%d -> %d (x%.2f)", base, math.floor(base * mul + 0.5), mul)
end

local function slider_title(id, mul)
	return weapon_name(id) .. "  |  " .. damage_text(id, mul)
end

-- Changes the label of an item that is currently on screen
local function set_item_text(item, text)
	item:parameters().text_id = text
	pcall(function()
		local menu = managers.menu:active_menu()
		local node_gui = menu and menu.renderer and menu.renderer:active_node_gui()
		for _, row_item in ipairs(node_gui and node_gui.row_items or {}) do
			if row_item.item == item and row_item.gui_text then
				row_item.gui_text:set_text(row_item.to_upper and utf8.to_upper(text) or text)
			end
		end
	end)
end

local groups, configured_node

-- Recreates the slider + remove button of every configured weapon
local function rebuild_configured()
	local node = configured_node
	if not node then
		return
	end

	local kept = {}
	for _, item in ipairs(node._items) do
		if not item:name():find("^wdc_cfg_") then
			table.insert(kept, item)
		end
	end
	node._items = kept

	local ids = {}
	for id in pairs(WeaponDamageControl.settings.weapons) do
		if tweak_data.weapon[id] then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		local name_a, name_b = weapon_name(a), weapon_name(b)
		if name_a ~= name_b then
			return name_a < name_b
		end
		return a < b
	end)

	local slider_data = {
		type = "CoreMenuItemSlider.ItemSlider",
		min = 0.1, max = 5, step = 0.05, show_value = true,
		decimal_count = 2, show_scale = 1, is_scaled = false, is_percentage = false
	}
	for _, id in ipairs(ids) do
		local mul = WeaponDamageControl:get_multiplier(id)
		local slider = node:create_item(slider_data, {
			name = slider_prefix .. id, text_id = slider_title(id, mul), help_id = "wdc_weapon_desc",
			callback = "wdc_set_weapon", disabled_color = Color(0.25, 1, 1, 1),
			localize = false, localize_help = true
		})
		slider:set_value(math.clamp(mul, slider_data.min, slider_data.max))
		slider:parameters().wdc_weapon_id = id
		node:add_item(slider)

		local remove = node:create_item({ type = "CoreMenuItem.Item" }, {
			name = remove_prefix .. id, text_id = "    " .. managers.localization:text("wdc_remove") .. " " .. weapon_name(id),
			callback = "wdc_remove_weapon", disabled_color = Color(0.25, 1, 1, 1),
			localize = false
		})
		remove:parameters().wdc_weapon_id = id
		node:add_item(remove)
	end

	-- keep the back button last
	for i, item in ipairs(node._items) do
		if item:name() == "back" then
			table.remove(node._items, i)
			table.insert(node._items, item)
			break
		end
	end

	pcall(function()
		local active = managers.menu:active_menu()
		if active and active.logic then
			active.logic:refresh_node(configured_menu_id, true)
		end
	end)
end

Hooks:Add("MenuManagerSetupCustomMenus", "WeaponDamageControl_setup", function()
	load_localization()
	groups = collect_weapons()
	MenuHelper:NewMenu(main_menu_id)
	MenuHelper:NewMenu(configured_menu_id)
	MenuHelper:NewMenu(add_menu_id)
	for _, cat in ipairs(WeaponDamageControl.categories) do
		if groups[cat] then
			MenuHelper:NewMenu(add_cat_prefix .. cat)
		end
	end
end)

Hooks:Add("MenuManagerPopulateCustomMenus", "WeaponDamageControl_populate", function()
	local wdc = WeaponDamageControl
	local s = wdc.settings

	MenuCallbackHandler.wdc_toggle_enabled = function(self, item)
		s.enabled = item:value() == "on"
		wdc:save()
	end
	MenuCallbackHandler.wdc_set_weapon = function(self, item)
		local id = item:parameters().wdc_weapon_id
		local mul = math.floor(item:value() * 100 + 0.5) / 100
		s.weapons[id] = mul
		set_item_text(item, slider_title(id, mul))
		wdc:save()
	end
	MenuCallbackHandler.wdc_remove_weapon = function(self, item)
		s.weapons[item:parameters().wdc_weapon_id] = nil
		wdc:save()
		rebuild_configured()
	end
	MenuCallbackHandler.wdc_add_weapon = function(self, item)
		local id = item:parameters().wdc_weapon_id
		if s.weapons[id] then
			return
		end
		s.weapons[id] = 1
		wdc:save()
		set_item_text(item, "[+] " .. weapon_name(id))
		rebuild_configured()
	end

	MenuHelper:AddToggle({
		id = "wdc_enabled", title = "wdc_enabled_title", desc = "wdc_enabled_desc",
		callback = "wdc_toggle_enabled", value = s.enabled, menu_id = main_menu_id, priority = 100
	})

	for _, cat in ipairs(wdc.categories) do
		for i, weapon in ipairs(groups[cat] or {}) do
			local base = wdc:get_base_damage(weapon.id)
			MenuHelper:AddButton({
				id = add_item_prefix .. weapon.id,
				title = (s.weapons[weapon.id] and "[+] " or "") .. weapon.name,
				desc = base and ("Damage: " .. base) or weapon.id, localized = false,
				callback = "wdc_add_weapon", menu_id = add_cat_prefix .. cat, priority = 1000 - i
			})
		end
	end
end)

Hooks:Add("MenuManagerBuildCustomMenus", "WeaponDamageControl_build", function(menu_manager, nodes)
	local wdc = WeaponDamageControl

	nodes[main_menu_id] = MenuHelper:BuildMenu(main_menu_id)
	nodes[configured_menu_id] = MenuHelper:BuildMenu(configured_menu_id)
	nodes[add_menu_id] = MenuHelper:BuildMenu(add_menu_id)
	configured_node = nodes[configured_menu_id]

	for _, cat in ipairs(wdc.categories) do
		if groups[cat] then
			local menu_id = add_cat_prefix .. cat
			nodes[menu_id] = MenuHelper:BuildMenu(menu_id)
			-- remember which weapon each button belongs to
			for _, item in ipairs(nodes[menu_id]:items()) do
				local name = item:name()
				if name:sub(1, #add_item_prefix) == add_item_prefix then
					item:parameters().wdc_weapon_id = name:sub(#add_item_prefix + 1)
				end
			end
			MenuHelper:AddMenuItem(nodes[add_menu_id], menu_id, "wdc_cat_" .. cat, "wdc_cat_desc")
		end
	end

	MenuHelper:AddMenuItem(nodes[main_menu_id], configured_menu_id, "wdc_configured_title", "wdc_configured_desc")
	MenuHelper:AddMenuItem(nodes[main_menu_id], add_menu_id, "wdc_add_title", "wdc_add_desc")
	MenuHelper:AddMenuItem(nodes.blt_options, main_menu_id, "wdc_menu_title", "wdc_menu_desc")

	rebuild_configured()
end)
