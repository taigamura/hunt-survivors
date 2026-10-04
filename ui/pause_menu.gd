class_name PauseMenu
extends CanvasLayer
## Resume / your gesture bindings / settings (screen shake, haptics, move-stick side) / quit.

signal resumed
signal quit_requested
signal side_changed

var _shake_btn: Button
var _haptic_btn: Button
var _side_btn: Button
var _gestures_lbl: Label


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(UIKit.bg_rect("ui.bg", 0.85))
	var m := UIKit.safe_margin(get_viewport(), 48)
	root.add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 20)
	m.add_child(v)
	v.add_child(UIKit.label("PAUSED", 56, "ui.accent"))
	var resume := UIKit.button("Resume", 36, true)
	resume.pressed.connect(func() -> void: resumed.emit())
	v.add_child(resume)
	_gestures_lbl = UIKit.label("", 24, "ui.text", HORIZONTAL_ALIGNMENT_CENTER, true)
	v.add_child(_gestures_lbl)
	v.add_child(UIKit.label("Settings", 26, "ui.text_dim"))
	_shake_btn = UIKit.button("", 30)
	_shake_btn.pressed.connect(func() -> void:
		GameState.shake_mode = (GameState.shake_mode + 1) % 3
		_refresh())
	v.add_child(_shake_btn)
	_haptic_btn = UIKit.button("", 30)
	_haptic_btn.pressed.connect(func() -> void:
		GameState.haptics = not GameState.haptics
		_refresh())
	v.add_child(_haptic_btn)
	_side_btn = UIKit.button("", 30)
	_side_btn.pressed.connect(func() -> void:
		GameState.stick_left = not GameState.stick_left
		side_changed.emit()
		_refresh())
	v.add_child(_side_btn)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	v.add_child(spacer)
	var quit := UIKit.button("Quit to Title", 30)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	v.add_child(quit)
	visible = false
	_refresh()


## `gestures`: one line per bound gesture, e.g. "TAP  Tackle  Lv 2".
func open(gestures: String = "") -> void:
	_gestures_lbl.text = gestures
	_gestures_lbl.visible = gestures != ""
	_refresh()
	visible = true


func close() -> void:
	visible = false
	Save.write()


func _refresh() -> void:
	if _shake_btn == null:
		return
	_shake_btn.text = "Screen Shake: %s" % GameState.shake_label()
	_haptic_btn.text = "Haptics: %s" % ("On" if GameState.haptics else "Off")
	_side_btn.text = "Move Stick: %s" % ("Left" if GameState.stick_left else "Right")
