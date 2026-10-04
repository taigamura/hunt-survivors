class_name Outposts
extends RefCounted
## Capturable zones. Stand inside for `capture_time` to capture (progress drains if you leave).
## Captured outposts suppress nearby spawns, heal the hunter inside, and add a damage bonus.

var positions: Array[Vector2] = []
var progress := PackedFloat32Array()
var captured := PackedByteArray()
var radius: float = 150.0
var capture_time: float = 4.0
var decay_rate: float = 1.5
var suppress_radius: float = 1300.0
var suppress_mult: float = 0.35
var bonus_each: float = 0.10
var heal_per_sec: float = 6.0


func setup(p_positions: Array[Vector2] = []) -> void:
	radius = Tuning.f("outposts.radius", 150.0)
	capture_time = Tuning.f("outposts.capture_time", 4.0)
	decay_rate = Tuning.f("outposts.decay_rate", 1.5)
	suppress_radius = Tuning.f("outposts.suppress_radius", 1300.0)
	suppress_mult = Tuning.f("outposts.suppress_mult", 0.35)
	bonus_each = Tuning.f("outposts.damage_bonus_each", 0.1)
	heal_per_sec = Tuning.f("player.outpost_heal_per_sec", 6.0)
	positions = p_positions
	if positions.is_empty():
		for v: Variant in Tuning.a("map.outposts"):
			var arr: Array = v
			positions.append(Vector2(float(arr[0]), float(arr[1])))
	progress.resize(positions.size())
	progress.fill(0.0)
	captured.resize(positions.size())
	captured.fill(0)


func inside_index(p: Vector2) -> int:
	for k in positions.size():
		if p.distance_squared_to(positions[k]) <= radius * radius:
			return k
	return -1


## Returns the index captured this frame, or -1.
func update(dt: float, player_pos: Vector2) -> int:
	var inside := inside_index(player_pos)
	var newly := -1
	for k in positions.size():
		if captured[k] != 0:
			continue
		if k == inside:
			progress[k] = minf(capture_time, progress[k] + dt)
			if progress[k] >= capture_time:
				captured[k] = 1
				newly = k
		else:
			progress[k] = maxf(0.0, progress[k] - decay_rate * dt)
	return newly


func is_captured(k: int) -> bool:
	return captured[k] != 0


func captured_count() -> int:
	var n := 0
	for k in captured.size():
		if captured[k] != 0:
			n += 1
	return n


func damage_bonus() -> float:
	return bonus_each * captured_count()


## Heal per second while inside a captured outpost (0 otherwise).
func heal_rate_at(p: Vector2) -> float:
	var k := inside_index(p)
	return heal_per_sec if k >= 0 and captured[k] != 0 else 0.0


## Spawn-rate multiplier at a world point (captured outposts suppress their area).
func spawn_mult_at(p: Vector2) -> float:
	for k in positions.size():
		if captured[k] != 0 and p.distance_squared_to(positions[k]) <= suppress_radius * suppress_radius:
			return suppress_mult
	return 1.0


func draw(ci: CanvasItem) -> void:
	var neutral := ArtRegistry.color("outpost.neutral")
	var cap_col := ArtRegistry.color("outpost.captured")
	var prog_col := ArtRegistry.color("outpost.progress")
	for k in positions.size():
		var p := positions[k]
		var col := cap_col if captured[k] != 0 else neutral
		ci.draw_circle(p, radius, Color(col.r, col.g, col.b, 0.10))
		ci.draw_arc(p, radius, 0.0, TAU, 64, Color(col.r, col.g, col.b, 0.7), 4.0)
		if captured[k] == 0 and progress[k] > 0.0:
			ci.draw_arc(p, radius - 10.0, -PI * 0.5, -PI * 0.5 + TAU * progress[k] / capture_time, 64, prog_col, 10.0)
		if captured[k] != 0:
			ci.draw_arc(p, suppress_radius, 0.0, TAU, 96, Color(col.r, col.g, col.b, 0.07), 3.0)
