extends Node
## Smoke run: plays the real Hunt with scripted bot input for each weapon and asserts
## no leaked nodes and KOs > 0. Prints telemetry useful for tuning.
##   godot --headless --path . --fixed-fps 60 res://tests/smoke.tscn [-- seconds=60 god=0 weapons=great_sword,dual_blades]
## Exit code 0 = pass. (The wrapper script also greps the log for SCRIPT ERROR.)

var seconds: float = 60.0
var weapons: PackedStringArray = ["great_sword", "dual_blades"]
var god: bool = false
var arrive: float = -1.0
var seed_value: int = 11

var hunt: Hunt
var idx: int = 0
var frames: int = 0
var max_frames: int = 0
var failures: PackedStringArray = []
var nodes_before: int = 0
var peak_enemies: int = 0
var fps_frames: int = 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"seconds":
				seconds = float(kv[1])
			"weapons":
				weapons = kv[1].split(",")
			"god":
				god = kv[1] == "1"
			"arrive":
				arrive = float(kv[1])
			"seed":
				seed_value = int(kv[1])
	max_frames = int(seconds * 60.0)
	_start()


func _start() -> void:
	nodes_before = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	hunt = Hunt.new()
	var cfg := {"mode": "smoke", "weapon": weapons[idx], "bot": true, "seed": seed_value + idx, "god": god}
	if arrive >= 0.0:
		cfg["arrive_time"] = arrive
	hunt.config = cfg
	add_child(hunt)
	frames = 0
	peak_enemies = 0


func _process(_d: float) -> void:
	if hunt == null:
		return
	frames += 1
	peak_enemies = maxi(peak_enemies, hunt.enemies.n_active)
	if frames % 600 == 0:
		_telemetry("t")
	if frames >= max_frames or (hunt.ended and hunt.end_timer <= 0.0):
		_finish()


func _telemetry(tag: String) -> void:
	var m := hunt.monster
	var mstate := "none" if m == null else "%s hp=%d/%d parts=%d enr=%s atk=%s dist=%d pos=%s cd=%.1f" % [m.state_name(), int(m.hp), int(m.max_hp), m.parts_broken, m.enraged, str(m.attacks_done), int(m.position.distance_to(hunt.player.position)), str(m.position.round()), m.attack_cd]
	print("  [%s %s %5.1fs] kos=%d foes=%d lvl=%d hp=%d/%d officers=%d outposts=%d musou=%d/%d monster=%s" % [
		tag, hunt.weapon_id, hunt.run_time, hunt.kos, hunt.enemies.n_active, hunt.progression.level,
		int(hunt.player.hp), int(hunt.player.max_hp), hunt.officers_defeated, hunt.outposts.captured_count(),
		hunt.musou.triggers, hunt.musou_blasts, mstate])


func _finish() -> void:
	_telemetry("END")
	var w := hunt.weapon_id
	var mw := hunt.main_weapon
	if mw is GreatSword:
		var gs := mw as GreatSword
		print("  great_sword releases=%d swipes=%d" % [gs.releases, gs.swipes])
		if gs.releases == 0:
			failures.append("%s: no charged releases" % w)
	elif mw is DualBlades:
		var db := mw as DualBlades
		print("  dual_blades whirl_ticks=%d dash_cuts=%d" % [db.whirl_ticks, db.dash_cuts])
		if db.whirl_ticks == 0:
			failures.append("%s: no whirl ticks" % w)
	print("  picks: %s" % ", ".join(hunt.pool.picks))
	print("  peak enemies=%d ended=%s won=%s reason=%s" % [peak_enemies, hunt.ended, hunt.won, hunt.end_reason])
	if hunt.kos <= 0:
		failures.append("%s: KOs == 0" % w)
	hunt.queue_free()
	hunt = null
	await get_tree().process_frame
	await get_tree().process_frame
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("  nodes before=%d after=%d orphans=%d" % [nodes_before, nodes_after, orphans])
	if nodes_after != nodes_before:
		failures.append("%s: leaked %d nodes" % [w, nodes_after - nodes_before])
	if orphans != 0:
		failures.append("%s: %d orphan nodes" % [w, orphans])
	idx += 1
	if idx < weapons.size():
		_start()
		return
	Engine.time_scale = 1.0
	if failures.is_empty():
		print("SMOKE PASS")
		get_tree().quit(0)
	else:
		for f in failures:
			print("SMOKE FAIL: ", f)
		get_tree().quit(1)
