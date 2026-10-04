extends Control
## Results: win/fail, time, KOs, officers, outposts, parts broken, level, new-best flags.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Engine.time_scale = 1.0
	get_tree().paused = false
	add_child(SwarmBackdrop.new())
	var r := GameState.last_result
	var won := bool(r.get("won", false))
	var m := UIKit.safe_margin(get_viewport(), 40)
	add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	m.add_child(v)

	v.add_child(UIKit.label("HUNT COMPLETE" if won else "HUNT FAILED", 64, "ui.accent" if won else "ui.danger"))
	var reason := String(r.get("reason", ""))
	var sub := "Ironhorn slain." if won else ("The monster escaped." if reason == "time" else "You fell in battle.")
	v.add_child(UIKit.label(sub, 28, "ui.text_dim"))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	v.add_child(gap)

	var big := UIKit.label(UIKit.fmt_int(int(r.get("kos", 0))) + " KOs", 84, "ui.accent")
	v.add_child(big)
	if bool(r.get("new_kos", false)):
		v.add_child(UIKit.label("NEW BEST!", 32, "ui.accent2"))

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.style(ArtRegistry.color("ui.panel"), Color(1, 1, 1, 0.1), 2))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 12)
	panel.add_child(grid)
	var rows := [
		["Weapon", String(Tuning.g("weapons.%s.name" % String(r.get("weapon", "great_sword")), "?"))],
		["Time", UIKit.fmt_time(float(r.get("time", 0.0))) + ("  (NEW FASTEST)" if bool(r.get("new_time", false)) else "")],
		["Officers defeated", str(int(r.get("officers", 0)))],
		["Outposts captured", "%d / %d" % [int(r.get("outposts", 0)), int(r.get("outposts_total", 3))]],
		["Parts broken", "%d / 3" % int(r.get("parts", 0))],
		["Max level", str(int(r.get("level", 1)))],
	]
	for row: Array in rows:
		grid.add_child(UIKit.label(String(row[0]), 28, "ui.text_dim", HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(UIKit.label(String(row[1]), 28, "ui.text", HORIZONTAL_ALIGNMENT_RIGHT))
	v.add_child(panel)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 40)
	v.add_child(gap2)
	var again := UIKit.button("HUNT AGAIN", 40, true, 110)
	again.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/hunt.tscn"))
	v.add_child(again)
	var swap := UIKit.button("Change Weapon", 30, false, 88)
	swap.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/weapon_select.tscn"))
	v.add_child(swap)
	var title := UIKit.button("Title", 30, false, 88)
	title.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/title.tscn"))
	v.add_child(title)
