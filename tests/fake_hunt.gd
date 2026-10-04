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
