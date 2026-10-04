extends Node
## Compiles every .gd under res:// and reports failures. Usage:
##   godot --headless --path . res://tools/check_scripts.tscn
func _ready() -> void:
	var bad := 0
	var files := _collect("res://")
	for f in files:
		var s: Variant = load(f)
		if s == null or not (s as GDScript).can_instantiate():
			print("FAIL ", f)
			bad += 1
	print("checked %d scripts, %d failed" % [files.size(), bad])
	get_tree().quit(1 if bad > 0 else 0)

func _collect(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue
		out.append_array(_collect(dir.path_join(d)))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out
