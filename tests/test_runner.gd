extends Node
## Headless test runner. Runs every tests/test_*.gd (classes extending TestCase),
## calling each method whose name starts with "test_".
##   godot --headless --path . res://tests/test_runner.tscn
## Exit code 0 = all passed.

func _ready() -> void:
	var total := 0
	var failed := 0
	var files := DirAccess.get_files_at("res://tests")
	files.sort()
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")) or f == "test_runner.gd" or f == "test_case.gd":
			continue
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			print("FAIL  could not load %s" % f)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var name := String(m["name"])
			if not name.begins_with("test_"):
				continue
			var tc: TestCase = script.new()
			tc.root = self
			tc._current = "%s::%s" % [f.get_basename(), name]
			tc.call(name)
			total += 1
			if tc.failures.is_empty():
				print("ok    %s" % tc._current)
			else:
				failed += 1
				for msg in tc.failures:
					print("FAIL  %s" % msg)
			# clean up anything the test parented here
			for c in get_children():
				c.free()
	Engine.time_scale = 1.0
	print("\n%d tests, %d failed" % [total, failed])
	print("TESTS PASS" if failed == 0 else "TESTS FAIL")
	get_tree().quit(0 if failed == 0 else 1)
