class_name BotInput
extends RefCounted
## Scripted input for smoke runs: random walk with periodic stops (so the Great Sword
## charges) and occasional sharp reversals (so Dual Blades dash-cut). Steers off map edges.

var rng := RandomNumberGenerator.new()
var dir: Vector2 = Vector2.RIGHT
var timer: float = 0.0
var stopped: bool = false
var reverse_timer: float = 3.0


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value


func next(dt: float, pos: Vector2, map_rect: Rect2, threat: Vector2 = Vector2.INF) -> Vector2:
	timer -= dt
	reverse_timer -= dt
	if timer <= 0.0:
		if not stopped and rng.randf() < 0.35:
			stopped = true
			timer = rng.randf_range(0.8, 1.8)
		else:
			stopped = false
			dir = Vector2.from_angle(rng.randf() * TAU)
			timer = rng.randf_range(0.6, 2.0)
	if not stopped and reverse_timer <= 0.0:
		reverse_timer = rng.randf_range(2.5, 4.5)
		dir = -dir
	var inner := map_rect.grow(-700.0)
	if not inner.has_point(pos):
		dir = (map_rect.get_center() - pos).normalized()
		stopped = false
	if threat != Vector2.INF and pos.distance_to(threat) < 260.0:
		dir = (pos - threat).normalized()
		stopped = false
	return Vector2.ZERO if stopped else dir
