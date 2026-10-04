class_name FakeHunt
extends HuntContext
## Recording stand-in for the Hunt, for weapon/monster unit tests.

var hits: Array[Dictionary] = []
var player_damage: Array[float] = []
var parts_broken: Array[String] = []
var died: bool = false
var shakes: int = 0
var crushes: int = 0
var spawned: int = 0
var slowed: float = 0.0
var dmg_mult_value: float = 1.0
var densest: Vector2 = Vector2(100, 0)
var target: Vector2 = Vector2(100, 0)
var subs: Dictionary = {}


static func make(parent: Node) -> FakeHunt:
	var h := FakeHunt.new()
	parent.add_child(h)
	h.player = Player.new()
	h.add_child(h.player)
	h.player.setup()
	h.fx_over = FX.new()
	h.add_child(h.fx_over)
	h.fx_under = FX.new()
	h.add_child(h.fx_under)
	return h


func hit_circle(c: Vector2, r: float, dmg: float, knock: float, flags: int = 0) -> int:
	hits.append({"shape": "circle", "c": c, "r": r, "dmg": dmg, "knock": knock, "flags": flags})
	return 1


func hit_arc(c: Vector2, dir: Vector2, r: float, half: float, dmg: float, knock: float, flags: int = 0) -> int:
	hits.append({"shape": "arc", "c": c, "dir": dir, "r": r, "half": half, "dmg": dmg, "knock": knock, "flags": flags})
	return 1


func hit_line(a: Vector2, b: Vector2, w: float, dmg: float, knock: float, flags: int = 0) -> int:
	hits.append({"shape": "line", "a": a, "b": b, "w": w, "dmg": dmg, "knock": knock, "flags": flags})
	return 1


func shoot(a: Vector2, dir: Vector2, reach: float, width: float, dmg: float, knock: float, pierce: int, flags: int = 0) -> Vector2:
	hits.append({"shape": "shot", "a": a, "dir": dir, "range": reach, "w": width, "dmg": dmg, "knock": knock, "pierce": pierce, "flags": flags})
	return a + dir * reach


func auto_target(from: Vector2, max_range: float) -> Vector2:
	return target if target != Vector2.INF and from.distance_to(target) <= max_range else Vector2.INF


func nearest_in_arc(from: Vector2, max_range: float, dir: Vector2, half: float) -> Vector2:
	if target == Vector2.INF or from.distance_to(target) > max_range:
		return Vector2.INF
	return target if absf(dir.angle_to(target - from)) <= half else Vector2.INF


func chain_targets(from: Vector2, n: int, first_range: float, hop: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		out.append(from + Vector2(60.0 * (k + 1), 0))
	return out


func sub_level(sub_id: String) -> int:
	return int(subs.get(sub_id, 0))


func hits_of(shape: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in hits:
		if String(h["shape"]) == shape:
			out.append(h)
	return out


func damage_mult() -> float:
	return dmg_mult_value


func add_shake(amount: float) -> void:
	shakes += 1


func densest_point(center: Vector2, max_range: float, samples: int, radius: float) -> Vector2:
	return densest


func kill_enemies_in_circle(c: Vector2, r: float, cause: int) -> int:
	crushes += 1
	return 0


func damage_player(amount: float, from: Vector2) -> bool:
	player_damage.append(amount)
	return true


func slow_player(seconds: float) -> void:
	slowed = seconds


func spawn_grunts_around(c: Vector2, n: int, min_r: float, max_r: float) -> void:
	spawned += n


func on_monster_part_broken(part: String, at: Vector2) -> void:
	parts_broken.append(part)


func on_monster_died(at: Vector2) -> void:
	died = true
