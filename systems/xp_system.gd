class_name XPSystem
extends Node2D
## XP gems: packed arrays + one MultiMesh. Over the cap, new value merges into existing gems
## (which grow a tier), so the field never holds more than `cap` gems.

const STRIDE := 12

var cap: int = 400
var gpos := PackedVector2Array()
var gval := PackedInt32Array()
var gspeed := PackedFloat32Array()
var gpulled := PackedByteArray()
var count: int = 0
var pull_speed: float = 520.0
var pull_accel: float = 1400.0
var tier_values: Array = [3, 10]
var render_enabled: bool = true

var _merge_cursor: int = 0
var _mmi: MultiMeshInstance2D
var _buf := PackedFloat32Array()
var _tier_cols: Array[Color] = []
var _size: Vector2


func setup(p_cap: int = -1) -> void:
	cap = p_cap if p_cap > 0 else Tuning.i("xp.gem_cap", 400)
	pull_speed = Tuning.f("xp.pull_speed", 520.0)
	pull_accel = Tuning.f("xp.pull_accel", 1400.0)
	tier_values = Tuning.a("xp.tier_values")
	gpos.resize(cap)
	gval.resize(cap)
	gspeed.resize(cap)
	gpulled.resize(cap)
	count = 0
	_tier_cols = [ArtRegistry.color("xp.tier0"), ArtRegistry.color("xp.tier1"), ArtRegistry.color("xp.tier2")]
	_size = ArtRegistry.size("xp.gem")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = EnemySystem._unit_quad()
	mm.instance_count = cap
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance2D.new()
	_mmi.multimesh = mm
	_mmi.texture = ArtRegistry.tex("xp.gem")
	add_child(_mmi)
	_buf.resize(cap * STRIDE)


func spawn(p: Vector2, value: int) -> void:
	if value <= 0:
		return
	if count >= cap:
		# merge into an existing gem (round-robin) — it becomes a bigger tier
		_merge_cursor = (_merge_cursor + 1) % cap
		gval[_merge_cursor] += value
		return
	gpos[count] = p
	gval[count] = value
	gspeed[count] = 0.0
	gpulled[count] = 0
	count += 1


func total_value() -> int:
	var s := 0
	for k in count:
		s += gval[k]
	return s


func attract_all() -> void:
	for k in count:
		gpulled[k] = 1


func tier_of(v: int) -> int:
	if v >= int(tier_values[1]):
		return 2
	if v >= int(tier_values[0]):
		return 1
	return 0


## Moves gems; returns XP collected this frame.
func step(dt: float, player_pos: Vector2, magnet_r: float, pickup_r: float) -> int:
	var got := 0
	var m2 := magnet_r * magnet_r
	var p2 := pickup_r * pickup_r
	var k := 0
	while k < count:
		var p := gpos[k]
		var d := player_pos - p
		var l2 := d.length_squared()
		if l2 <= p2:
			got += gval[k]
			count -= 1
			gpos[k] = gpos[count]
			gval[k] = gval[count]
			gspeed[k] = gspeed[count]
			gpulled[k] = gpulled[count]
			continue
		if gpulled[k] == 0 and l2 <= m2:
			gpulled[k] = 1
		if gpulled[k] != 0:
			var s := minf(gspeed[k] + pull_accel * dt, pull_speed * 3.0)
			s = maxf(s, pull_speed * 0.5)
			gspeed[k] = s
			var l := sqrt(l2)
			gpos[k] = p + d / l * minf(s * dt, l)
		k += 1
	if render_enabled:
		_render()
	return got


func _render() -> void:
	var b := _buf
	_buf = PackedFloat32Array()
	for k in count:
		var o := k * STRIDE
		var tier := tier_of(gval[k])
		var sc := 1.0 + 0.45 * tier
		var col := _tier_cols[tier]
		var p := gpos[k]
		b[o] = _size.x * sc; b[o + 1] = 0.0; b[o + 2] = 0.0; b[o + 3] = p.x
		b[o + 4] = 0.0; b[o + 5] = _size.y * sc; b[o + 6] = 0.0; b[o + 7] = p.y
		b[o + 8] = col.r; b[o + 9] = col.g; b[o + 10] = col.b; b[o + 11] = 1.0
	_buf = b
	RenderingServer.multimesh_set_buffer(_mmi.multimesh.get_rid(), _buf)
	_mmi.multimesh.visible_instance_count = count
