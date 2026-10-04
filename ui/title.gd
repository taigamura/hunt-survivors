extends Control
## Title screen.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Engine.time_scale = 1.0
	get_tree().paused = false
	add_child(SwarmBackdrop.new())
	var m := UIKit.safe_margin(get_viewport(), 40)
	add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	m.add_child(v)

	var t1 := UIKit.label("HUNT", 120, "ui.accent")
	var t2 := UIKit.label("SURVIVORS", 64, "ui.text")
	v.add_child(t1)
	v.add_child(t2)
	v.add_child(UIKit.label("One thumb to move. One to fight. A thousand foes.", 26, "ui.text_dim", HORIZONTAL_ALIGNMENT_CENTER, true))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 120)
	v.add_child(gap)

	var start := UIKit.button("START HUNT", 44, true, 120)
	start.name = "StartButton"
	start.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/weapon_select.tscn"))
	v.add_child(start)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 40)
	v.add_child(gap2)
	v.add_child(UIKit.label("Best", 24, "ui.text_dim"))
	for w in GameState.WEAPONS:
		var b := Save.best_for(w)
		var nm := String(Tuning.g("weapons.%s.name" % w, w))
		var line := "%s — %s KOs" % [nm, UIKit.fmt_int(int(b["kos"]))]
		if float(b["time"]) > 0.0:
			line += "  ·  fastest %s" % UIKit.fmt_time(float(b["time"]))
		v.add_child(UIKit.label(line, 24, "ui.text"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode in [KEY_ENTER, KEY_SPACE]:
		get_tree().change_scene_to_file("res://ui/weapon_select.tscn")
