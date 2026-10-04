class_name FX
extends Node2D
## Transient procedural effects (slashes, rings, bolts, flames) + registered world drawers
## (telegraphs, outposts, trails). Colors always come from ArtRegistry ids.

const MAX_EFFECTS := 260

var effects: Array[Dictionary] = []
var drawers: Array[Callable] = []


func add_drawer(c: Callable) -> void:
	drawers.append(c)


func clear() -> void:
	effects.clear()


func _add(e: Dictionary) -> void:
	if effects.size() >= MAX_EFFECTS:
		effects.pop_front()
	e["max"] = e["life"]
	effects.append(e)


func arc(pos: Vector2, dir: Vector2, r: float, half: float, color_id: String, life: float = 0.18) -> void:
	_add({"kind": 0, "pos": pos, "dir": dir, "r": r, "half": half, "color": ArtRegistry.color(color_id), "life": life})


func ring(pos: Vector2, r: float, color_id: String, life: float = 0.3, width: float = 10.0, grow: float = 0.25) -> void:
	_add({"kind": 1, "pos": pos, "r": r, "w": width, "grow": grow, "color": ArtRegistry.color(color_id), "life": life})


func line(a: Vector2, b: Vector2, width: float, color_id: String, life: float = 0.15) -> void:
	_add({"kind": 2, "a": a, "b": b, "w": width, "color": ArtRegistry.color(color_id), "life": life})


func circle(pos: Vector2, r: float, color_id: String, life: float = 0.2) -> void:
	_add({"kind": 3, "pos": pos, "r": r, "color": ArtRegistry.color(color_id), "life": life})


func bolt(pos: Vector2, r: float, color_id: String, life: float = 0.22) -> void:
	var pts := PackedVector2Array()
	var top := pos + Vector2(randf_range(-40, 40), -520)
	for k in 9:
		var t := k / 8.0
		var p := top.lerp(pos, t)
		if k > 0 and k < 8:
			p.x += randf_range(-26, 26)
		pts.append(p)
	_add({"kind": 4, "pos": pos, "r": r, "pts": pts, "color": ArtRegistry.color(color_id), "life": life})


func flame(pos: Vector2, r: float, life: float) -> void:
	_add({"kind": 5, "pos": pos, "r": r, "color": ArtRegistry.color("fx.flame"), "life": life, "seed": randf() * TAU})


func step(dt: float) -> void:
	var k := 0
	while k < effects.size():
		var e := effects[k]
		e["life"] = float(e["life"]) - dt
		if float(e["life"]) <= 0.0:
			effects.remove_at(k)
		else:
			k += 1
	queue_redraw()


func _draw() -> void:
	for d in drawers:
		if d.is_valid():
			d.call(self)
	for e in effects:
		var life: float = e["life"]
		var mx: float = e["max"]
		var t := 1.0 - life / mx  # 0 -> 1 over lifetime
		var col: Color = e["color"]
		match int(e["kind"]):
			0:
				var c := col
				c.a *= 1.0 - t * t
				var r: float = float(e["r"]) * (0.85 + 0.15 * t)
				draw_colored_polygon(pie(e["pos"], e["dir"], r, e["half"], r * 0.35 * t), c)
			1:
				var c := col
				c.a *= 1.0 - t
				var r: float = float(e["r"]) * (1.0 - float(e["grow"]) + float(e["grow"]) * t)
				draw_arc(e["pos"], r, 0.0, TAU, 48, c, float(e["w"]) * (1.0 - t * 0.6))
			2:
				var c := col
				c.a *= 1.0 - t
				draw_line(e["a"], e["b"], c, float(e["w"]) * (1.0 - t * 0.5))
			3:
				var c := col
				c.a *= 1.0 - t
				draw_circle(e["pos"], float(e["r"]) * (0.6 + 0.4 * t), c)
			4:
				var c := col
				c.a *= 1.0 - t
				draw_polyline(e["pts"], c, 6.0 * (1.0 - t) + 2.0)
				draw_circle(e["pos"], float(e["r"]) * (0.4 + 0.6 * t), Color(c.r, c.g, c.b, c.a * 0.35))
			5:
				var c := col
				var fade := clampf(life / 0.4, 0.0, 1.0)
				var flick := 0.85 + 0.15 * sin(float(e["seed"]) + life * 18.0)
				c.a *= fade
				draw_circle(e["pos"], float(e["r"]) * flick, c)
				draw_circle(e["pos"], float(e["r"]) * 0.55 * flick, Color(1.0, 0.85, 0.35, c.a * 0.8))


## Pie-slice polygon; inner > 0 makes it a thick arc band.
static func pie(center: Vector2, dir: Vector2, r: float, half: float, inner: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var a0 := dir.angle() - half
	var seg := maxi(6, int(half * 14.0))
	for k in seg + 1:
		var a := a0 + (half * 2.0) * k / seg
		pts.append(center + Vector2.from_angle(a) * r)
	if inner <= 0.5:
		pts.append(center)
	else:
		for k in range(seg, -1, -1):
			var a := a0 + (half * 2.0) * k / seg
			pts.append(center + Vector2.from_angle(a) * inner)
	return pts
