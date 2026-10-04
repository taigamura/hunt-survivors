class_name Progression
extends RefCounted
## XP -> levels. Level-ups queue in `pending` and are consumed one card-pick at a time.

var level: int = 1
var xp: int = 0
var pending: int = 0
var base: float = 6.0
var linear: float = 3.6
var quadratic: float = 0.32


func setup() -> void:
	base = Tuning.f("xp.curve_base", 6.0)
	linear = Tuning.f("xp.curve_linear", 3.6)
	quadratic = Tuning.f("xp.curve_quadratic", 0.32)


## XP needed to go from level L to L+1.
func xp_to_next(l: int) -> int:
	var k := float(l - 1)
	return int(round(base + linear * k + quadratic * k * k))


## Adds XP; returns number of new levels gained (also added to `pending`).
func add_xp(amount: int) -> int:
	xp += amount
	var gained := 0
	while xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		gained += 1
	pending += gained
	return gained


func take_pending() -> bool:
	if pending <= 0:
		return false
	pending -= 1
	return true


func progress() -> float:
	return clampf(float(xp) / float(xp_to_next(level)), 0.0, 1.0)


## Total XP from level 1 to reach level `l` (for tuning/tests).
func total_xp_for(l: int) -> int:
	var s := 0
	for k in range(1, l):
		s += xp_to_next(k)
	return s
