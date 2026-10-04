extends Node
## ArtRegistry — the ONLY place visuals are defined.
##
## Every sprite, FX color and UI color is looked up by string id, e.g.
## "enemy.grunt", "monster.ironhorn.horns", "fx.slash_arc".
## Each entry: { texture: Texture2D|null, tint: Color, size: Vector2 (world px), rotate: bool }.
##
## Placeholder art is generated procedurally at startup. To swap in real art,
## add res://art/manifest.json mapping ids to files, e.g.
##   { "enemy.grunt": { "path": "res://art/grunt.png", "tint": "#ffffff", "size": [24, 24] } }
## Nothing else in the game needs to change.

const MANIFEST := "res://art/manifest.json"

var entries: Dictionary = {}


func _ready() -> void:
	_build_placeholders()
	_apply_manifest()


# ---------------------------------------------------------------- public API

## Re-applies a manifest file (used by tests; the game loads res://art/manifest.json at startup).
func apply_manifest(path: String) -> void:
	_apply_manifest(path)


func has_id(id: String) -> bool:
	return entries.has(id)


func entry(id: String) -> Dictionary:
	if not entries.has(id):
		if entries.is_empty():
			_build_placeholders()
		if not entries.has(id):
			push_warning("ArtRegistry: unknown id '%s'" % id)
			return {"texture": null, "tint": Color.MAGENTA, "size": Vector2(16, 16), "rotate": false}
	return entries[id]


func tex(id: String) -> Texture2D:
	return entry(id).get("texture") as Texture2D


func tint(id: String) -> Color:
	return entry(id).get("tint", Color.WHITE)


## Alias of tint() for color-only FX/UI entries.
func color(id: String) -> Color:
	return tint(id)


func size(id: String) -> Vector2:
	return entry(id).get("size", Vector2(16, 16))


func rotates(id: String) -> bool:
	return bool(entry(id).get("rotate", false))


## Convenience: configure a Sprite2D from a registry id (texture, tint, world size).
func apply_to_sprite(sprite: Sprite2D, id: String) -> void:
	var t := tex(id)
	sprite.texture = t
	sprite.modulate = tint(id)
	if t != null:
		var s := size(id)
		sprite.scale = Vector2(s.x / float(t.get_width()), s.y / float(t.get_height()))


# ------------------------------------------------------------- registration

func _put(id: String, texture: Texture2D, tint_color: Color, world_size: Vector2, rotate: bool = false) -> void:
	entries[id] = {"texture": texture, "tint": tint_color, "size": world_size, "rotate": rotate}


func _put_color(id: String, c: Color) -> void:
	entries[id] = {"texture": null, "tint": c, "size": Vector2.ZERO, "rotate": false}


func _apply_manifest(path: String = MANIFEST) -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return
	for id: String in (parsed as Dictionary):
		if not (parsed[id] is Dictionary):
			continue  # e.g. "_readme"
		var spec: Dictionary = parsed[id]
		var e: Dictionary = entries.get(id, {"texture": null, "tint": Color.WHITE, "size": Vector2(16, 16), "rotate": false}).duplicate()
		if spec.has("path"):
			var t: Texture2D = load(String(spec["path"]))
			if t != null:
				e["texture"] = t
		if spec.has("tint"):
			e["tint"] = Color(String(spec["tint"]))
		if spec.has("size"):
			var s: Array = spec["size"]
			e["size"] = Vector2(float(s[0]), float(s[1]))
		if spec.has("rotate"):
			e["rotate"] = bool(spec["rotate"])
		entries[id] = e


# ---------------------------------------------------------- placeholder art

const OUTLINE := Color(0.06, 0.06, 0.08, 1.0)


func _build_placeholders() -> void:
	# --- player
	_put("player.body", _paint(64, func(p: Vector2) -> float:
		return minf(_sd_circle(p, Vector2(30, 32), 22.0), _sd_poly(p, [Vector2(62, 32), Vector2(40, 18), Vector2(40, 46)])), 3.0),
		Color(0.92, 0.98, 1.0), Vector2(62, 62), true)

	# --- swarm (white fill, tinted per instance)
	_put("enemy.grunt", _paint(48, func(p: Vector2) -> float:
		return _sd_poly(p, [Vector2(44, 24), Vector2(8, 6), Vector2(16, 24), Vector2(8, 42)]), 3.5),
		Color(0.93, 0.33, 0.30), Vector2(48, 48), true)
	_put("enemy.runner", _paint(48, func(p: Vector2) -> float:
		return _sd_poly(p, [Vector2(46, 24), Vector2(4, 12), Vector2(14, 24), Vector2(4, 36)]), 3.5),
		Color(1.0, 0.62, 0.22), Vector2(46, 36), true)
	_put("enemy.brute", _paint(48, func(p: Vector2) -> float:
		return minf(_sd_box(p, Vector2(22, 24), Vector2(15, 17), 5.0), _sd_box(p, Vector2(40, 24), Vector2(5, 13), 2.0)), 3.5),
		Color(0.72, 0.42, 0.95), Vector2(68, 68), true)
	_put("enemy.officer", _paint(64, func(p: Vector2) -> float:
		var body := _sd_circle(p, Vector2(30, 42), 17.0)
		var pole := _sd_box(p, Vector2(44, 25), Vector2(2.5, 19), 1.0)
		var flag := _sd_poly(p, [Vector2(46, 6), Vector2(62, 12), Vector2(46, 19)])
		return minf(body, minf(pole, flag)), 3.0),
		Color(1.0, 0.82, 0.25), Vector2(92, 92), false)

	# --- pickups
	_put("xp.gem", _paint(32, func(p: Vector2) -> float:
		return _sd_poly(p, [Vector2(16, 2), Vector2(29, 16), Vector2(16, 30), Vector2(3, 16)]), 2.5),
		Color(0.35, 0.95, 0.85), Vector2(20, 20), false)
	_put_color("xp.tier0", Color(0.35, 0.95, 0.85))
	_put_color("xp.tier1", Color(0.4, 0.65, 1.0))
	_put_color("xp.tier2", Color(1.0, 0.45, 0.85))

	# --- world
	_put("obstacle.rock", _paint(128, func(p: Vector2) -> float:
		var s := _sd_circle(p, Vector2(64, 66), 44.0)
		s = minf(s, _sd_circle(p, Vector2(44, 52), 30.0))
		s = minf(s, _sd_circle(p, Vector2(86, 58), 30.0))
		s = minf(s, _sd_circle(p, Vector2(66, 88), 28.0))
		return s, 5.0, Color(0.42, 0.44, 0.47), Color(0.18, 0.19, 0.21)),
		Color(1, 1, 1), Vector2(128, 128), false)
	_put("ground.tile", _ground_tile(), Color(1, 1, 1), Vector2(256, 256), false)
	_put("outpost.flag", _paint(64, func(p: Vector2) -> float:
		var pole := _sd_box(p, Vector2(20, 34), Vector2(3, 28), 1.0)
		var flag := _sd_poly(p, [Vector2(23, 6), Vector2(60, 16), Vector2(23, 28)])
		return minf(pole, flag), 3.0),
		Color(1, 1, 1), Vector2(64, 64), false)
	_put_color("outpost.neutral", Color(0.75, 0.78, 0.82))
	_put_color("outpost.captured", Color(1.0, 0.82, 0.25))
	_put_color("outpost.progress", Color(0.45, 0.95, 0.6))

	# --- monster (drawn facing +x)
	var steel := Color(0.55, 0.68, 0.82)
	_put("monster.ironhorn.body", _paint_rect(Vector2i(192, 128), func(p: Vector2) -> float:
		return _sd_ellipse(p, Vector2(96, 64), Vector2(88, 56)), 5.0, Color(1, 1, 1), OUTLINE),
		steel, Vector2(230, 150), false)
	_put("monster.ironhorn.horns", _paint(96, func(p: Vector2) -> float:
		var h1 := _sd_poly(p, [Vector2(10, 30), Vector2(92, 8), Vector2(30, 46)])
		var h2 := _sd_poly(p, [Vector2(10, 66), Vector2(30, 50), Vector2(92, 88)])
		var head := _sd_circle(p, Vector2(22, 48), 22.0)
		return minf(head, minf(h1, h2)), 4.0, Color(0.95, 0.92, 0.85), OUTLINE),
		Color(1, 1, 1), Vector2(110, 110), false)
	_put("monster.ironhorn.horns_broken", _paint(96, func(p: Vector2) -> float:
		var h1 := _sd_poly(p, [Vector2(10, 32), Vector2(48, 26), Vector2(30, 46)])
		var h2 := _sd_poly(p, [Vector2(10, 64), Vector2(30, 50), Vector2(48, 70)])
		var head := _sd_circle(p, Vector2(22, 48), 22.0)
		return minf(head, minf(h1, h2)), 4.0, Color(0.7, 0.66, 0.6), OUTLINE),
		Color(1, 1, 1), Vector2(110, 110), false)
	_put("monster.ironhorn.back", _paint(128, func(p: Vector2) -> float:
		var s := _sd_poly(p, [Vector2(20, 64), Vector2(34, 20), Vector2(48, 64)])
		s = minf(s, _sd_poly(p, [Vector2(48, 64), Vector2(64, 10), Vector2(80, 64)]))
		s = minf(s, _sd_poly(p, [Vector2(80, 64), Vector2(94, 20), Vector2(108, 64)]))
		s = minf(s, _sd_box(p, Vector2(64, 76), Vector2(50, 16), 8.0))
		return s, 4.0, Color(0.8, 0.86, 0.95), OUTLINE),
		Color(1, 1, 1), Vector2(130, 130), false)
	_put("monster.ironhorn.back_broken", _paint(128, func(p: Vector2) -> float:
		var s := _sd_poly(p, [Vector2(24, 64), Vector2(34, 46), Vector2(44, 64)])
		s = minf(s, _sd_poly(p, [Vector2(84, 64), Vector2(94, 44), Vector2(104, 64)]))
		s = minf(s, _sd_box(p, Vector2(64, 76), Vector2(50, 16), 8.0))
		s = maxf(s, -_sd_box(p, Vector2(62, 76), Vector2(3, 18), 0.0))
		return s, 4.0, Color(0.55, 0.58, 0.64), OUTLINE),
		Color(1, 1, 1), Vector2(130, 130), false)
	_put("monster.ironhorn.tail", _paint_rect(Vector2i(128, 64), func(p: Vector2) -> float:
		var shaft := _sd_poly(p, [Vector2(126, 22), Vector2(26, 28), Vector2(26, 36), Vector2(126, 42)])
		var club := _sd_circle(p, Vector2(22, 32), 18.0)
		return minf(shaft, club), 4.0, Color(1, 1, 1), OUTLINE),
		steel, Vector2(150, 75), false)
	_put("monster.ironhorn.tail_broken", _paint_rect(Vector2i(128, 64), func(p: Vector2) -> float:
		return _sd_poly(p, [Vector2(126, 22), Vector2(86, 27), Vector2(80, 33), Vector2(86, 37), Vector2(126, 42)]), 4.0, Color(0.75, 0.75, 0.78), OUTLINE),
		steel, Vector2(150, 75), false)

	# --- FX palette (procedural shapes, colors live here)
	_put_color("fx.slash_arc", Color(1.0, 0.93, 0.7, 0.75))
	_put_color("fx.slash_gs1", Color(1.0, 0.9, 0.6, 0.7))
	_put_color("fx.slash_gs2", Color(1.0, 0.75, 0.35, 0.8))
	_put_color("fx.slash_gs3", Color(1.0, 0.98, 0.9, 0.95))
	_put_color("fx.swipe", Color(0.9, 0.9, 0.95, 0.45))
	_put_color("fx.shockwave", Color(1.0, 0.85, 0.45, 0.8))
	_put_color("fx.whirl", Color(0.55, 0.95, 1.0, 0.55))
	_put_color("fx.trail", Color(0.45, 0.85, 1.0, 0.45))
	_put_color("fx.dash", Color(0.85, 1.0, 1.0, 0.95))
	_put_color("fx.shard", Color(0.75, 0.97, 1.0, 1.0))
	_put_color("fx.bolt", Color(0.75, 0.88, 1.0, 1.0))
	_put_color("fx.flame", Color(1.0, 0.5, 0.15, 0.55))
	_put_color("fx.telegraph", Color(1.0, 0.15, 0.1, 0.32))
	_put_color("fx.telegraph_edge", Color(1.0, 0.3, 0.2, 0.9))
	_put_color("fx.gold", Color(1.0, 0.82, 0.3, 1.0))
	_put_color("fx.aim", Color(1.0, 1.0, 1.0, 0.55))
	_put_color("fx.tracer", Color(1.0, 0.95, 0.7, 0.85))
	_put_color("fx.tracer_heavy", Color(1.0, 0.75, 0.35, 0.95))
	_put_color("fx.explosion", Color(1.0, 0.6, 0.25, 0.85))
	_put_color("fx.shield", Color(0.55, 0.8, 1.0, 0.8))
	_put_color("fx.guard", Color(0.55, 0.8, 1.0, 0.35))
	_put_color("fx.death", Color(1.0, 0.55, 0.45, 1.0))
	_put_color("fx.part_break", Color(1.0, 0.95, 0.6, 1.0))
	_put_color("fx.charge0", Color(0.75, 0.75, 0.8, 0.5))
	_put_color("fx.charge1", Color(1.0, 0.9, 0.55, 0.9))
	_put_color("fx.charge2", Color(1.0, 0.7, 0.3, 0.95))
	_put_color("fx.charge3", Color(1.0, 1.0, 1.0, 1.0))
	_put_color("fx.momentum", Color(0.45, 0.95, 1.0, 0.95))
	_put_color("fx.enrage", Color(1.0, 0.45, 0.4, 1.0))
	_put_color("fx.monster_hit", Color(2.0, 2.0, 2.0, 1.0))
	_put_color("fx.enemy_flash", Color(4.0, 4.0, 4.0, 1.0))
	_put_color("fx.fleeing", Color(0.55, 0.55, 0.6, 0.7))

	# --- UI palette
	_put_color("ui.bg", Color(0.07, 0.08, 0.09))
	_put_color("ui.panel", Color(0.12, 0.13, 0.15, 0.96))
	_put_color("ui.panel_hi", Color(0.18, 0.2, 0.23, 1.0))
	_put_color("ui.accent", Color(1.0, 0.82, 0.25))
	_put_color("ui.accent2", Color(0.45, 0.95, 1.0))
	_put_color("ui.text", Color(0.95, 0.96, 0.98))
	_put_color("ui.text_dim", Color(0.62, 0.65, 0.7))
	_put_color("ui.danger", Color(1.0, 0.32, 0.28))
	_put_color("ui.hp", Color(0.4, 0.95, 0.5))
	_put_color("ui.xp", Color(0.35, 0.95, 0.85))
	_put_color("ui.monster_hp", Color(1.0, 0.35, 0.3))
	_put_color("ui.damage_num", Color(1.0, 1.0, 1.0))
	_put_color("ui.damage_num_big", Color(1.0, 0.85, 0.3))
	_put_color("ui.damage_num_monster", Color(1.0, 0.55, 0.4))
	_put_color("ui.ko_popup", Color(1.0, 0.9, 0.4))


# --------------------------------------------------------------- painters

func _paint(px: int, sdf: Callable, outline_px: float, fill: Color = Color.WHITE, outline: Color = OUTLINE) -> Texture2D:
	return _paint_rect(Vector2i(px, px), sdf, outline_px, fill, outline)


## Rasterizes a signed-distance function (negative = inside) with anti-aliased fill + outline.
func _paint_rect(dim: Vector2i, sdf: Callable, outline_px: float, fill: Color = Color.WHITE, outline: Color = OUTLINE) -> Texture2D:
	var img := Image.create(dim.x, dim.y, false, Image.FORMAT_RGBA8)
	for y in dim.y:
		for x in dim.x:
			var dist: float = sdf.call(Vector2(x + 0.5, y + 0.5))
			var alpha := clampf(0.5 - dist, 0.0, 1.0)
			if alpha <= 0.0:
				continue
			var inner := clampf(-dist - outline_px + 0.5, 0.0, 1.0)
			var c := outline.lerp(fill, inner)
			c.a = alpha
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _ground_tile() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var base := Color(0.13, 0.155, 0.14)
	for y in n:
		for x in n:
			var c := base
			var v := rng.randf_range(-0.012, 0.012)
			c = Color(c.r + v, c.g + v, c.b + v)
			if x == 0 or y == 0:
				c = c.lightened(0.035)
			img.set_pixel(x, y, c)
	for k in 26:
		var cx := rng.randi_range(4, n - 5)
		var cy := rng.randi_range(4, n - 5)
		img.set_pixel(cx, cy, base.lightened(0.18))
		img.set_pixel(cx + 1, cy, base.lightened(0.12))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ SDFs

static func _sd_circle(p: Vector2, c: Vector2, r: float) -> float:
	return p.distance_to(c) - r


static func _sd_ellipse(p: Vector2, c: Vector2, r: Vector2) -> float:
	var q := (p - c) / r
	return (q.length() - 1.0) * minf(r.x, r.y)


static func _sd_box(p: Vector2, c: Vector2, half: Vector2, round_r: float) -> float:
	var q := (p - c).abs() - half + Vector2(round_r, round_r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - round_r


## Convex polygon SDF (approximate outside corners — fine for anti-aliasing).
static func _sd_poly(p: Vector2, pts: Array) -> float:
	var n := pts.size()
	var area := 0.0
	for k in n:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sgn := 1.0 if area > 0.0 else -1.0
	var m := -INF
	for k in n:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % n]
		var e := (b - a).normalized()
		var normal := Vector2(e.y, -e.x) * sgn
		m = maxf(m, (p - a).dot(normal))
	return m
