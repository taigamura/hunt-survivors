extends Control
## Pre-hunt gesture loadout: which move each starting gesture (tap / swipe / hold) fires.
## Tapping a row cycles it through the weapon's move pool (moves already on another row are
## skipped). Shape gestures unlock mid-hunt from level-up cards. Saved per weapon.

var weapon: String = "great_sword"
var loadout: Dictionary = {}
var _rows: Dictionary = {}  ## kind -> {"name": Label, "desc": Label}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	weapon = GameState.selected_weapon
	loadout = Save.loadout_for(weapon)
	add_child(SwarmBackdrop.new())
	var m := UIKit.safe_margin(get_viewport(), 36)
	add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	m.add_child(v)
	v.add_child(UIKit.label("LOADOUT", 46, "ui.accent"))
	v.add_child(UIKit.label(String(Tuning.g("weapons.%s.name" % weapon, weapon)).to_upper(), 32, "ui.text"))
	var side := "Left thumb moves. Right thumb draws gestures." if GameState.stick_left else "Right thumb moves. Left thumb draws gestures."
	v.add_child(UIKit.label(side, 22, "ui.text_dim", HORIZONTAL_ALIGNMENT_CENTER, true))
	v.add_child(UIKit.label("Tap a gesture to change its move", 22, "ui.accent2"))

	for kind in MoveSet.start_gestures():
		v.add_child(_row(kind))

	var hint := UIKit.label("Level up to unlock shape gestures (circle, V, zigzag, triangle) with more moves. Any move fired just before Ironhorn's attack lands is a PERFECT counter.", 20, "ui.text_dim", HORIZONTAL_ALIGNMENT_CENTER, true)
	v.add_child(hint)

	var go := UIKit.button("HUNT!", 44, true, 116)
	go.name = "StartHunt"
	go.pressed.connect(func() -> void:
		Save.set_loadout(weapon, loadout)
		get_tree().change_scene_to_file("res://scenes/hunt.tscn"))
	v.add_child(go)
	var back := UIKit.button("Back", 30, false, 80)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/weapon_select.tscn"))
	v.add_child(back)


func _row(kind: String) -> Button:
	var b := UIKit.button("", 30, false, 150)
	b.name = "Row_" + kind
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18
	h.offset_right = -18
	h.offset_top = 12
	h.offset_bottom = -12
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := UIKit.Glyph.new()
	g.kind = kind
	g.color = ArtRegistry.color("ui.accent2")
	g.custom_minimum_size = Vector2(70, 70)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(g)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kl := UIKit.label(MoveSet.gesture_label(kind), 22, "ui.accent2", HORIZONTAL_ALIGNMENT_LEFT)
	kl.custom_minimum_size = Vector2(90, 0)
	kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(kl)
	var nl := UIKit.label("", 32, "ui.text", HORIZONTAL_ALIGNMENT_LEFT)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(nl)
	vb.add_child(head)
	var dl := UIKit.label("", 20, "ui.text_dim", HORIZONTAL_ALIGNMENT_LEFT, true)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(dl)
	h.add_child(vb)
	b.add_child(h)
	_rows[kind] = {"name": nl, "desc": dl}
	_refresh_row(kind)
	b.pressed.connect(func() -> void: cycle(kind))
	return b


## Next move in the pool for this gesture, skipping moves bound on other rows.
func cycle(kind: String) -> void:
	var ids := MoveSet.pool_ids(weapon)
	var taken := {}
	for k: String in loadout:
		if k != kind:
			taken[String(loadout[k])] = true
	var idx := ids.find(String(loadout.get(kind, "")))
	for step in range(1, ids.size() + 1):
		var cand := ids[(idx + step) % ids.size()]
		if not taken.has(cand):
			loadout[kind] = cand
			break
	_refresh_row(kind)


func _refresh_row(kind: String) -> void:
	var id := String(loadout.get(kind, ""))
	var def := {}
	for d in MoveSet.pool_defs(weapon):
		if String(d["id"]) == id:
			def = d
	var row: Dictionary = _rows[kind]
	(row["name"] as Label).text = String(def.get("name", "-"))
	(row["desc"] as Label).text = "%s  (%.1fs)" % [String(def.get("desc", "")), float(def.get("cooldown", 0.0))]
