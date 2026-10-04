class_name Weapon
extends RefCounted
## Base for main weapons and sub-weapons. Weapons read the player's movement each frame
## and call into the HuntContext to hit things.

var id: String = ""
var display_name: String = ""
var hunt: HuntContext
var player: Player
var level: int = 1             ## sub-weapon level (1..5)
var upgrades: Dictionary = {}  ## main-weapon upgrade id -> level
var upgrade_defs: Array = []   ## from tuning


func setup(p_hunt: HuntContext, p_player: Player) -> void:
	hunt = p_hunt
	player = p_player


func update(dt: float, move: Vector2) -> void:
	pass


func up(upgrade_id: String) -> int:
	return int(upgrades.get(upgrade_id, 0))


func upgrade_def(upgrade_id: String) -> Dictionary:
	for d: Dictionary in upgrade_defs:
		if String(d["id"]) == upgrade_id:
			return d
	return {}


## Per-level magnitude from tuning, times current level.
func up_value(upgrade_id: String) -> float:
	var d := upgrade_def(upgrade_id)
	return float(d.get("per_level", 0.0)) * up(upgrade_id)


func apply_upgrade(upgrade_id: String) -> void:
	upgrades[upgrade_id] = up(upgrade_id) + 1


## Drawn in the player's local space (indicator rings, orbiting blades).
func draw_local(ci: CanvasItem) -> void:
	pass


## Drawn in world space under the swarm (trails, burning ground).
func draw_world_under(ci: CanvasItem) -> void:
	pass


## Multiplier on damage the hunter takes (Great Sword's planted stance reduces it).
func damage_taken_mult() -> float:
	return 1.0


func dmg(base: float) -> float:
	return base * hunt.damage_mult()
