extends Node
## Screenshots every menu screen + the level-up and pause overlays (needs a display).
##   godot --path . --rendering-method gl_compatibility --resolution 720x1280 res://tools/ui_shots.tscn -- out=/tmp/ui

var out_dir := "user://ui_shots"
var steps: Array[Callable] = []
var current: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameState.last_result = {"won": true, "reason": "slain", "weapon": "dual_blades", "time": 431.0, "kos": 6234,
		"officers": 11, "outposts": 2, "outposts_total": 3, "parts": 3, "level": 31, "new_kos": true, "new_time": false}
	await _shot_scene("res://ui/title.tscn", "title")
	await _shot_scene("res://ui/weapon_select.tscn", "weapon_select")
	await _shot_scene("res://ui/results.tscn", "results")
	# level-up overlay inside a real hunt
	var hunt := Hunt.new()
	hunt.config = {"mode": "play", "weapon": "great_sword", "seed": 2, "god": true, "bot": false, "auto_pick": false}
	_swap(hunt)
	await _frames(20)
	hunt.progression.add_xp(hunt.progression.total_xp_for(4))
	await _frames(4)
	await _save("level_up")
	hunt.level_ui.visible = false
	hunt.progression.pending = 0
	get_tree().paused = false
	await _frames(2)
	hunt.toggle_pause()
	await _frames(4)
	await _save("pause")
	get_tree().paused = false
	get_tree().quit()


func _swap(n: Node) -> void:
	if current != null:
		current.queue_free()
	current = n
	add_child(n)


func _shot_scene(path: String, name: String) -> void:
	_swap((load(path) as PackedScene).instantiate())
	await _frames(30)
	await _save(name)


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := out_dir.path_join(name + ".png")
	img.save_png(p)
	print("saved ", p)
