extends TestCase
## ArtRegistry: every id the game uses exists, and a manifest overrides without code changes.

const USED_IDS := [
	"player.body", "enemy.grunt", "enemy.runner", "enemy.brute", "enemy.officer", "xp.gem",
	"obstacle.rock", "ground.tile", "outpost.flag",
	"monster.ironhorn.body", "monster.ironhorn.horns", "monster.ironhorn.horns_broken",
	"monster.ironhorn.back", "monster.ironhorn.back_broken", "monster.ironhorn.tail", "monster.ironhorn.tail_broken",
]


func test_all_sprite_ids_have_textures() -> void:
	for id: String in USED_IDS:
		assert_true(ArtRegistry.has_id(id), id)
		assert_true(ArtRegistry.tex(id) != null, "%s has a texture" % id)
		assert_gt(ArtRegistry.size(id).x, 0.0, "%s has a size" % id)


func test_every_referenced_color_id_exists() -> void:
	# scan the source for ArtRegistry.color("...") / tint("...") / "fx.*" ids and make sure they're registered
	var re := RegEx.new()
	re.compile('"((?:fx|ui|outpost)\\.[a-z0-9_]+|xp\\.tier[0-9])"')
	for dir in ["res://systems", "res://player/weapons", "res://player/subweapons", "res://monster", "res://musou", "res://ui", "res://scenes"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(dir.path_join(f))
			for m in re.search_all(src):
				var id := m.get_string(1)
				assert_true(ArtRegistry.has_id(id), "%s uses unknown art id %s" % [f, id])


func test_manifest_overrides_tint_and_size() -> void:
	var path := "user://test_manifest.json"
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"_readme": "ignored", "enemy.grunt": {"tint": "#00ff00", "size": [50, 40]}}))
	fa.close()
	var old: Dictionary = ArtRegistry.entry("enemy.grunt").duplicate()
	ArtRegistry.apply_manifest(path)
	assert_true(ArtRegistry.tint("enemy.grunt").is_equal_approx(Color("#00ff00")))
	assert_eq(ArtRegistry.size("enemy.grunt"), Vector2(50, 40))
	assert_true(ArtRegistry.tex("enemy.grunt") != null, "texture kept when no path given")
	ArtRegistry.entries["enemy.grunt"] = old
	DirAccess.remove_absolute(path)
