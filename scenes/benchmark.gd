extends Node
## Headless swarm benchmark.
##   godot --headless --path . --fixed-fps 60 res://scenes/benchmark.tscn
## For each enemy count it fills the swarm around a hunter who runs a circle with Dual Blades
## (continuous whirl) + Orbiting Shards + Thunder Call firing, keeps the count topped up,
## runs 10 s of simulated time, and reports average / p95 per-frame cost:
##   sim   = weapon hit queries + flow field + swarm step (the 6 ms budget)
##   render = MultiMesh buffer fill (reported separately)
## Results are printed and written to user://bench.json.

const COUNTS: Array[int] = [500, 1000, 1500, 2000]
const FRAMES_PER_RUN := 600
const WARMUP := 30
const BUDGET_US := 6000

var hunt: Hunt
var count_idx: int = 0
var frame: int = 0
var samples_sim: PackedInt32Array = PackedInt32Array()
var samples_render: PackedInt32Array = PackedInt32Array()
var samples_step: PackedInt32Array = PackedInt32Array()
var samples_weapons: PackedInt32Array = PackedInt32Array()
var samples_field: PackedInt32Array = PackedInt32Array()
var results: Array[Dictionary] = []
var angle: float = 0.0


func _ready() -> void:
	hunt = Hunt.new()
	hunt.config = {"mode": "bench", "weapon": "dual_blades", "seed": 42, "god": true, "bot": false, "arrive_time": 1e9}
	hunt.input_override = _circle_input
	add_child(hunt)
	# give the hunter a realistic mid-game kit
	for sid in ["orbit_shards", "thunder_call"]:
		hunt.pool.apply({"kind": "sub", "id": sid})
		hunt.pool.apply({"kind": "sub", "id": sid})
		hunt.pool.apply({"kind": "sub", "id": sid})
	_start_run()


func _circle_input(dt: float) -> Vector2:
	# run a big circle around the map center at full deflection
	var p := hunt.player.position
	var to_center := -p
	var tangent := Vector2(-to_center.y, to_center.x).normalized() if p.length() > 1.0 else Vector2.RIGHT
	var radial := to_center.normalized() * clampf((p.length() - 600.0) / 300.0, -1.0, 1.0)
	return (tangent + radial).normalized()


func _start_run() -> void:
	hunt.enemies.clear_all()
	hunt.xp.count = 0
	frame = 0
	samples_sim.clear()
	samples_render.clear()
	samples_step.clear()
	samples_weapons.clear()
	samples_field.clear()
	hunt.fill_enemies(COUNTS[count_idx])


func _process(_delta: float) -> void:
	# top the swarm back up (kills are refilled) — runs before the Hunt child processes
	if frame > 0:
		hunt.fill_enemies(COUNTS[count_idx])
		if frame > WARMUP:
			samples_weapons.append(hunt.t_weapons_us)
			samples_field.append(hunt.t_field_us)
			samples_step.append(hunt.t_step_us)
			samples_sim.append(hunt.t_weapons_us + hunt.t_field_us + hunt.t_step_us)
			samples_render.append(hunt.t_render_us)
	frame += 1
	if frame > FRAMES_PER_RUN + WARMUP:
		_finish_run()


func _finish_run() -> void:
	var n := COUNTS[count_idx]
	var r := {
		"enemies": n,
		"sim_avg_ms": _avg(samples_sim) / 1000.0,
		"sim_p95_ms": _p95(samples_sim) / 1000.0,
		"weapons_avg_ms": _avg(samples_weapons) / 1000.0,
		"field_avg_ms": _avg(samples_field) / 1000.0,
		"step_avg_ms": _avg(samples_step) / 1000.0,
		"render_avg_ms": _avg(samples_render) / 1000.0,
		"render_p95_ms": _p95(samples_render) / 1000.0,
		"kos": hunt.kos,
	}
	results.append(r)
	print("  diag: ended=%s musou=%.2f pos=%s paused=%s weapons=%d frames=%d" % [hunt.ended, hunt.musou_timer, hunt.player.position, get_tree().paused, hunt.player.weapons.size(), hunt.frames])
	print("BENCH %4d enemies | sim avg %.2f ms  p95 %.2f ms  (weapons %.2f, field %.2f, step %.2f) | render avg %.2f ms  p95 %.2f ms" % [
		n, r["sim_avg_ms"], r["sim_p95_ms"], r["weapons_avg_ms"], r["field_avg_ms"], r["step_avg_ms"], r["render_avg_ms"], r["render_p95_ms"]])
	count_idx += 1
	if count_idx >= COUNTS.size():
		_report()
		return
	_start_run()


func _report() -> void:
	var pass_1500 := false
	for r in results:
		if int(r["enemies"]) == 1500:
			pass_1500 = float(r["sim_avg_ms"]) * 1000.0 <= BUDGET_US
	var out := {
		"engine": Engine.get_version_info()["string"],
		"cpu": OS.get_processor_name(),
		"cores": OS.get_processor_count(),
		"results": results,
		"budget_ms": BUDGET_US / 1000.0,
		"pass_1500": pass_1500,
	}
	var f := FileAccess.open("user://bench.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
	print("BENCH CPU: %s (%d cores)" % [OS.get_processor_name(), OS.get_processor_count()])
	print("BENCH RESULT: 1500-enemy budget %s" % ("PASS" if pass_1500 else "FAIL"))
	get_tree().quit(0 if pass_1500 else 2)


static func _avg(a: PackedInt32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


static func _p95(a: PackedInt32Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[int(floor((b.size() - 1) * 0.95))])
