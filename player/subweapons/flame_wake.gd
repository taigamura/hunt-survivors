class_name FlameWake
extends Weapon
## Drops burning ground every `step` px travelled — the faster you move, the more fire.

var levels: Array = []
var patches: GroundPatches
var _travel: float = 0.0
var _last_pos: Vector2 = Vector2.INF


func _init() -> void:
	id = "flame_wake"


func setup(p_hunt: HuntContext, p_player: Player) -> void:
	super.setup(p_hunt, p_player)
	var cfg := Tuning.d("subweapons.flame_wake")
	display_name = String(cfg["name"])
	levels = cfg["levels"]
	patches = GroundPatches.new(int(cfg["cap"]), float(cfg["tick"]))


func cfg() -> Dictionary:
	return levels[clampi(level, 1, levels.size()) - 1]


func update(dt: float, move: Vector2) -> void:
	var c := cfg()
	if _last_pos == Vector2.INF:
		_last_pos = player.position
	_travel += player.position.distance_to(_last_pos)
	_last_pos = player.position
	var step := float(c["step"])
	if _travel >= step:
		_travel = fmod(_travel, step)
		patches.add(player.position, float(c["radius"]) * player.area_mult, float(c["life"]), dmg(float(c["damage"])))
	patches.update(dt, hunt)


func draw_world_under(ci: CanvasItem) -> void:
	patches.draw_flames(ci)
