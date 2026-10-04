class_name MoveSet
extends RefCounted
## Gesture -> move bindings for one hunt, with per-move levels and cooldowns.
## Tap / swipe / hold come from the pre-hunt loadout; shape gestures (circle, v, zigzag,
## triangle) are unlocked mid-hunt by level-up cards. Moves are implemented by the main
## weapon (`Weapon.perform_move`); shared moves (roll, lightning) live in the Weapon base.

var weapon: Weapon
var player: Player
var defs: Dictionary = {}          ## move id -> tuning def
var pool: Array[String] = []       ## every move this weapon can use, in display order
var bindings: Dictionary = {}      ## gesture kind -> move id
var levels: Dictionary = {}        ## move id -> 1..max_level (bound moves only)
var cooldowns: Dictionary = {}     ## move id -> seconds left
var max_level: int = 3
var level_damage: float = 0.3
var level_cooldown: float = 0.12

# telemetry
var performed: int = 0
var perfects: int = 0
var by_move: Dictionary = {}       ## move id -> times performed


func setup(p_weapon: Weapon, p_player: Player, loadout: Dictionary) -> void:
	weapon = p_weapon
	player = p_player
	max_level = Tuning.i("moves.max_level", 3)
	level_damage = Tuning.f("moves.level_damage", 0.3)
	level_cooldown = Tuning.f("moves.level_cooldown", 0.12)
	defs.clear()
	pool.clear()
	for d: Dictionary in pool_defs(weapon.id):
		defs[String(d["id"])] = d
		pool.append(String(d["id"]))
	var clean := sanitize_loadout(weapon.id, loadout)
	for kind: String in clean:
		bind(kind, String(clean[kind]))


## The weapon's own moves followed by the shared ones.
static func pool_defs(weapon_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in Tuning.a("weapons.%s.moves" % weapon_id):
		out.append(d)
	for d: Dictionary in Tuning.a("moves.shared"):
		out.append(d)
	return out


static func pool_ids(weapon_id: String) -> Array[String]:
	var out: Array[String] = []
	for d in pool_defs(weapon_id):
		out.append(String(d["id"]))
	return out


static func start_gestures() -> Array[String]:
	var out: Array[String] = []
	for g: Variant in Tuning.a("moves.start_gestures"):
		out.append(String(g))
	return out


static func shape_gestures() -> Array[String]:
	var out: Array[String] = []
	for g: Variant in Tuning.a("moves.shape_gestures"):
		out.append(String(g))
	return out


static func default_loadout(weapon_id: String) -> Dictionary:
	return Tuning.d("weapons.%s.default_loadout" % weapon_id).duplicate()


## Keeps only the start gestures, known move ids and no duplicates; gaps are filled from the
## weapon's default loadout, then from the first unused pool move.
static func sanitize_loadout(weapon_id: String, loadout: Dictionary) -> Dictionary:
	var ids := pool_ids(weapon_id)
	var defaults := default_loadout(weapon_id)
	var out := {}
	var used := {}
	for kind in start_gestures():
		var want := String(loadout.get(kind, ""))
		if want in ids and not used.has(want):
			out[kind] = want
			used[want] = true
	for kind in start_gestures():
		if out.has(kind):
			continue
		var fallback := String(defaults.get(kind, ""))
		if not (fallback in ids) or used.has(fallback):
			fallback = ""
			for id in ids:
				if not used.has(id):
					fallback = id
					break
		if fallback != "":
			out[kind] = fallback
			used[fallback] = true
	return out


static func gesture_label(kind: String) -> String:
	match kind:
		"tap":
			return "TAP"
		"swipe":
			return "SWIPE"
		"hold":
			return "HOLD"
		"circle":
			return "CIRCLE"
		"v":
			return "V"
		"zigzag":
			return "ZIGZAG"
		"triangle":
			return "TRIANGLE"
	return kind.to_upper()


func bind(kind: String, move_id: String) -> void:
	if not defs.has(move_id):
		return
	bindings[kind] = move_id
	levels[move_id] = maxi(int(levels.get(move_id, 0)), 1)
	cooldowns[move_id] = 0.0


func move_for(kind: String) -> String:
	return String(bindings.get(kind, ""))


func def_of(move_id: String) -> Dictionary:
	return defs.get(move_id, {})


func level_of(move_id: String) -> int:
	return int(levels.get(move_id, 0))


func is_bound(move_id: String) -> bool:
	return move_id in bindings.values()


func unbound_moves() -> Array[String]:
	var out: Array[String] = []
	for id in pool:
		if not is_bound(id):
			out.append(id)
	return out


func unbound_shapes() -> Array[String]:
	var out: Array[String] = []
	for g in shape_gestures():
		if not bindings.has(g):
			out.append(g)
	return out


## Bound gestures in display order (start gestures, then shapes as unlocked).
func bound_gestures() -> Array[String]:
	var out: Array[String] = []
	for g in start_gestures() + shape_gestures():
		if bindings.has(g):
			out.append(g)
	return out


func upgradable_moves() -> Array[String]:
	var out: Array[String] = []
	for g in bound_gestures():
		var id := move_for(g)
		if level_of(id) < max_level:
			out.append(id)
	return out


func upgrade(move_id: String) -> void:
	if levels.has(move_id):
		levels[move_id] = mini(level_of(move_id) + 1, max_level)


func power(move_id: String) -> float:
	return 1.0 + level_damage * (level_of(move_id) - 1)


func cooldown_for(move_id: String) -> float:
	var base := float(def_of(move_id).get("cooldown", 1.0))
	return base * clampf(1.0 - level_cooldown * (level_of(move_id) - 1), 0.3, 1.0)


func cooldown_left(move_id: String) -> float:
	return float(cooldowns.get(move_id, 0.0))


## 0 = ready, 1 = just used.
func cooldown_frac(move_id: String) -> float:
	var total := cooldown_for(move_id)
	return clampf(cooldown_left(move_id) / maxf(total, 0.001), 0.0, 1.0)


func is_ready(kind: String) -> bool:
	var id := move_for(kind)
	return id != "" and cooldown_left(id) <= 0.0


func tick(dt: float) -> void:
	var haste := player.haste_mult if player != null else 1.0
	for id: String in cooldowns:
		if float(cooldowns[id]) > 0.0:
			cooldowns[id] = maxf(0.0, float(cooldowns[id]) - dt * haste)


## Called when a hold is first detected, so a move can react while the finger is down.
func begin_hold(ctx: Dictionary) -> void:
	if not is_ready("hold"):
		return
	var id := move_for("hold")
	weapon.begin_hold(id, def_of(id), ctx)


## Runs the move bound to ctx.kind. Returns "ok", "unbound", "cooldown" or "failed"
## (the move declined, e.g. Whirlwind with no charge).
func trigger(ctx: Dictionary) -> String:
	var kind := String(ctx["kind"])
	var id := move_for(kind)
	if id == "":
		return "unbound"
	if cooldown_left(id) > 0.0:
		return "cooldown"
	ctx["move"] = id
	ctx["level"] = level_of(id)
	ctx["power"] = float(ctx.get("power", 1.0)) * power(id)
	if not weapon.perform_move(id, def_of(id), ctx):
		return "failed"
	cooldowns[id] = cooldown_for(id)
	performed += 1
	by_move[id] = int(by_move.get(id, 0)) + 1
	return "ok"
