extends Node
## Visual check: runs a bot-driven hunt and saves screenshots at given frames.
## Usage (needs a display; e.g. xvfb-run):
##   godot --path . --rendering-method gl_compatibility --fixed-fps 60 res://tools/shot.tscn -- \
##       weapon=dual_blades frames=300,900 out=/tmp/shots arrive=20 seed=3 musou_at=600

var hunt: Hunt
var frames: PackedInt32Array = [300]
var out_dir: String = "user://shots"
var frame: int = 0
var weapon: String = "great_sword"
var musou_at: int = -1
var fill_at: int = -1
var fill_n: int = 0


func _ready() -> void:
	var cfg := {"mode": "smoke", "bot": true, "seed": 3, "god": true}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"weapon":
				weapon = kv[1]
			"frames":
				frames = PackedInt32Array()
				for f in kv[1].split(","):
					frames.append(int(f))
			"out":
				out_dir = kv[1]
			"arrive":
				cfg["arrive_time"] = float(kv[1])
			"seed":
				cfg["seed"] = int(kv[1])
			"musou_at":
				musou_at = int(kv[1])
			"fill":
				var p := kv[1].split("@")
				fill_n = int(p[0])
				fill_at = int(p[1])
			"god":
				cfg["god"] = kv[1] == "1"
	cfg["weapon"] = weapon
	DirAccess.make_dir_recursive_absolute(out_dir)
	hunt = Hunt.new()
	hunt.config = cfg
	add_child(hunt)


func _process(_d: float) -> void:
	frame += 1
	if frame == musou_at:
		hunt.musou.value = hunt.musou.max_value
		hunt.request_musou()
	if frame == fill_at:
		hunt.fill_enemies(fill_n)
	if frame in frames:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := out_dir.path_join("%s_%05d.png" % [weapon, frame])
		img.save_png(path)
		print("saved ", path, "  kos=", hunt.kos, " foes=", hunt.enemies.n_active, " lvl=", hunt.progression.level, " t=", "%.1f" % hunt.run_time)
	if frame >= frames[frames.size() - 1] + 2:
		get_tree().quit()
