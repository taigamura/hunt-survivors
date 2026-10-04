class_name OrbitShards
extends Weapon
## Blades orbiting the hunter; each shard hits what it touches every `tick`.

var levels: Array = []
var tick: float = 0.22
var angle: float = 0.0
var _tick_timer: float = 0.0
var hits: int = 0


func _init() -> void:
	id = "orbit_shards"


func setup(p_hunt: HuntContext, p_player: Player) -> void:
	super.setup(p_hunt, p_player)
	var cfg := Tuning.d("subweapons.orbit_shards")
	display_name = String(cfg["name"])
	levels = cfg["levels"]
	tick = float(cfg["tick"])


func cfg() -> Dictionary:
	return levels[clampi(level, 1, levels.size()) - 1]


func shard_positions() -> PackedVector2Array:
	var c := cfg()
	var n := int(c["count"])
	var r := float(c["radius"]) * player.area_mult
	var out := PackedVector2Array()
	for k in n:
		out.append(player.position + Vector2.from_angle(angle + TAU * k / n) * r)
	return out


func update(dt: float, move: Vector2) -> void:
	var c := cfg()
	angle += float(c["spin"]) * dt
	_tick_timer -= dt * player.haste_mult
	if _tick_timer <= 0.0:
		_tick_timer = tick
		var hr := float(c["hit_radius"]) * player.area_mult
		for p in shard_positions():
			hits += hunt.hit_circle(p, hr, dmg(float(c["damage"])), 140.0)


func draw_local(ci: CanvasItem) -> void:
	var c := cfg()
	var n := int(c["count"])
	var r := float(c["radius"]) * player.area_mult
	var col := ArtRegistry.color("fx.shard")
	for k in n:
		var a := angle + TAU * k / n
		var p := Vector2.from_angle(a) * r
		var t := Vector2.from_angle(a + PI * 0.5)
		var nrm := Vector2.from_angle(a)
		var poly := PackedVector2Array([p + t * 16.0, p + nrm * 6.0, p - t * 10.0, p - nrm * 6.0])
		ci.draw_colored_polygon(poly, col)
		ci.draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color(0, 0, 0, 0.6), 1.5)
