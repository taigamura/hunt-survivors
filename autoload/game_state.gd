extends Node
## Cross-scene state: chosen weapon, settings, last run results, safe-area helper.

const WEAPONS: Array[String] = ["great_sword", "dual_blades"]

var selected_weapon: String = "great_sword"
var last_result: Dictionary = {}

## settings (persisted by Save)
var shake_mode: int = 0  # 0 = full, 1 = reduced, 2 = off
var haptics: bool = true
var musou_left: bool = false


func shake_mult() -> float:
	match shake_mode:
		1:
			return Tuning.f("camera.reduced_shake_mult", 0.35)
		2:
			return 0.0
	return 1.0


func shake_label() -> String:
	return ["Full", "Reduced", "Off"][clampi(shake_mode, 0, 2)]


func haptic(ms: int) -> void:
	if haptics and ms > 0 and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


## Safe-area insets in canvas (viewport) units: {top, bottom, left, right}.
func safe_insets(vp: Viewport) -> Dictionary:
	var out := {"top": 10.0, "bottom": 10.0, "left": 10.0, "right": 10.0}
	if not OS.has_feature("mobile"):
		return out
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if safe.size.x <= 0 or win.x <= 0:
		return out
	var vis := vp.get_visible_rect().size
	var sx := vis.x / float(win.x)
	var sy := vis.y / float(win.y)
	out["top"] = maxf(10.0, safe.position.y * sy)
	out["bottom"] = maxf(10.0, (win.y - safe.end.y) * sy)
	out["left"] = maxf(10.0, safe.position.x * sx)
	out["right"] = maxf(10.0, (win.x - safe.end.x) * sx)
	return out
