class_name HuntContext
extends Node2D
## The interface weapons, sub-weapons and the monster use to affect the world.
## The real Hunt scene implements it; tests use a recording fake.

const HIT_NONE := 0
const HIT_BIG := 1        ## always show a damage number
const HIT_NO_MONSTER := 2 ## don't apply to the monster
const HIT_DOT := 4        ## lingering ground damage (reduced against the monster)

var player: Player
var enemies: EnemySystem
var fx_under: FX
var fx_over: FX
var run_time: float = 0.0


func hit_circle(c: Vector2, r: float, dmg: float, knock: float, flags: int = 0) -> int:
	return 0


func hit_arc(c: Vector2, dir: Vector2, r: float, half: float, dmg: float, knock: float, flags: int = 0) -> int:
	return 0


func hit_line(a: Vector2, b: Vector2, w: float, dmg: float, knock: float, flags: int = 0) -> int:
	return 0


## Hitscan round from `a` along unit `dir`: hits the nearest `pierce` enemies within `reach`
## (the monster stops it). Returns where the round stopped, for the tracer.
func shoot(a: Vector2, dir: Vector2, reach: float, width: float, dmg: float, knock: float, pierce: int, flags: int = 0) -> Vector2:
	return a + dir * reach


## Auto-aim point: the monster's nearest unbroken part if it is within range, else the
## nearest swarm enemy, else Vector2.INF.
func auto_target(from: Vector2, max_range: float) -> Vector2:
	return Vector2.INF


## Nearest target inside a pie slice (monster aim point included), or Vector2.INF.
func nearest_in_arc(from: Vector2, max_range: float, dir: Vector2, half: float) -> Vector2:
	return Vector2.INF


## Up to n enemy positions for a ricochet: nearest to `from`, then nearest to each previous
## hit within `hop` (no repeats).
func chain_targets(from: Vector2, n: int, first_range: float, hop: float) -> PackedVector2Array:
	return PackedVector2Array()


## Level of an owned sub-weapon (0 = not owned).
func sub_level(sub_id: String) -> int:
	return 0


## Multiplier from passives and captured outposts.
func damage_mult() -> float:
	return 1.0


func add_shake(amount: float) -> void:
	pass


func hitstop(ms: int) -> void:
	pass


func haptic(key: String) -> void:
	pass


## Best strike point near `center` (densest crowd), or Vector2.INF if nothing nearby.
func densest_point(center: Vector2, max_range: float, samples: int, radius: float) -> Vector2:
	return Vector2.INF


# ---- monster callbacks

## Kills swarm enemies in a circle (monster crush). Returns count.
func kill_enemies_in_circle(c: Vector2, r: float, cause: int) -> int:
	return 0


func damage_player(amount: float, from: Vector2) -> bool:
	return false


func slow_player(seconds: float) -> void:
	pass


func spawn_grunts_around(c: Vector2, n: int, min_r: float, max_r: float) -> void:
	pass


func on_monster_part_broken(part: String, at: Vector2) -> void:
	pass


func on_monster_died(at: Vector2) -> void:
	pass


func is_blocked(p: Vector2) -> bool:
	return false


## Path-aware direction toward `to` (flow field). Default: straight line.
func steer_dir(from: Vector2, to: Vector2) -> Vector2:
	return (to - from).normalized()
