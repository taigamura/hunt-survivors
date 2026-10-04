class_name UpgradePool
extends RefCounted
## Builds level-up card options (main-weapon upgrades, gesture moves, sub-weapons, passives)
## and applies picks. Gesture cards: "move" levels up a bound move; "gesture" unlocks a shape
## gesture (circle, v, zigzag, triangle) bound to a move you don't have yet.

const SUB_IDS: Array[String] = ["orbit_shards", "thunder_call", "flame_wake"]

var hunt: HuntContext
var player: Player
var main: Weapon
var moves: MoveSet
var subs: Array[Weapon] = []
var passive_levels: Dictionary = {}
var passive_defs: Array = []
var max_subs: int = 3
var heal_frac: float = 0.3
var shape_min_level: int = 3
var picks: Array[String] = []  ## history, for tests/telemetry


func setup(p_hunt: HuntContext, p_player: Player, p_main: Weapon, p_moves: MoveSet = null) -> void:
	hunt = p_hunt
	player = p_player
	main = p_main
	moves = p_moves
	shape_min_level = Tuning.i("moves.shape_unlock_min_level", 3)
	passive_defs = Tuning.a("passives")
	max_subs = Tuning.i("max_subweapons", 3)
	heal_frac = Tuning.f("fallback_heal_frac", 0.3)


static func make_sub(sub_id: String) -> Weapon:
	match sub_id:
		"orbit_shards":
			return OrbitShards.new()
		"thunder_call":
			return ThunderCall.new()
		"flame_wake":
			return FlameWake.new()
	return null


func sub_by_id(sub_id: String) -> Weapon:
	for s in subs:
		if s.id == sub_id:
			return s
	return null


func passive_level(pid: String) -> int:
	return int(passive_levels.get(pid, 0))


## `level` gates shape-gesture cards; `rng` picks which shape/move pair is offered.
func all_options(rng: RandomNumberGenerator = null, level: int = 99) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if moves != null:
		for mid in moves.upgradable_moves():
			var md := moves.def_of(mid)
			var cur := moves.level_of(mid)
			out.append({"kind": "move", "id": mid, "name": String(md["name"]), "desc": "Move: +%d%% damage, %d%% faster cooldown" % [int(moves.level_damage * 100.0 + 0.5), int(moves.level_cooldown * 100.0 + 0.5)], "cur": cur, "max": moves.max_level, "weight": 0.9})
		var shapes := moves.unbound_shapes()
		var free_moves := moves.unbound_moves()
		if level >= shape_min_level and not shapes.is_empty() and not free_moves.is_empty():
			var g := shapes[rng.randi() % shapes.size()] if rng != null else shapes[0]
			var mid := free_moves[rng.randi() % free_moves.size()] if rng != null else free_moves[0]
			var md := moves.def_of(mid)
			out.append({"kind": "gesture", "id": "%s:%s" % [g, mid], "gesture": g, "move": mid, "name": "%s: %s" % [MoveSet.gesture_label(g).capitalize(), String(md["name"])], "desc": "Draw a %s to %s" % [MoveSet.gesture_label(g).to_lower(), String(md["desc"]).substr(0, 1).to_lower() + String(md["desc"]).substr(1)], "cur": 0, "max": 1, "weight": 1.3})
	for d: Dictionary in main.upgrade_defs:
		var cur := main.up(String(d["id"]))
		if cur < int(d["max"]):
			out.append({"kind": "weapon", "id": d["id"], "name": d["name"], "desc": d["desc"], "cur": cur, "max": int(d["max"]), "weight": 1.4})
	for sid in SUB_IDS:
		var cfg := Tuning.d("subweapons." + sid)
		var owned := sub_by_id(sid)
		if owned != null:
			if owned.level < 5:
				out.append({"kind": "sub", "id": sid, "name": cfg["name"], "desc": cfg["desc"], "cur": owned.level, "max": 5, "weight": 1.1})
		elif subs.size() < max_subs:
			out.append({"kind": "sub", "id": sid, "name": cfg["name"], "desc": cfg["desc"], "cur": 0, "max": 5, "weight": 1.25})
	for d: Dictionary in passive_defs:
		var cur := passive_level(String(d["id"]))
		if cur < int(d["max"]):
			out.append({"kind": "passive", "id": d["id"], "name": d["name"], "desc": d["desc"], "cur": cur, "max": int(d["max"]), "weight": 1.0})
	return out


func roll(rng: RandomNumberGenerator, n: int = 3, level: int = 99) -> Array[Dictionary]:
	var pool := all_options(rng, level)
	var picked: Array[Dictionary] = []
	while picked.size() < n and not pool.is_empty():
		var total := 0.0
		for o in pool:
			total += float(o["weight"])
		var r := rng.randf() * total
		var idx := 0
		for k in pool.size():
			r -= float(pool[k]["weight"])
			if r <= 0.0:
				idx = k
				break
		picked.append(pool[idx])
		pool.remove_at(idx)
	if picked.is_empty():
		picked.append({"kind": "heal", "id": "heal", "name": "Field Ration", "desc": "Recover %d%% HP" % int(heal_frac * 100), "cur": 0, "max": 0, "weight": 1.0})
	return picked


func apply(opt: Dictionary) -> void:
	var oid := String(opt["id"])
	picks.append(oid)
	match String(opt["kind"]):
		"weapon":
			main.apply_upgrade(oid)
		"move":
			moves.upgrade(oid)
		"gesture":
			moves.bind(String(opt["gesture"]), String(opt["move"]))
		"sub":
			var owned := sub_by_id(oid)
			if owned != null:
				owned.level = mini(owned.level + 1, 5)
			else:
				var w := make_sub(oid)
				w.setup(hunt, player)
				w.level = 1
				subs.append(w)
				player.weapons.append(w)
		"passive":
			passive_levels[oid] = passive_level(oid) + 1
			_recompute_passives()
		"heal":
			player.heal(player.max_hp * heal_frac)


func _per_level(pid: String) -> float:
	for d: Dictionary in passive_defs:
		if String(d["id"]) == pid:
			return float(d["per_level"])
	return 0.0


func _recompute_passives() -> void:
	player.dmg_mult = 1.0 + _per_level("p_damage") * passive_level("p_damage")
	player.area_mult = 1.0 + _per_level("p_area") * passive_level("p_area")
	player.haste_mult = 1.0 + _per_level("p_haste") * passive_level("p_haste")
	player.speed_mult = 1.0 + _per_level("p_speed") * passive_level("p_speed")
	player.magnet_mult = 1.0 + _per_level("p_magnet") * passive_level("p_magnet")
	player.regen = _per_level("p_regen") * passive_level("p_regen")
	player.bonus_hp = _per_level("p_hp") * passive_level("p_hp")
	player.recompute_max_hp()
