dofile(ModPath .. "lua/core.lua")

local orig_get_current_damage = RaycastWeaponBase._get_current_damage

if orig_get_current_damage then
	function RaycastWeaponBase:_get_current_damage(...)
		local damage = orig_get_current_damage(self, ...)
		if WeaponDamageControl.settings.enabled and self._name_id then
			damage = damage * WeaponDamageControl:get_multiplier(self._name_id)
		end
		return damage
	end
else
	log("[WeaponDamageControl] RaycastWeaponBase._get_current_damage not found, damage is not modified")
end
