class_name Particles
extends Node2D
## Pooled, capped square particles (death pops, sparks). Ring buffer: oldest is overwritten.

var cap: int = 350
var ppos := PackedVector2Array()
var pvel := PackedVector2Array()
var plife := PackedFloat32Array()
var pmax := PackedFloat32Array()
var psize := PackedFloat32Array()
var pcol := PackedColorArray()
var _cursor: int = 0
var alive: int = 0


func setup(p_cap: int) -> void:
	cap = p_cap
	ppos.resize(cap)
	pvel.resize(cap)
	plife.resize(cap)
	plife.fill(0.0)
	pmax.resize(cap)
	psize.resize(cap)
	pcol.resize(cap)


func burst(p: Vector2, col: Color, n: int, speed: float = 160.0, size: float = 5.0, life: float = 0.35) -> void:
	for k in n:
		var i := _cursor
		_cursor = (_cursor + 1) % cap
		ppos[i] = p
		pvel[i] = Vector2.from_angle(randf() * TAU) * speed * randf_range(0.4, 1.0)
		plife[i] = life * randf_range(0.7, 1.0)
		pmax[i] = plife[i]
		psize[i] = size * randf_range(0.7, 1.2)
		pcol[i] = col


func step(dt: float) -> void:
	var drag := exp(-5.0 * dt)
	alive = 0
	for i in cap:
		if plife[i] > 0.0:
			plife[i] -= dt
			ppos[i] += pvel[i] * dt
			pvel[i] *= drag
			alive += 1
	queue_redraw()


func _draw() -> void:
	for i in cap:
		var l := plife[i]
		if l > 0.0:
			var t := l / pmax[i]
			var s := psize[i] * (0.4 + 0.6 * t)
			var c := pcol[i]
			c.a *= t
			draw_rect(Rect2(ppos[i] - Vector2(s, s) * 0.5, Vector2(s, s)), c)
