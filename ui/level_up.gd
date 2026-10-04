class_name LevelUpUI
extends CanvasLayer
## Pause-time card picker: 3 big thumb-friendly cards. Emits `picked(option)`.

signal picked(option: Dictionary)

var _root: Control
var _title: Label
var _cards: VBoxContainer
var _options: Array[Dictionary] = []
var _open_time: int = 0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.add_child(UIKit.bg_rect("ui.bg", 0.78))
	var m := UIKit.safe_margin(get_viewport(), 28)
	_root.add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	m.add_child(v)
	_title = UIKit.label("LEVEL UP", 52, "ui.accent")
	v.add_child(_title)
	v.add_child(UIKit.label("Choose one", 24, "ui.text_dim"))
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 18)
	v.add_child(_cards)
	visible = false


func is_open() -> bool:
	return visible


func show_options(options: Array[Dictionary], level: int) -> void:
	_options = options
	_title.text = "LEVEL %d" % level
	for c in _cards.get_children():
		c.queue_free()
	for k in options.size():
		var o := options[k]
		var cur := int(o["cur"])
		var tag := ""
		match String(o["kind"]):
			"weapon":
				tag = "WEAPON"
			"sub":
				tag = "SUB-WEAPON"
			"passive":
				tag = "PASSIVE"
			_:
				tag = "SUPPLY"
		var lvl_text := "NEW" if cur == 0 and String(o["kind"]) != "heal" else ("Lv %d → %d" % [cur, cur + 1] if int(o["max"]) > 0 else "")
		var b := UIKit.button("", 30, false, 150)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_left = 26
		vb.offset_right = -26
		vb.offset_top = 14
		vb.offset_bottom = -14
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 4)
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_l := UIKit.label(String(o["name"]), 34, "ui.text", HORIZONTAL_ALIGNMENT_LEFT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lvl_l := UIKit.label(lvl_text, 26, "ui.accent", HORIZONTAL_ALIGNMENT_RIGHT)
		lvl_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(name_l)
		head.add_child(lvl_l)
		vb.add_child(head)
		var tag_l := UIKit.label(tag, 18, "ui.accent2", HORIZONTAL_ALIGNMENT_LEFT)
		tag_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tag_l)
		var desc_l := UIKit.label(String(o["desc"]), 24, "ui.text_dim", HORIZONTAL_ALIGNMENT_LEFT)
		desc_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(desc_l)
		b.add_child(vb)
		b.pressed.connect(_on_pressed.bind(k))
		_cards.add_child(b)
	_open_time = Time.get_ticks_msec()
	visible = true


func _on_pressed(k: int) -> void:
	# ignore taps that land in the first instant (thumb still down from moving)
	if Time.get_ticks_msec() - _open_time < 250:
		return
	visible = false
	picked.emit(_options[k])
