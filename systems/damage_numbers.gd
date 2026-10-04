class_name DamageNumbers
extends Node2D
## Pooled floating text (damage numbers, "KO!" popups). Hard cap; oldest gets recycled.

var cap: int = 60
var life_time: float = 0.6
var npos := PackedVector2Array()
var nlife := PackedFloat32Array()
var nsize := PackedInt32Array()
var ncol := PackedColorArray()
var ntext: Array[String] = []
var _cursor: int = 0
var _font: Font
var _last_small_time: float = 0.0
var _clock: float = 0.0


func setup(p_cap: int, p_life: float) -> void:
	cap = p_cap
	life_time = p_life
	npos.resize(cap)
	nlife.resize(cap)
	nlife.fill(0.0)
	nsize.resize(cap)
	ncol.resize(cap)
	ntext.resize(cap)
	_font = ThemeDB.fallback_font


func add(p: Vector2, text: String, col: Color, size: int = 22, force: bool = true) -> void:
	# Crowd control: small numbers are rate-limited so big hits stay readable.
	if not force:
		if _clock - _last_small_time < 0.035:
			return
		_last_small_time = _clock
	var i := _cursor
	_cursor = (_cursor + 1) % cap
	npos[i] = p + Vector2(randf_range(-10, 10), randf_range(-8, 4))
	nlife[i] = life_time
	nsize[i] = size
	ncol[i] = col
	ntext[i] = text


func active_count() -> int:
	var n := 0
	for i in cap:
		if nlife[i] > 0.0:
			n += 1
	return n


func step(dt: float) -> void:
	_clock += dt
	for i in cap:
		if nlife[i] > 0.0:
			nlife[i] -= dt
			npos[i] += Vector2(0, -60.0 * dt)
	queue_redraw()


func _draw() -> void:
	for i in cap:
		var l := nlife[i]
		if l <= 0.0:
			continue
		var t := l / life_time
		var c := ncol[i]
		c.a = clampf(t * 1.6, 0.0, 1.0)
		var pop := 1.0 + 0.35 * clampf((t - 0.75) * 4.0, 0.0, 1.0)
		var sz := int(nsize[i] * pop)
		var w := _font.get_string_size(ntext[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var p := npos[i] - Vector2(w * 0.5, 0)
		draw_string_outline(_font, p, ntext[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(0, 0, 0, c.a * 0.85))
		draw_string(_font, p, ntext[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)
