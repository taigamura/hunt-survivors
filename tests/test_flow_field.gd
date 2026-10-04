extends TestCase
## Flow field: routes around obstacles, unreachable areas, time-sliced rebuilds.


func _wall_field() -> FlowField:
	var f := FlowField.new(Rect2(-2000, -2000, 4000, 4000), 40.0, 84)
	# vertical wall at x=200 from y=-600..600
	for y in range(-600, 601, 20):
		f.block_circle(Vector2(200, y), 30)
	f.update(Vector2.ZERO, true)
	return f


func test_distance_detours_around_wall() -> void:
	var f := _wall_field()
	var behind := Vector2(500, 0)
	var straight := int(behind.length() / f.cell)
	var d := f.distance_at(behind)
	assert_gt(d, 0, "point behind the wall is reachable")
	assert_gt(d, straight + 20, "path must go around the wall (got %d, straight %d)" % [d, straight])
	assert_eq(f.distance_at(Vector2.ZERO), 0)


func test_following_field_reaches_target_without_entering_walls() -> void:
	var f := _wall_field()
	var p := Vector2(500, 0)
	var reached := false
	for k in 600:
		var dir := f.sample(p)
		p += dir * 15.0
		assert_false(f.is_blocked(p), "walked into a blocked cell at %s" % str(p))
		if p.distance_to(Vector2.ZERO) < 45.0:
			reached = true
			break
	assert_true(reached, "followed the field to the target")


func test_enclosed_area_is_unreachable() -> void:
	var f := FlowField.new(Rect2(-2000, -2000, 4000, 4000), 40.0, 84)
	for k in 64:
		f.block_circle(Vector2(600, 600) + Vector2.from_angle(TAU * k / 64.0) * 160.0, 30)
	f.update(Vector2.ZERO, true)
	assert_true(f.distance_at(Vector2(600, 600)) < 0, "inside of a closed ring has no path")


func test_outside_map_is_blocked() -> void:
	var f := FlowField.new(Rect2(-1000, -1000, 2000, 2000), 40.0, 40)
	assert_true(f.is_blocked(Vector2(-1200, 0)))
	assert_true(f.is_blocked(Vector2(0, 1100)))
	assert_false(f.is_blocked(Vector2.ZERO))


func test_time_sliced_rebuild_swaps_in() -> void:
	var f := FlowField.new(Rect2(-3000, -3000, 6000, 6000), 40.0, 84)
	f.update(Vector2.ZERO, true)
	var builds := f.builds_completed
	var target := Vector2(800, 0)
	f.update(target)
	assert_true(f.job_active, "a rebuild runs over several frames")
	assert_true(f.distance_at(Vector2.ZERO) == 0, "old field stays readable during the rebuild")
	var frames := 1
	while f.job_active and frames < 50:
		f.update(target)
		frames += 1
	assert_false(f.job_active, "rebuild finished")
	assert_gt(frames, 1, "took more than one frame (time-sliced)")
	assert_eq(f.builds_completed, builds + 1)
	assert_eq(f.distance_at(target), 0, "new field targets the new cell")
