class_name Weapon
extends RefCounted
## Base for main weapons and sub-weapons. Weapons read the player's movement each frame
## and call into the HuntContext to hit things. Main weapons also implement gesture moves
## (`perform_move`); the shared moves every weapon can bind (roll, lightning) live here.

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


## Final say on incoming damage; `from` is where it came from (Bulwark blocks frontal hits).
func modify_incoming(amount: float, from: Vector2) -> float:
	return amount * damage_taken_mult()


func dmg(base: float) -> float:
	return base * hunt.damage_mult()


# ---------------------------------------------------------------- gesture moves
# ctx keys: kind, dir (unit, world), aimed (the stroke chose dir), target (auto-aim point or
# Vector2.INF), hold_time, power (level x perfect multiplier), perfect, level, move.

## Runs a move; returns false if it can't fire right now (no cooldown is spent).
func perform_move(move_id: String, def: Dictionary, ctx: Dictionary) -> bool:
	match move_id:
		"roll":
			var dir: Vector2 = ctx["dir"] if bool(ctx["aimed"]) else player.move_dir
			var dur := float(def["duration"])
			player.start_dash(dir, float(def["distance"]), dur)
			player.iframes = maxf(player.iframes, dur + 0.15)
			hunt.fx_under.line(player.position, player.position + dir * float(def["distance"]), 18.0, "fx.trail", 0.25)
			return true
		"lightning":
			var p := target_point(ctx, float(def["reach"]))
			var bonus := 1.0 + float(def["per_thunder_level"]) * hunt.sub_level("thunder_call")
			var r := float(def["radius"]) * player.area_mult
			hunt.hit_circle(p, r, move_dmg(def, "damage", ctx) * bonus, 260.0, HuntContext.HIT_BIG)
			hunt.fx_over.bolt(p, r, "fx.bolt")
			hunt.fx_under.circle(p, r, "fx.bolt", 0.3)
			hunt.add_shake(0.2)
			return true
	return false


## Called when a hold is detected for the move bound to "hold" (finger still down).
func begin_hold(move_id: String, def: Dictionary, ctx: Dictionary) -> void:
	pass


## The held gesture ended without firing (pause, level-up, released on cooldown).
func cancel_hold() -> void:
	pass


## Move damage: tuning value x passives/outposts x move level/perfect power.
func move_dmg(def: Dictionary, key: String, ctx: Dictionary) -> float:
	return dmg(float(def[key])) * float(ctx.get("power", 1.0))


## Where an aimed move lands: along the stroke when aimed, else the auto-aim target if it is
## within reach, else straight ahead.
func target_point(ctx: Dictionary, reach: float) -> Vector2:
	var dir: Vector2 = ctx["dir"]
	if bool(ctx["aimed"]):
		return player.position + dir * reach
	var t: Vector2 = ctx["target"]
	if t != Vector2.INF and t.distance_to(player.position) <= reach * 1.5:
		return t
	return player.position + dir * reach
