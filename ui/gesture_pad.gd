class_name GesturePad
extends Control
## Second-thumb gesture surface: the half of the screen opposite the move stick, below the HUD
## band. Tracks one stroke at a time, detects holds live (finger down and still), classifies
## everything else on release (GestureRecognizer), and emits `gestured(ev)`:
##   {"kind": String, "dir": Vector2 (unit, screen), "center": Vector2 (screen),
##    "aim": Vector2 (hold only: drag offset, ZERO = no aim), "hold_time": float}
## Also draws the live stroke trail, the hold-aim arrow, and a short label for what fired.

signal gestured(ev: Dictionary)
signal hold_started

var stick_left: bool = true
var zone_top: float = 0.14
var hold_time: float = 0.3
var hold_max_dist: float = 22.0
var aim_dead_zone: float = 24.0
var blocked_rects: Array[Rect2] = []
var rec := GestureRecognizer.new()

var touch_index: int = -1
var points := PackedVector2Array()
var down_msec: int = 0
var holding: bool = false
var hold_origin: Vector2 = Vector2.ZERO
var hold_current: Vector2 = Vector2.ZERO
var _moved_far: bool = false
var _scale: float = 1.0
var _last_msec: int = 0

# feedback
var _fade_points := PackedVector2Array()
var _fade_t: float = 0.0
var _label: String = ""
var _label_pos: Vector2 = Vector2.ZERO
var _label_col: Color = Color.WHITE
var _label_t: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_top = Tuning.f("gestures.zone_top", 0.14)
	hold_time = Tuning.f("gestures.hold_time", 0.3)
	hold_max_dist = Tuning.f("gestures.hold_max_dist", 22.0)
	aim_dead_zone = Tuning.f("gestures.aim_dead_zone", 24.0)
	_scale = get_viewport_rect().size.y / 1280.0
	rec.setup(_scale)


func is_active() -> bool:
	return touch_index >= 0


func reset() -> void:
	touch_index = -1
	holding = false
	points.clear()
	queue_redraw()


## Hold aim as a unit screen direction, or ZERO while inside the aim dead zone.
func hold_aim() -> Vector2:
	var off := hold_current - hold_origin
	if not holding or off.length() < aim_dead_zone * _scale:
		return Vector2.ZERO
	return off.normalized()


func in_zone(p: Vector2) -> bool:
	var sz := get_viewport_rect().size
	if p.y < sz.y * zone_top:
		return false
	if stick_left and p.x < sz.x * 0.5:
		return false
	if not stick_left and p.x >= sz.x * 0.5:
		return false
	for r in blocked_rects:
		if r.has_point(p):
			return false
	return true


## Short label at the last stroke ("TACKLE", "2.1s", "?").
func feedback(text: String, col: Color) -> void:
	_label = text
	_label_col = col
	_label_t = 0.7
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and touch_index < 0:
			if not in_zone(t.position):
				return
			touch_index = t.index
			points.clear()
			points.append(t.position)
			down_msec = Time.get_ticks_msec()
			holding = false
			_moved_far = false
			hold_origin = t.position
			hold_current = t.position
			queue_redraw()
		elif not t.pressed and t.index == touch_index:
			points.append(t.position)
			_finish()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index != touch_index:
			return
		if holding:
			hold_current = d.position
		else:
			points.append(d.position)
			if d.position.distance_to(points[0]) > hold_max_dist * _scale:
				_moved_far = true
		queue_redraw()


func _process(_delta: float) -> void:
	# feedback fades in real time (hit-stop and slow-mo scale the game delta)
	var now := Time.get_ticks_msec()
	var real_dt := clampf((now - _last_msec) / 1000.0, 0.0, 0.1)
	_last_msec = now
	if touch_index >= 0 and not holding and not _moved_far:
		if (Time.get_ticks_msec() - down_msec) / 1000.0 >= hold_time:
			holding = true
			hold_origin = points[0]
			hold_current = points[points.size() - 1]
			hold_started.emit()
	if _fade_t > 0.0:
		_fade_t -= real_dt
	if _label_t > 0.0:
		_label_t -= real_dt
	if touch_index >= 0 or _fade_t > 0.0 or _label_t > 0.0:
		queue_redraw()


func _finish() -> void:
	var ev: Dictionary
	if holding:
		var aim := hold_current - hold_origin
		ev = {"kind": GestureRecognizer.HOLD, "dir": aim.normalized() if aim.length() >= aim_dead_zone * _scale else Vector2.ZERO,
			"center": hold_origin, "aim": aim if aim.length() >= aim_dead_zone * _scale else Vector2.ZERO,
			"hold_time": (Time.get_ticks_msec() - down_msec) / 1000.0}
	else:
		ev = rec.classify(points)
		ev["aim"] = Vector2.ZERO
		ev["hold_time"] = 0.0
	_fade_points = points.duplicate()
	_fade_t = 0.25
	_label_pos = ev["center"]
	touch_index = -1
	holding = false
	points.clear()
	queue_redraw()
	gestured.emit(ev)


func _draw() -> void:
	var col := Color(1, 1, 1, 0.55)
	if _fade_t > 0.0 and _fade_points.size() >= 2:
		draw_polyline(_fade_points, Color(1, 1, 1, 0.5 * _fade_t / 0.25), 5.0 * _scale, true)
	if touch_index >= 0:
		if holding:
			var r := 34.0 * _scale
			draw_circle(hold_origin, r, Color(1, 1, 1, 0.12))
			draw_arc(hold_origin, r, 0.0, TAU, 32, col, 3.0 * _scale)
			var aim := hold_aim()
			if aim != Vector2.ZERO:
				var tip := hold_origin + aim * 90.0 * _scale
				draw_line(hold_origin, tip, col, 6.0 * _scale)
				var side := aim.orthogonal() * 14.0 * _scale
				draw_colored_polygon(PackedVector2Array([tip + aim * 18.0 * _scale, tip + side, tip - side]), col)
		elif points.size() >= 2:
			draw_polyline(points, col, 6.0 * _scale, true)
	if _label_t > 0.0 and _label != "":
		var font := ThemeDB.fallback_font
		var sz := int(30 * _scale)
		var c := _label_col
		c.a = clampf(_label_t / 0.3, 0.0, 1.0)
		var w := font.get_string_size(_label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var vp := get_viewport_rect().size
		var p := _label_pos + Vector2(-w * 0.5, -60.0 * _scale - (0.7 - _label_t) * 40.0 * _scale)
		p.x = clampf(p.x, 8.0, vp.x - w - 8.0)
		draw_string_outline(font, p, _label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, maxi(4, sz / 6), Color(0, 0, 0, c.a * 0.9))
		draw_string(font, p, _label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)
