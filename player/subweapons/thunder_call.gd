class_name ThunderCall
extends Weapon
## Lightning strikes the densest nearby crowd (found via the spatial hash).

var levels: Array = []
var strike_range: float = 520.0
var samples: int = 10
var _timer: float = 0.8
var strikes_done: int = 0
var last_strike: Vector2 = Vector2.INF


func _init() -> void:
	id = "thunder_call"


func setup(p_hunt: HuntContext, p_player: Player) -> void:
	super.setup(p_hunt, p_player)
	var cfg := Tuning.d("subweapons.thunder_call")
	display_name = String(cfg["name"])
	levels = cfg["levels"]
	strike_range = float(cfg["range"])
	samples = int(cfg["samples"])


func cfg() -> Dictionary:
	return levels[clampi(level, 1, levels.size()) - 1]


func update(dt: float, move: Vector2) -> void:
	_timer -= dt * player.haste_mult
	if _timer > 0.0:
		return
	var c := cfg()
	_timer = float(c["interval"])
	var r := float(c["radius"]) * player.area_mult
	for k in int(c["strikes"]):
		var target := hunt.densest_point(player.position, strike_range, samples, r)
		if target == Vector2.INF:
			return
		hunt.hit_circle(target, r, dmg(float(c["damage"])), 220.0, HuntContext.HIT_BIG)
		hunt.fx_over.bolt(target, r, "fx.bolt")
		hunt.fx_under.circle(target, r, "fx.bolt", 0.25)
		hunt.add_shake(0.12)
		strikes_done += 1
		last_strike = target
