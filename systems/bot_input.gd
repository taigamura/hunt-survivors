class_name BotInput
extends RefCounted
## Scripted "competent-ish" player for smoke runs and balance telemetry:
## - kites away from nearby crowds, wanders toward uncaptured outposts, engages the monster
##   from the side and sidesteps its telegraphs;
## - Great Sword: plants to charge when there's breathing room, then steps into the crowd;
## - Dual Blades: keeps full deflection, circle-strafes, and whips back for dash cuts.
## Also includes a little randomness so runs differ by seed.

var rng := RandomNumberGenerator.new()
var weapon: String = "great_sword"
var wander_dir: Vector2 = Vector2.RIGHT
var wander_timer: float = 0.0
var commit_timer: float = 0.0
var commit_dir: Vector2 = Vector2.ZERO
var reverse_timer: float = 3.0
var strafe_sign: float = 1.0


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
		if db.momentum >= 0.9 and reverse_timer <= 0.0 and near > 6:
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
