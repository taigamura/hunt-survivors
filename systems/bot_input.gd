class_name BotInput
extends RefCounted
## Scripted "competent-ish" player for smoke runs and balance telemetry:
## - kites away from nearby crowds, wanders toward uncaptured outposts, engages the monster
##   from the side and sidesteps its telegraphs;
## - Great Sword: plants to charge when there's breathing room, then steps into the crowd;
## - Hand Cannon / Bulwark: plant (steady aim / shield up) while there's room, kite when swarmed;
## - Dual Blades / Twin Fangs: keep full deflection, circle-strafe, whip back for dash cuts / spins;
## - Assault Rifle: kites at full deflection;
## - gesture thumb (next_gestures): fires a ready bound move every second or so at the crowd or
##   the monster, and always tries a perfect counter when a telegraphed attack is about to land.
## Also includes a little randomness so runs differ by seed.

var rng := RandomNumberGenerator.new()
var weapon: String = "great_sword"
var wander_dir: Vector2 = Vector2.RIGHT
var wander_timer: float = 0.0
var commit_timer: float = 0.0
var commit_dir: Vector2 = Vector2.ZERO
var reverse_timer: float = 3.0
var strafe_sign: float = 1.0
var gesture_timer: float = 1.0
var plant_timer: float = 2.0
var counter_skill: float = 0.4  ## chance the bot tries a perfect counter on a given telegraph
var _counter_roll: float = -1.0


func _init(seed_value: int = 1, p_weapon: String = "great_sword") -> void:
	rng.seed = seed_value
	weapon = p_weapon


func next(dt: float, hunt: HuntContext) -> Vector2:
	var player := hunt.player
	var pos := player.position
	var en := hunt.enemies
	wander_timer -= dt
	reverse_timer -= dt
	if commit_timer > 0.0:
		commit_timer -= dt
		return commit_dir

	# --- threat field from nearby enemies
	var threat := Vector2.ZERO
	var crowd := Vector2.ZERO
	var near := 0
	var close := 0
	for i in en.query_circle(pos, 300.0, false):
		var d := pos - en.pos[i]
		var l := d.length()
		if l < 0.01:
			continue
		threat += d / l * (1.0 - l / 300.0)
		crowd += en.pos[i]
		near += 1
		if l < 120.0:
			close += 1
	if near > 0:
		crowd /= near

	# --- goal: monster (when it's here) or an uncaptured outpost, else wander
	var goal := Vector2.INF
	var monster: Ironhorn = hunt.get("monster")
	var dodge := Vector2.ZERO
	if monster != null and monster.is_alive():
		var to_m := monster.position - pos
		if monster.state == Ironhorn.State.TELEGRAPH or (monster.state == Ironhorn.State.ATTACK and monster.attack == "charge"):
			# sidestep perpendicular to the attack direction / away from the body
			var away := -to_m.normalized()
			if monster.attack == "charge":
				var side := monster.attack_dir.orthogonal()
				if side.dot(pos - monster.position) < 0.0:
					side = -side
				dodge = side * 1.6 + away * 0.4
			else:
				dodge = away * 1.5
		else:
			goal = monster.position + to_m.normalized().orthogonal() * 140.0 * strafe_sign - to_m.normalized() * 150.0
	else:
		var ops: Outposts = hunt.get("outposts")
		if ops != null:
			var best := INF
			for k in ops.positions.size():
				if not ops.is_captured(k):
					var dd := pos.distance_to(ops.positions[k])
					if dd < best:
						best = dd
						goal = ops.positions[k]
	if wander_timer <= 0.0:
		wander_timer = rng.randf_range(1.0, 2.5)
		wander_dir = Vector2.from_angle(rng.randf() * TAU)
		if rng.randf() < 0.3:
			strafe_sign = -strafe_sign

	var goal_dir := wander_dir
	if goal != Vector2.INF and pos.distance_to(goal) > 30.0:
		goal_dir = (goal - pos).normalized()
	elif goal != Vector2.INF:
		goal_dir = Vector2.ZERO  # sit on the outpost

	# keep off the map edge
	var mr: Rect2 = player.map_rect.grow(-500.0)
	if not mr.has_point(pos):
		goal_dir = (mr.get_center() - pos).normalized()

	if dodge != Vector2.ZERO:
		return dodge.normalized()

	if weapon in ["pistol", "sword_shield"]:
		# alternate holding ground (steady aim / shield up) with short walks to collect XP
		plant_timer -= dt
		if plant_timer <= -rng.randf_range(1.0, 1.6):
			plant_timer = rng.randf_range(2.0, 3.2)
		var swarmed := player.hp <= player.max_hp * 0.3 and close >= 3
		if plant_timer > 0.0 and not swarmed:
			return Vector2.ZERO
		# ranged kills drop XP far away: walk to the nearest gem when there is one
		var xp: XPSystem = hunt.get("xp")
		if xp != null:
			var best := 650.0 * 650.0
			for g in xp.count:
				var d2 := xp.gpos[g].distance_squared_to(pos)
				if d2 < best:
					best = d2
					goal_dir = (xp.gpos[g] - pos).normalized()
		var walk := goal_dir * 0.8 + threat * 1.0
		# half stick: Bulwark keeps its shield up while walking
		var mag := 0.6 if weapon == "sword_shield" and not swarmed else 1.0
		return (walk.normalized() if walk.length() > 0.05 else goal_dir) * mag
	if weapon == "great_sword":
		var gs := player.weapons[0] as GreatSword
		var lvl := gs.charge_level()
		# release into the crowd when charged and they're close
		if lvl >= 1 and close > 0:
			commit_dir = (crowd - pos).normalized()
			commit_timer = 0.12
			return commit_dir
		# plant if there's room (or always while on an outpost)
		var hp_ok := player.hp > player.max_hp * 0.25
		if hp_ok or close < 3:
			return Vector2.ZERO
		var dir := goal_dir * 1.0 + threat * 0.8
		return dir.normalized() if dir.length() > 0.05 else goal_dir
	else:
		var db := player.weapons[0] as DualBlades
		var can_whip := (db != null and db.momentum >= 0.9) or weapon == "dual_pistols"
		if can_whip and reverse_timer <= 0.0 and near > 6:
			reverse_timer = rng.randf_range(1.5, 3.0)
			commit_dir = (crowd - pos).normalized() if near > 0 else -player.move_dir
			commit_timer = 0.1
			return commit_dir
		var strafe := threat.orthogonal() * strafe_sign
		var dir2 := goal_dir * 0.7 + threat * 1.1 + strafe * 0.6
		if goal_dir == Vector2.ZERO:
			# circle the outpost instead of standing still
			dir2 = player.move_dir.rotated(0.08) + threat
		return dir2.normalized() if dir2.length() > 0.05 else wander_dir


## Gesture-thumb policy. Returns world-space gesture events for Hunt.inject_gesture.
func next_gestures(dt: float, hunt: HuntContext) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var moves: MoveSet = hunt.get("moves")
	if moves == null:
		return out
	var player := hunt.player
	var ready: Array[String] = []
	for kind in moves.bound_gestures():
		if moves.is_ready(kind):
			ready.append(kind)
	if ready.is_empty():
		return out
	var monster: Ironhorn = hunt.get("monster")
	if monster == null or monster.state != Ironhorn.State.TELEGRAPH:
		_counter_roll = -1.0
	elif monster.counter_window(player.position, player.radius + 40.0, Tuning.f("gestures.perfect_window", 0.3)):
		if _counter_roll < 0.0:
			_counter_roll = rng.randf()  # decide once per telegraph
		if _counter_roll < counter_skill:
			_counter_roll = 2.0
			out.append({"kind": ready[0], "dir": (monster.position - player.position).normalized()})
			return out
	gesture_timer -= dt
	if gesture_timer > 0.0:
		return out
	gesture_timer = rng.randf_range(0.5, 1.4)
	var target := hunt.auto_target(player.position, 450.0)
	if target == Vector2.INF:
		return out
	var kind := ready[rng.randi() % ready.size()]
	out.append({"kind": kind, "dir": (target - player.position).normalized(), "hold_time": rng.randf_range(0.3, 1.5) if kind == "hold" else 0.0})
	return out
