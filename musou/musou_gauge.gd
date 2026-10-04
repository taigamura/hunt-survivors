class_name MusouGauge
extends RefCounted
## Fills from KOs (more from officers and part breaks). Full = the Musou button lights up.

var value: float = 0.0
var max_value: float = 300.0
var triggers: int = 0


func setup() -> void:
	max_value = Tuning.f("musou.max", 300.0)
	value = 0.0


func add(amount: float, mult: float = 1.0) -> void:
	value = minf(max_value, value + amount * mult)


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
	return true
