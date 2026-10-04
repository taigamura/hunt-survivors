class_name SwordShield
extends Weapon
## Bulwark: "Hold the line." Below full stick (walking or standing still) the shield is up:
## hits from the front arc are blocked (guard_mult) and every block charges a counter-bash that
## fires on its own when full. Standing still, the shield turns to track the nearest foe.
## A short sword jab ticks toward your facing. Running (full stick) lowers the shield.
## Gesture moves: Guard Counter, Shield Charge, Shield Wall (hold), Shield Throw, Earthguard.

var guard_below: float = 0.8
var guard_arc_deg: float = 150.0
var guard_mult: float = 0.25
var jab: Dictionary = {}
var retaliate: Dictionary = {}

var guarding: bool = false
var energy: float = 0.0
var jab_timer: float = 0.0

# Guard Counter window and the strike it owes (struck on the next update, not mid-hit)
var counter_timer: float = 0.0
var counter_def: Dictionary = {}
var counter_power: float = 1.0
var counter_pending: bool = false
var counter_dir: Vector2 = Vector2.RIGHT

# Shield Wall: active while the gesture thumb is held
var wall_holding: bool = false
var wall_def: Dictionary = {}

var _thorns_at: PackedVector2Array = PackedVector2Array()

# observable for tests / telemetry
var blocks: int = 0
var bashes: int = 0
var jabs: int = 0
var counters: int = 0


func _init() -> void:
	id = "sword_shield"


func setup(p_hunt: HuntContext, p_player: Player) -> void:
	super.setup(p_hunt, p_player)
	var cfg := Tuning.d("weapons.sword_shield")
	display_name = String(cfg.get("name", "Bulwark"))
	guard_below = float(cfg["guard_below"])
	guard_arc_deg = float(cfg["guard_arc_deg"])
	guard_mult = float(cfg["guard_mult"])
	jab = cfg["jab"]
	retaliate = cfg["retaliate"]
	upgrade_defs = cfg["upgrades"]
	jab_timer = float(jab["interval"])


func guard_half_angle() -> float:
	return deg_to_rad(guard_arc_deg + up_value("sh_arc")) * 0.5


func energy_max() -> float:
	return float(retaliate["max"])


func update(dt: float, move: Vector2) -> void:
	var mag := move.length()
	guarding = mag < guard_below
	# planted: the shield turns toward the nearest threat
	if mag < 0.0001:
		var t := hunt.auto_target(player.position, 260.0)
		if t != Vector2.INF and t.distance_to(player.position) > 1.0:
			var want := (t - player.position).normalized()
			player.facing = Vector2.from_angle(rotate_toward(player.facing.angle(), want.angle(), 6.0 * dt))
	if counter_timer > 0.0:
		counter_timer -= dt
	if counter_pending:
		_counter_strike()
	if not _thorns_at.is_empty():
		var td := up_value("sh_thorns")
		for p in _thorns_at:
			hunt.hit_circle(p, 26.0, dmg(td), 160.0, HuntContext.HIT_NO_MONSTER)
		_thorns_at.clear()
	if energy >= energy_max():
		_bash()
	jab_timer -= dt * player.haste_mult
	if jab_timer <= 0.0:
		jab_timer = float(jab["interval"]) * clampf(1.0 - up_value("sh_jab"), 0.35, 1.0)
		var r := float(jab["radius"]) * player.area_mult
		var half := deg_to_rad(float(jab["half_angle_deg"]))
		hunt.hit_arc(player.position, player.facing, r, half, dmg(float(jab["damage"])), float(jab["knock"]))
		hunt.fx_over.arc(player.position, player.facing, r, half * 0.6, "fx.swipe", 0.1)
		jabs += 1


func modify_incoming(amount: float, from: Vector2) -> float:
	var to := from - player.position
	if counter_timer > 0.0:
		counter_pending = true
		if to.length_squared() > 1.0:
			counter_dir = to.normalized()
		return 0.0
	var mult := 1.0
	if wall_holding:
		mult = float(wall_def.get("guard_mult", 0.15))
	elif guarding and to.length_squared() > 1.0 and absf(player.facing.angle_to(to)) <= guard_half_angle():
		mult = guard_mult
	if mult >= 1.0:
		return amount
	_on_block(amount * (1.0 - mult), from)
	return amount * mult


func _on_block(blocked: float, from: Vector2) -> void:
	blocks += 1
	energy = minf(energy_max(), energy + blocked * float(retaliate["energy_per_damage"]) * (1.0 + up_value("sh_grudge")))
	if up("sh_thorns") > 0:
		_thorns_at.append(from)
	hunt.fx_over.arc(player.position, (from - player.position).normalized(), player.radius + 26.0, 0.6, "fx.shield", 0.15)
	hunt.haptic("block")


func _bash() -> void:
	energy = 0.0
	var bonus := 1.0 + up_value("sh_bash")
	var r := float(retaliate["radius"]) * player.area_mult * bonus
	var half := deg_to_rad(float(retaliate["half_angle_deg"]))
	hunt.hit_arc(player.position, player.facing, r, half, dmg(float(retaliate["damage"])) * bonus, float(retaliate["knock"]), HuntContext.HIT_BIG)
	hunt.fx_over.arc(player.position, player.facing, r, half, "fx.shield", 0.25)
	hunt.add_shake(0.35)
	bashes += 1


func _counter_strike() -> void:
	counter_pending = false
	counter_timer = 0.0
	var r := float(counter_def["radius"]) * player.area_mult
	var half := deg_to_rad(float(counter_def["half_angle_deg"]))
	hunt.hit_arc(player.position, counter_dir, r, half, dmg(float(counter_def["damage"])) * counter_power, float(counter_def["knock"]), HuntContext.HIT_BIG)
	hunt.fx_over.arc(player.position, counter_dir, r, half, "fx.slash_gs3", 0.22)
	hunt.fx_over.ring(player.position, player.radius + 30.0, "fx.shield", 0.25, 8.0, 0.6)
	player.iframes = maxf(player.iframes, 0.3)
	hunt.add_shake(0.4)
	hunt.haptic("dash_cut")
	counters += 1


func perform_move(move_id: String, def: Dictionary, ctx: Dictionary) -> bool:
	var dir: Vector2 = ctx["dir"]
	var power := float(ctx["power"])
	match move_id:
		"sh_counter":
			counter_timer = float(def["window"])
			counter_def = def
			counter_power = power
			counter_dir = dir
			hunt.fx_over.ring(player.position, player.radius + 22.0, "fx.shield", float(def["window"]), 6.0, -0.2)
			return true
		"sh_charge":
			if player.is_dashing():
				return false
			var dist := float(def["distance"])
			var a := player.position
			var dur := float(def["duration"])
			player.start_dash(dir, dist, dur)
			player.facing = dir
			player.iframes = maxf(player.iframes, dur + 0.1)
			hunt.hit_line(a, a + dir * dist, float(def["width"]) * player.area_mult, move_dmg(def, "damage", ctx), float(def["knock"]))
			hunt.fx_over.line(a, a + dir * dist, 46.0, "fx.guard", 0.25)
			hunt.add_shake(0.3)
			return true
		"sh_wall":
			wall_holding = false
			var t := minf(float(ctx["hold_time"]), float(def["max_hold"]))
			var r := (float(def["radius"]) + float(def["radius_per_sec"]) * t) * player.area_mult
			var d := dmg(float(def["damage"]) + float(def["damage_per_sec"]) * t) * power
			hunt.hit_circle(player.position, r, d, float(def["knock"]), HuntContext.HIT_BIG)
			hunt.fx_over.ring(player.position, r, "fx.shield", 0.35, 16.0, 0.6)
			hunt.add_shake(0.25 + 0.2 * t)
			return true
		"sh_throw":
			var a := player.position
			var b := a + dir * float(def["distance"])
			var w := float(def["width"]) * player.area_mult
			hunt.hit_line(a, b, w, move_dmg(def, "damage", ctx), float(def["knock"]))
			hunt.hit_line(b, a, w, move_dmg(def, "damage", ctx) * 0.6, float(def["knock"]) * 0.5)
			hunt.fx_over.line(a, b, 30.0, "fx.shield", 0.3)
			hunt.fx_over.circle(b, w, "fx.shield", 0.3)
			return true
		"sh_slam":
			var r := float(def["radius"]) * player.area_mult
			hunt.hit_circle(player.position, r, move_dmg(def, "damage", ctx), float(def["knock"]), HuntContext.HIT_BIG)
			hunt.fx_over.ring(player.position, r, "fx.shield", 0.35, 20.0, 0.5)
			hunt.fx_under.circle(player.position, r, "fx.guard", 0.3)
			hunt.add_shake(0.45)
			return true
	return super.perform_move(move_id, def, ctx)


func begin_hold(move_id: String, def: Dictionary, ctx: Dictionary) -> void:
	if move_id == "sh_wall":
		wall_holding = true
		wall_def = def


func cancel_hold() -> void:
	wall_holding = false


func draw_local(ci: CanvasItem) -> void:
	var r := player.radius + 13.0
	ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 5.0)
	var frac := energy / energy_max()
	if frac > 0.0:
		ci.draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 40, ArtRegistry.color("fx.shield"), 5.0)
	var sc := ArtRegistry.color("fx.shield")
	if wall_holding:
		ci.draw_arc(Vector2.ZERO, r + 10.0, 0.0, TAU, 40, sc, 6.0)
	elif guarding:
		# the shield arc sits in the player's local frame; facing is world-space
		var a := player.facing.angle() - player.rotation
		var half := guard_half_angle()
		ci.draw_arc(Vector2.ZERO, r + 10.0, a - half, a + half, 24, sc, 6.0)
	if counter_timer > 0.0:
		ci.draw_arc(Vector2.ZERO, r + 18.0, 0.0, TAU, 40, ArtRegistry.color("fx.slash_gs3"), 3.0)
