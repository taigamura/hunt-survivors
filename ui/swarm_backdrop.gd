class_name SwarmBackdrop
extends Control
## Decorative menu background: a lazy river of swarm silhouettes.

var pts: Array[Vector3] = []  ## x, y, speed
var _tex: Texture2D
var _tint: Color


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex = ArtRegistry.tex("enemy.grunt")
	_tint = ArtRegistry.tint("enemy.grunt")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 140:
		pts.append(Vector3(rng.randf_range(-100, 820), rng.randf_range(0, 1600), rng.randf_range(30, 90)))


func _process(delta: float) -> void:
	var w := size.x + 200.0
	for k in pts.size():
		var p := pts[k]
		p.x += p.z * delta
		if p.x > size.x + 60.0:
			p.x -= w
		pts[k] = p
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), ArtRegistry.color("ui.bg"))
	var c := _tint
	c.a = 0.22
	for p in pts:
		var y := fmod(p.y, maxf(size.y, 1.0))
		draw_texture_rect(_tex, Rect2(p.x, y, 26, 26), false, c)
