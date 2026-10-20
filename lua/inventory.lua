dofile(ModPath .. "lua/core.lua")

local function multiplier(weapon_id)
	if not WeaponDamageControl.settings.enabled or type(weapon_id) ~= "string" then
		return 1
	end
	return WeaponDamageControl:get_multiplier(weapon_id)
end

-- Stats card of the inventory and weapon modification screens, and the details card of Better Weapon Preview.
-- All of them get their numbers from WeaponDescription._get_stats, which returns the base, attachment and skill
-- tables. Each table is scaled, so the total is (base + attachments + skills) * multiplier like in a mission.
local function scale_damage(stats, mul)
	local damage = type(stats) == "table" and stats.damage
	if type(damage) == "table" and tonumber(damage.value) then
		damage.value = damage.value * mul
	elseif type(damage) == "number" then
		stats.damage = damage * mul
	end
end

local installed = false

local function hook_weapon_description()
	local wd = rawget(_G, "WeaponDescription")
	if installed or not wd then
		return
	end
	installed = true

	if wd._get_stats then
		local orig_get_stats = wd._get_stats
		function wd._get_stats(name, ...)
			local base, mods, skill = orig_get_stats(name, ...)
			local mul = multiplier(name)
			if mul ~= 1 then
				scale_damage(base, mul)
				scale_damage(mods, mul)
				scale_damage(skill, mul)
			end
			return base, mods, skill
		end
	else
		log("[WeaponDamageControl] WeaponDescription._get_stats not found, stats cards are not modified")
	end

	-- damage change shown per attachment in the weapon modification screen
	if wd.get_stats_for_mod then
		local orig_get_stats_for_mod = wd.get_stats_for_mod
		function wd.get_stats_for_mod(mod_name, weapon_name, ...)
			local result = orig_get_stats_for_mod(mod_name, weapon_name, ...)
			local mul = multiplier(weapon_name)
			if mul ~= 1 and type(result) == "table" then
				for _, key in ipairs({ "chosen", "equip" }) do
					scale_damage(result[key], mul)
				end
			end
			return result
		end
	end
end

hook_weapon_description()
-- WeaponDescription may not exist yet when this file loads, so try again when the screen opens
if not installed and BlackMarketGui then
	Hooks:PreHook(BlackMarketGui, "_setup", "WeaponDamageControl_hook_description", hook_weapon_description)
end

-- More Weapon Stats and Better Weapon Preview read the damage of a simulated weapon (Faker)
local function hook_faker()
	local faker = rawget(_G, "Faker")
	if not faker or not faker.make_weapon_base or faker.wdc_hooked then
		return
	end
	faker.wdc_hooked = true

	local orig_make_weapon_base = faker.make_weapon_base
	function faker:make_weapon_base(factory_id, blueprint, name_id, npc, ...)
		local wbase = orig_make_weapon_base(self, factory_id, blueprint, name_id, npc, ...)
		local mul = npc and 1 or multiplier(name_id)
		if wbase and tonumber(wbase._damage) and mul ~= 1 then
			wbase._damage = wbase._damage * mul
		end
		return wbase
	end
end

hook_faker()
