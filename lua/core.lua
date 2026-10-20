if WeaponDamageControl then
	return
end

WeaponDamageControl = {
	save_path = SavePath .. "WeaponDamageControl.json",
	-- checked in this order, first match wins
	categories = { "revolver", "pistol", "smg", "assault_rifle", "shotgun", "lmg", "snp", "bow", "crossbow", "flamethrower", "grenade_launcher", "saw", "minigun", "other" },
	-- configured weapons on first run, before a save file exists
	defaults = {
		amcar = 1.8, new_mp5 = 1.5, mac10 = 1.5, mp9 = 1.5, new_m4 = 1.3,
		glock_17 = 1.6, b92fs = 1.6, c45 = 1.4, colt_1911 = 1.4, r870 = 1.2
	},
	settings = {
		enabled = true,
		weapons = {}
	}
}

function WeaponDamageControl:load()
	local file = io.open(self.save_path, "r")
	if not file then
		for id, mul in pairs(self.defaults) do
			self.settings.weapons[id] = mul
		end
		return
	end
	local ok, data = pcall(json.decode, file:read("*all"))
	file:close()
	if not ok or type(data) ~= "table" then
		return
	end
	if data.enabled ~= nil then
		self.settings.enabled = data.enabled
	end
	if type(data.weapons) == "table" then
		for id, mul in pairs(data.weapons) do
			if tonumber(mul) then
				self.settings.weapons[id] = tonumber(mul)
			end
		end
	end
end

function WeaponDamageControl:save()
	local file = io.open(self.save_path, "w+")
	if file then
		file:write(json.encode(self.settings))
		file:close()
	end
end

function WeaponDamageControl:get_multiplier(weapon_id)
	return self.settings.weapons[weapon_id] or 1
end

-- Damage stat as shown in the weapon stats, or nil if the weapon has none
function WeaponDamageControl:get_base_damage(weapon_id)
	local td = tweak_data.weapon[weapon_id]
	return td and td.stats and td.stats.damage
end

-- Player weapons only: skips NPC/crew variants and non-weapon entries of the tweak table
function WeaponDamageControl:is_player_weapon(weapon_id, td)
	return type(td) == "table" and type(td.stats) == "table" and type(td.use_data) == "table"
		and td.categories ~= nil and not weapon_id:find("_npc$") and not weapon_id:find("_crew$")
end

function WeaponDamageControl:get_category(td)
	for _, cat in ipairs(self.categories) do
		if cat ~= "other" and table.contains(td.categories, cat) then
			return cat
		end
	end
	return "other"
end

WeaponDamageControl:load()
