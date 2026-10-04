extends Control
## Two big weapon cards, each with a one-line description of its movement mechanic.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(SwarmBackdrop.new())
	var m := UIKit.safe_margin(get_viewport(), 36)
	add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 26)
	m.add_child(v)
	v.add_child(UIKit.label("CHOOSE YOUR WEAPON", 46, "ui.accent"))
	v.add_child(UIKit.label("Your movement is your combo.", 24, "ui.text_dim"))

	for w in GameState.WEAPONS:
		v.add_child(_card(w))

	var back := UIKit.button("Back", 30, false, 84)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/title.tscn"))
	v.add_child(back)


func _card(w: String) -> Button:
	var cfg := Tuning.d("weapons." + w)
	var b := UIKit.button("", 30, false, 300)
	b.name = "Card_" + w
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 30
	vb.offset_right = -30
	vb.offset_top = 22
	vb.offset_bottom = -22
	vb.add_theme_constant_override("separation", 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := WeaponIcon.new()
	icon.weapon = w
	icon.custom_minimum_size = Vector2(0, 90)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(icon)
	var nm := UIKit.label(String(cfg.get("name", w)).to_upper(), 44, "ui.text")
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)
	var tag := UIKit.label(String(cfg.get("tagline", "")), 26, "ui.accent2")
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tag)
	var best := Save.best_for(w)
	var bl := UIKit.label("Best: %s KOs" % UIKit.fmt_int(int(best["kos"])), 22, "ui.text_dim")
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(bl)
	b.add_child(vb)
	b.pressed.connect(func() -> void:
		GameState.selected_weapon = w
		get_tree().change_scene_to_file("res://scenes/hunt.tscn"))
	return b


class WeaponIcon:
	extends Control
	## Tiny animated diagram of the weapon's movement mechanic.
	var weapon: String = ""

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var t := Time.get_ticks_msec() / 1000.0
		var pc := ArtRegistry.tint("player.body")
		if weapon == "great_sword":
			var phase := fmod(t, 2.4)
			var charge := clampf(phase / 1.5, 0.0, 1.0)
			var col := ArtRegistry.color("fx.charge%d" % mini(3, int(charge * 3.0 + 0.001)))
			draw_arc(c, 30, -PI * 0.5, -PI * 0.5 + TAU * charge, 32, col, 6.0)
			draw_circle(c, 14, pc)
			if phase > 1.6:
				var a := clampf((phase - 1.6) / 0.8, 0.0, 1.0)
				var cc := ArtRegistry.color("fx.slash_gs3")
				cc.a *= 1.0 - a
				draw_colored_polygon(FX.pie(c, Vector2.RIGHT, 40 + 50 * a, 1.6), cc)
		else:
			var x := fmod(t * 160.0, size.x + 80.0) - 40.0
			var p := Vector2(x, c.y)
			for k in 5:
				var tc := ArtRegistry.color("fx.trail")
				tc.a *= 1.0 - k / 5.0
				draw_circle(p - Vector2(18 * (k + 1), 0), 12, tc)
			var wc := ArtRegistry.color("fx.whirl")
			for k in 3:
				var a := t * 14.0 + TAU * k / 3.0
				draw_line(p + Vector2.from_angle(a) * 30 - Vector2.from_angle(a + PI * 0.5) * 9, p + Vector2.from_angle(a) * 30 + Vector2.from_angle(a + PI * 0.5) * 9, wc, 4.0)
			draw_circle(p, 14, pc)
