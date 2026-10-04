extends Node
## End-to-end screen flow: Title -> Weapon Select -> Loadout -> Hunt -> (forced win) -> Results.
## Presses the real buttons. Works headless:
##   godot --headless --path . res://tools/flow_check.tscn

var failures: PackedStringArray = []


func _ready() -> void:
	# Step out of the way so change_scene_to_file() doesn't free this driver.
	var title: Node = (load("res://ui/title.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(title)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = title
	await _frames(5)
	_press("StartButton")
	await _frames(10)
	_expect_scene("weapon_select")
	_press("Card_dual_blades")
	await _frames(10)
	_expect_scene("loadout")
	_press("Row_tap")  # cycle the tap move once; the hunt must use the new choice
	await _frames(2)
	var want := String(Save.loadout_for("dual_blades").get("tap", ""))
	var chosen := String((get_tree().current_scene.get("loadout") as Dictionary).get("tap", ""))
	_press("StartHunt")
	await _frames(20)
	_expect_scene("hunt")
	var hunt := get_tree().current_scene as Hunt
	if hunt != null:
		if hunt.weapon_id != "dual_blades":
			failures.append("hunt started with %s" % hunt.weapon_id)
		if chosen == want or hunt.moves.move_for("tap") != chosen:
			failures.append("loadout not applied: chose %s, hunt has %s" % [chosen, hunt.moves.move_for("tap")])
		await _frames(60)
		if hunt.run_time <= 0.5:
			failures.append("hunt did not run")
		hunt.end_run(true, "slain")
		await _frames(int(Tuning.f("run.end_delay", 2.0) * 60.0) + 30)
	_expect_scene("results")
	if not bool(GameState.last_result.get("won", false)):
		failures.append("result not recorded as a win")
	if failures.is_empty():
		print("FLOW PASS")
		get_tree().quit(0)
	else:
		for f in failures:
			print("FLOW FAIL: ", f)
		get_tree().quit(1)


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _press(node_name: String) -> void:
	var n := get_tree().current_scene.find_child(node_name, true, false)
	if n == null or not (n is BaseButton):
		failures.append("button %s not found in %s" % [node_name, get_tree().current_scene.name])
		return
	(n as BaseButton).pressed.emit()


func _expect_scene(fragment: String) -> void:
	var cs := get_tree().current_scene
	var path := cs.scene_file_path if cs != null else ""
	if not path.contains(fragment):
		failures.append("expected scene %s, got %s" % [fragment, path])
	else:
		print("  at ", path)
