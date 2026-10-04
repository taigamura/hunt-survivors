extends Node
## Generates the placeholder iOS app icon procedurally -> res://art/icon_1024.png
##   godot --headless --path . res://tools/make_icon.tscn

const N := 1024


func _ready() -> void:
	var img := Image.create(N, N, false, Image.FORMAT_RGB8)
	var bg := Color(0.07, 0.08, 0.09)
	var gold := Color(1.0, 0.82, 0.25)
	var red := Color(0.93, 0.33, 0.30)
	var white := Color(0.92, 0.98, 1.0)
	var c := Vector2(N * 0.5, N * 0.56)
	# background + charged slash arc
	for y in N:
		for x in N:
			var p := Vector2(x + 0.5, y + 0.5)
			var dc := p.distance_to(c)
			var col := bg.lerp(Color(0.13, 0.14, 0.16), clampf(1.0 - dc / 700.0, 0.0, 1.0))
			if absf(Vector2.UP.angle_to(p - c)) < 1.35:
				col = col.lerp(gold, clampf(0.5 - (absf(dc - 250.0) - 34.0), 0.0, 1.0))
			img.set_pixel(x, y, col)
	# swarm arrowheads pointing inward (only touch their bounding boxes)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var poly := [Vector2(34, 0), Vector2(-24, -22), Vector2(-11, 0), Vector2(-24, 22)]
	for k in 46:
		var a := rng.randf() * TAU
		var center := c + Vector2.from_angle(a) * rng.randf_range(320.0, 520.0)
		var face := a + PI
		for y in range(int(center.y) - 40, int(center.y) + 41):
			for x in range(int(center.x) - 40, int(center.x) + 41):
				if x < 0 or y < 0 or x >= N or y >= N:
					continue
				var lp := (Vector2(x + 0.5, y + 0.5) - center).rotated(-face)
				var d := ArtRegistry._sd_poly(lp, poly)
				if d < 4.5:
					var cur := img.get_pixel(x, y)
					var edge := cur.lerp(Color(0.05, 0.05, 0.06), clampf(4.5 - d, 0.0, 1.0))
					img.set_pixel(x, y, edge.lerp(red, clampf(0.5 - d, 0.0, 1.0)))
	# the hunter
	for y in range(int(c.y) - 110, int(c.y) + 111):
		for x in range(int(c.x) - 110, int(c.x) + 111):
			var body := Vector2(x + 0.5, y + 0.5).distance_to(c) - 92.0
			if body < 12.0:
				var cur := img.get_pixel(x, y)
				cur = cur.lerp(Color(0.05, 0.05, 0.06), clampf(12.5 - body, 0.0, 1.0))
				img.set_pixel(x, y, cur.lerp(white, clampf(0.5 - body, 0.0, 1.0)))
	DirAccess.make_dir_recursive_absolute("res://art")
	var err := img.save_png("res://art/icon_1024.png")
	print("icon written: ", err == OK)
	get_tree().quit(0 if err == OK else 1)
