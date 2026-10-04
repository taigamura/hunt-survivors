class_name MusouGauge
extends RefCounted
## Fills from KOs (more from officers and part breaks). Full = the Musou button lights up.

var value: float = 0.0
var max_value: float = 300.0
var triggers: int = 0
var recharge_lock: float = 20.0
var lock_timer: float = 0.0  ## after a Musou the gauge stays empty for a while


func setup() -> void:
	max_value = Tuning.f("musou.max", 300.0)
	recharge_lock = Tuning.f("musou.recharge_lock", 20.0)
	value = 0.0


func add(amount: float, mult: float = 1.0) -> void:
	if lock_timer > 0.0:
		return
	value = minf(max_value, value + amount * mult)


func tick(dt: float) -> void:
	if lock_timer > 0.0:
		lock_timer -= dt


func is_locked() -> bool:
	return lock_timer > 0.0


func is_full() -> bool:
	return value >= max_value


func fraction() -> float:
	return clampf(value / max_value, 0.0, 1.0)


## Spends the full gauge. Returns false if it wasn't full.
func trigger() -> bool:
	if not is_full():
		return false
	value = 0.0
	triggers += 1
	lock_timer = recharge_lock
	return true
