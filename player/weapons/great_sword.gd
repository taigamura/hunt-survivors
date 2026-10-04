class_name GreatSword
extends Weapon
## "Plant your feet." Standing still charges 3 levels; starting to move releases
## a wide arc toward the movement direction. A weak swipe ticks while moving.
## Gesture moves: Aimed Unleash (release toward a swipe without moving), Tackle (keeps and adds
## charge), Overhead Slam, Whirlwind (360 release), Fissure.

var thresholds: Array[float] = [0.4, 0.9, 1.5]
var levels: Array = []
var swipe: Dictionary = {}
var shockwave: Dictionary = {}
var brace: Dictionary = {}
var planted_mult: float = 0.6
var release_iframes: float = 0.3

var charge_time: float = 0.0
var was_moving: bool = false
var swipe_timer: float = 0.0
var _last_level_seen: int = 0

# observable for tests / telemetry
var releases: int = 0
var last_release_level: int = 0
var last_release_dir: Vector2 = Vector2.ZERO
var swipes: int = 0


func _init() -> void:
	id = "great_sword"


func setup(p_hunt: HuntContext, p_player: Player) -> void:
	super.setup(p_hunt, p_player)
	var cfg := Tuning.d("weapons.great_sword")
	display_name = String(cfg.get("name", "Great Sword"))
	thresholds.clear()
	for v: Variant in cfg["thresholds"]:
		thresholds.append(float(v))
	levels = cfg["levels"]
	swipe = cfg["swipe"]
	shockwave = cfg["shockwave"]
	brace = cfg.get("brace", {})
	upgrade_defs = cfg["upgrades"]
	planted_mult = float(cfg.get("planted_damage_mult", 0.6))
	release_iframes = float(cfg.get("release_iframes", 0.3))
	swipe_timer = float(swipe["interval"])


func threshold(lvl: int) -> float:
	var speedup := clampf(1.0 - up_value("gs_charge"), 0.3, 1.0)
	return thresholds[lvl - 1] * speedup / player.haste_mult


func charge_level() -> int:
	var lvl := 0
	for k in range(1, 4):
		if charge_time >= threshold(k):
			lvl = k
	return lvl


## Planted stance: standing still to charge also braces you.
func damage_taken_mult() -> float:
	return planted_mult if not was_moving else 1.0


func charge_fraction() -> float:
	return clampf(charge_time / threshold(3), 0.0, 1.0)


func update(dt: float, move: Vector2) -> void:
	var moving := move.length_squared() > 0.0001
	if not moving:
		charge_time += dt
		var lvl := charge_level()
		if lvl > _last_level_seen:
			_last_level_seen = lvl
			# level-up glow pulse + brace shove (keeps the crowd off you while you charge)
			hunt.fx_over.ring(player.position, 34.0 + lvl * 8.0, "fx.charge%d" % lvl, 0.25, 4.0 + lvl * 2.0, 0.6)
			if not brace.is_empty():
				var br := (float(brace["radius"]) + float(brace["radius_per_level"]) * lvl) * player.area_mult
				hunt.hit_circle(player.position, br, dmg(float(brace["damage"]) * lvl), float(brace["knock"]) + float(brace["knock_per_level"]) * lvl)
				hunt.fx_over.ring(player.position, br, "fx.charge%d" % lvl, 0.2, 6.0, 0.5)
			if lvl == 3:
				hunt.haptic("gs_level3")
	else:
		if not was_moving:
			var lvl := charge_level()
			if lvl >= 1:
				release(lvl, move.normalized())
				_spend_charge()
			else:
				charge_time = 0.0
			_last_level_seen = charge_level()
		swipe_timer -= dt * player.haste_mult
		if swipe_timer <= 0.0:
			_do_swipe(move.normalized())
			swipe_timer = float(swipe["interval"]) * clampf(1.0 - up_value("gs_swipe"), 0.35, 1.0)
	was_moving = moving


func _spend_charge() -> void:
	var retain := up_value("gs_retain")
	charge_time = charge_time * retain if retain > 0.0 else 0.0
	_last_level_seen = charge_level()


func release(lvl: int, dir: Vector2, power: float = 1.0) -> void:
	var cfg: Dictionary = levels[lvl - 1]
	var arc_bonus := 1.0 + up_value("gs_arc")
	var r := float(cfg["radius"]) * player.area_mult * arc_bonus
	var half := minf(deg_to_rad(float(cfg["half_angle_deg"])) * arc_bonus, PI * 0.95)
	var damage := dmg(float(cfg["damage"])) * power
	var flags := HuntContext.HIT_BIG if lvl >= 2 else HuntContext.HIT_NONE
	hunt.hit_arc(player.position, dir, r, half, damage, float(cfg["knock"]), flags)
	hunt.fx_over.arc(player.position, dir, r, half, "fx.slash_gs%d" % lvl, 0.16 + 0.05 * lvl)
	hunt.add_shake(float(cfg["shake"]))
	var stop_ms := int(cfg.get("hitstop_ms", 0))
	if stop_ms > 0:
		hunt.hitstop(stop_ms)
	if lvl == 3:
		hunt.haptic("gs_level3")
		var sw_lvl := up("gs_shockwave")
		if sw_lvl > 0:
			var sr := float(shockwave["radius"]) * player.area_mult * (1.0 + 0.25 * (sw_lvl - 1))
			var sd := damage * float(shockwave["damage_frac"]) * (1.0 + up_value("gs_shockwave") - 0.5)
			hunt.hit_circle(player.position, sr, sd, float(shockwave["knock"]), HuntContext.HIT_BIG)
			hunt.fx_over.ring(player.position, sr, "fx.shockwave", 0.4, 16.0, 0.7)
	# a committed release is a brief moment of invulnerability
	player.iframes = maxf(player.iframes, release_iframes)
	releases += 1
	last_release_level = lvl
	last_release_dir = dir


func perform_move(move_id: String, def: Dictionary, ctx: Dictionary) -> bool:
	var dir: Vector2 = ctx["dir"]
	var power := float(ctx["power"])
	match move_id:
		"gs_aimed":
			var lvl := charge_level()
			if lvl >= 1:
				release(lvl, dir, power)
				_spend_charge()
			else:
				var r := float(def["uncharged_radius"]) * player.area_mult
				var half := deg_to_rad(float(def["uncharged_half_angle_deg"]))
				hunt.hit_arc(player.position, dir, r, half, move_dmg(def, "uncharged_damage", ctx), float(def["knock"]))
				hunt.fx_over.arc(player.position, dir, r, half, "fx.slash_gs1", 0.16)
			player.facing = dir
			return true
		"gs_tackle":
			var dist := float(def["distance"])
			var a := player.position
			var dur := float(def["duration"])
			player.start_dash(dir, dist, dur)
			player.iframes = maxf(player.iframes, dur + 0.1)
			hunt.hit_line(a, a + dir * dist, float(def["width"]) * player.area_mult, move_dmg(def, "damage", ctx), float(def["knock"]))
			hunt.fx_over.line(a, a + dir * dist, 30.0, "fx.swipe", 0.2)
			hunt.add_shake(0.2)
			charge_time += float(def["charge_add"]) / player.haste_mult
			return true
		"gs_slam":
			var lvl := charge_level()
			var p := target_point(ctx, float(def["reach"]))
			var r := (float(def["radius"]) + float(def["radius_per_level"]) * lvl) * player.area_mult
			var d := dmg(float(def["damage"]) + float(def["damage_per_level"]) * lvl) * power
			hunt.hit_circle(p, r, d, float(def["knock"]), HuntContext.HIT_BIG)
			hunt.fx_over.circle(p, r, "fx.slash_gs%d" % maxi(1, lvl), 0.25)
			hunt.fx_over.ring(p, r, "fx.shockwave", 0.3, 12.0, 0.5)
			hunt.fx_over.line(player.position, p, 26.0, "fx.slash_gs%d" % maxi(1, lvl), 0.15)
			hunt.add_shake(0.25 + 0.2 * lvl)
			if lvl >= 3:
				hunt.hitstop(int(levels[2].get("hitstop_ms", 0)))
				hunt.haptic("gs_level3")
			if lvl >= 1:
				_spend_charge()
			return true
		"gs_whirl":
			var lvl := charge_level()
			if lvl < 1:
				return false
			var cfg: Dictionary = levels[lvl - 1]
			var r := float(cfg["radius"]) * player.area_mult * (1.0 + up_value("gs_arc")) * float(def["radius_frac"])
			var d := dmg(float(cfg["damage"])) * float(def["damage_frac"]) * power
			hunt.hit_circle(player.position, r, d, float(cfg["knock"]), HuntContext.HIT_BIG)
			hunt.fx_over.arc(player.position, player.facing, r, PI, "fx.slash_gs%d" % lvl, 0.25)
			hunt.fx_over.ring(player.position, r, "fx.slash_gs%d" % lvl, 0.3, 10.0, 0.3)
			hunt.add_shake(float(cfg["shake"]))
			player.iframes = maxf(player.iframes, release_iframes)
			_spend_charge()
			return true
		"gs_quake":
			var r := float(def["radius"]) * player.area_mult
			for k in int(def["count"]):
				var p := player.position + dir * float(def["spacing"]) * (k + 1)
				hunt.hit_circle(p, r, move_dmg(def, "damage", ctx), float(def["knock"]))
				hunt.fx_under.circle(p, r, "fx.shockwave", 0.3 + 0.05 * k)
			hunt.add_shake(0.35)
			return true
	return super.perform_move(move_id, def, ctx)


func _do_swipe(dir: Vector2) -> void:
	var r := float(swipe["radius"]) * player.area_mult
	var half := deg_to_rad(float(swipe["half_angle_deg"]))
	var damage := dmg(float(swipe["damage"])) * (1.0 + 2.5 * up_value("gs_swipe"))
	hunt.hit_arc(player.position, dir, r, half, damage, float(swipe["knock"]))
	hunt.fx_over.arc(player.position, dir, r, half, "fx.swipe", 0.12)
	swipes += 1


func draw_local(ci: CanvasItem) -> void:
	var lvl := charge_level()
	var frac := charge_fraction()
	var r := player.radius + 13.0
	ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 5.0)
	if frac > 0.0:
		var col := ArtRegistry.color("fx.charge%d" % lvl)
		ci.draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 40, col, 5.0)
		# threshold ticks
		for k in range(1, 4):
			var a := -PI * 0.5 + TAU * threshold(k) / threshold(3)
			ci.draw_line(Vector2.from_angle(a) * (r - 5), Vector2.from_angle(a) * (r + 5), Color(0, 0, 0, 0.6), 2.0)
	if lvl >= 1:
		var g := ArtRegistry.color("fx.charge%d" % lvl)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
		g.a = 0.18 + 0.12 * lvl + 0.1 * pulse
		ci.draw_circle(Vector2.ZERO, player.radius + 4.0 + 5.0 * lvl, g)
		if lvl == 3:
			ci.draw_arc(Vector2.ZERO, r + 8.0 + 3.0 * pulse, 0.0, TAU, 40, Color(1, 1, 1, 0.8), 2.5)
