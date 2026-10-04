extends Node
## Persists best KO count and fastest hunt per weapon, plus settings, to user://save.json.

const PATH := "user://save.json"

var best: Dictionary = {}  # weapon -> {"kos": int, "time": float (0 = never won)}


func _ready() -> void:
	load_save()


func load_save() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		return
	var dct: Dictionary = parsed
	best = dct.get("best", {})
	var s: Dictionary = dct.get("settings", {})
	GameState.shake_mode = int(s.get("shake_mode", 0))
	GameState.haptics = bool(s.get("haptics", true))
	GameState.musou_left = bool(s.get("musou_left", false))


func write() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"best": best,
		"settings": {
			"shake_mode": GameState.shake_mode,
			"haptics": GameState.haptics,
			"musou_left": GameState.musou_left,
		},
	}, "  "))


func best_for(weapon: String) -> Dictionary:
	var b: Dictionary = best.get(weapon, {})
	return {"kos": int(b.get("kos", 0)), "time": float(b.get("time", 0.0))}


## Records a run; returns {"new_kos": bool, "new_time": bool}.
func record(weapon: String, kos: int, won: bool, time_sec: float) -> Dictionary:
	var b := best_for(weapon)
	var res := {"new_kos": false, "new_time": false}
	if kos > b["kos"]:
		b["kos"] = kos
		res["new_kos"] = true
	if won and (b["time"] <= 0.0 or time_sec < b["time"]):
		b["time"] = time_sec
		res["new_time"] = true
	best[weapon] = b
	write()
	return res
