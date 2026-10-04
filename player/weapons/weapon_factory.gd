class_name WeaponFactory
extends RefCounted
## Main weapon id -> instance. Ids match `weapons.*` in tuning and GameState.WEAPONS.


static func make(weapon_id: String) -> Weapon:
	match weapon_id:
		"dual_blades":
			return DualBlades.new()
		"sword_shield":
			return SwordShield.new()
		"pistol":
			return Pistol.new()
		"dual_pistols":
			return DualPistols.new()
		"assault_rifle":
			return AssaultRifle.new()
	return GreatSword.new()
