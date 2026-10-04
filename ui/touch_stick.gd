class_name TouchStick
extends Control
## Floating move stick: touch anywhere in the lower 70% of the stick's half of the screen
## (left by default; the other half is the GesturePad) to set the origin, drag to move,
## release to stop. Mouse drag works on desktop via touch emulation.

var radius: float = 90.0
var zone_top: float = 0.3
var origin: Vector2 = Vector2.ZERO
var current: Vector2 = Vector2.ZERO
var touch_index: int = -1
var blocked_rects: Array[Rect2] = []
var stick_left: bool = true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	radius = Tuning.f("controls.joystick_radius", 90.0)
	zone_top = Tuning.f("controls.joystick_zone_top", 0.3)


func is_active() -> bool:
	return touch_index >= 0


func reset() -> void:
	touch_index = -1
	queue_redraw()


## Raw stick vector, length 0..1 (dead zone / response curve applied by the hunt).
func raw_vector() -> Vector2:
	if touch_index < 0:
		return Vector2.ZERO
	return ((current - origin) / radius).limit_length(1.0)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and touch_index < 0:
			var p := t.position
			var vs := get_viewport_rect().size
			if p.y < vs.y * zone_top:
				return
			if (p.x >= vs.x * 0.5) == stick_left:
				return
			for r in blocked_rects:
				if r.has_point(p):
					return
			touch_index = t.index
			origin = p
			current = p
			queue_redraw()
		elif not t.pressed and t.index == touch_index:
			reset()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == touch_index:
			current = d.position
			# floating: drag the base along if the thumb wanders far
			var off := current - origin
			if off.length() > radius * 1.35:
				origin = current - off.normalized() * radius * 1.35
			queue_redraw()


func _draw() -> void:
	if touch_index < 0:
		return
	var off := (current - origin).limit_length(radius)
	draw_circle(origin, radius, Color(1, 1, 1, 0.07))
	draw_arc(origin, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.3), 3.0)
	draw_circle(origin + off, radius * 0.42, Color(1, 1, 1, 0.28))
	draw_arc(origin + off, radius * 0.42, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 3.0)
