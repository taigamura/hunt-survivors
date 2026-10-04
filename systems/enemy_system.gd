class_name EnemySystem
extends Node2D
## Data-oriented swarm. Enemies are rows in parallel packed arrays, never nodes.
## Rendering: one MultiMeshInstance2D per enemy type, buffer rebuilt each frame.
## Narrow API (portable to GDExtension later):
##   spawn(), despawn(), damage(), kill(), rout_squad(),
##   query_circle(), query_arc(), query_line(), count_in_circle(), contact_damage(), step()

const T_GRUNT := 0
const T_RUNNER := 1
const T_BRUTE := 2
const T_OFFICER := 3
const TYPE_NAMES: Array[String] = ["grunt", "runner", "brute", "officer"]
const N_TYPES := 4
const STRIDE := 12  # 2D transform (8) + color (4)

const CAUSE_WEAPON := 0
const CAUSE_MONSTER := 1

var cap: int = 2000

# --- per-enemy columns
var pos: PackedVector2Array
var face: PackedVector2Array
var kb: PackedVector2Array
var hp: PackedFloat32Array
var flash: PackedFloat32Array
var flee: PackedFloat32Array
var etype: PackedInt32Array
var squad: PackedInt32Array
var slot: PackedInt32Array  ## index into `active`, -1 when free
var wob_c: PackedFloat32Array  ## per-enemy heading wobble (cos/sin) so crowds fan out
var wob_s: PackedFloat32Array
var flank: PackedFloat32Array  ## per-enemy -1..1: which side (and how far) it flanks a moving hunter
var last_seen: PackedVector2Array  ## where the hunter was when this enemy last saw it
var lost_t: PackedFloat32Array  ## seconds spent at last_seen without finding the hunter

# --- live set + free list
var active: PackedInt32Array
var n_active: int = 0
var free_stack: PackedInt32Array
var n_free: int = 0

# --- per-type stats
var t_speed := PackedFloat32Array()
var t_radius := PackedFloat32Array()
var t_hp := PackedFloat32Array()
var t_contact := PackedFloat32Array()
var t_xp := PackedInt32Array()
var t_mass := PackedFloat32Array()
var t_size: Array[Vector2] = []
var t_rotate: Array[bool] = []
var t_tint: Array[Color] = []

var hp_mult: float = 1.0
var last_contact_pos: Vector2 = Vector2.ZERO
var speed_mult: float = 1.0
var target: Vector2 = Vector2.ZERO
var target_vel: Vector2 = Vector2.ZERO  ## the hunter's velocity (enemies lead their chase)
var despawn_dist_sq: float = 1900.0 * 1900.0
var sep_checks: int = 4
var sep_strength: float = 0.55
var kb_decay: float = 9.0
var flee_speed_mult: float = 1.5
var rout_time: float = 2.6
var flash_time: float = 0.07
var direct_chase_sq: float = 4900.0
var wobble: float = 0.45
var look_ahead: float = 170.0
var wobble_min_sq: float = 260.0 * 260.0
var sight_sq: float = 720.0 * 720.0
var lead_factor: float = 0.7
var lead_max: float = 1.0
var flank_frac: float = 0.5
var flank_max: float = 220.0
var lost_reach_sq: float = 70.0 * 70.0
var lost_time: float = 3.0
var lost_despawns: int = 0  ## telemetry: enemies that gave up the search and were recycled

var hash: SpatialHash
var field: FlowField

## Called as on_kill.call(idx, position, type, cause) right before the slot is freed.
var on_kill: Callable = Callable()

var render_enabled: bool = true
var _mm: Array[MultiMeshInstance2D] = []
var _buf: Array[PackedFloat32Array] = []
var _frame: int = 0
var _despawn_queue: PackedInt32Array = PackedInt32Array()
var _flash_color: Color = Color(4, 4, 4, 1)
var _flee_color: Color = Color(0.55, 0.55, 0.6, 0.7)


func setup(p_field: FlowField, p_cap: int = -1) -> void:
	field = p_field
	cap = p_cap if p_cap > 0 else Tuning.i("enemies.cap", 2000)
	despawn_dist_sq = pow(Tuning.f("enemies.despawn_distance", 1900.0), 2.0)
	sep_checks = Tuning.i("enemies.separation_checks", 4)
	sep_strength = Tuning.f("enemies.separation_strength", 0.55)
	kb_decay = Tuning.f("enemies.knockback_decay", 9.0)
	flee_speed_mult = Tuning.f("enemies.flee_speed_mult", 1.5)
	rout_time = Tuning.f("enemies.rout_time", 2.6)
	flash_time = Tuning.f("juice.flash_time", 0.07)
	direct_chase_sq = pow(Tuning.f("flow_field.direct_chase_distance", 70.0), 2.0)
	wobble = Tuning.f("enemies.heading_wobble", 0.45)
	look_ahead = Tuning.f("flow_field.look_ahead", 170.0)
	wobble_min_sq = pow(Tuning.f("enemies.wobble_min_distance", 260.0), 2.0)
	sight_sq = pow(Tuning.f("enemies.sight_radius", 720.0), 2.0)
	lead_factor = Tuning.f("enemies.lead_factor", 0.7)
	lead_max = Tuning.f("enemies.lead_max", 1.0)
	flank_frac = Tuning.f("enemies.flank_frac", 0.5)
	flank_max = Tuning.f("enemies.flank_max", 220.0)
	lost_reach_sq = pow(Tuning.f("enemies.lost_reach", 70.0), 2.0)
	lost_time = Tuning.f("enemies.lost_time", 3.0)
	hash = SpatialHash.new(3600.0, 80.0)

	pos.resize(cap)
	face.resize(cap)
	kb.resize(cap)
	hp.resize(cap)
	flash.resize(cap)
	flee.resize(cap)
	etype.resize(cap)
	squad.resize(cap)
	slot.resize(cap)
	slot.fill(-1)
	wob_c.resize(cap)
	wob_s.resize(cap)
	flank.resize(cap)
	last_seen.resize(cap)
	lost_t.resize(cap)
	var wrng := RandomNumberGenerator.new()
	wrng.seed = 99
	for k in cap:
		var a := wrng.randf_range(-wobble, wobble)
		wob_c[k] = cos(a)
		wob_s[k] = sin(a)
		flank[k] = wrng.randf_range(-1.0, 1.0)
	active.resize(cap)
	free_stack.resize(cap)
	n_active = 0
	n_free = cap
	for k in cap:
		free_stack[k] = cap - 1 - k  # pop order 0,1,2...

	t_speed.resize(N_TYPES)
	t_radius.resize(N_TYPES)
	t_hp.resize(N_TYPES)
	t_contact.resize(N_TYPES)
	t_xp.resize(N_TYPES)
	t_mass.resize(N_TYPES)
	t_size.clear()
	t_rotate.clear()
	t_tint.clear()
	for t in N_TYPES:
		var key := "enemies.types.%s" % TYPE_NAMES[t]
		t_speed[t] = Tuning.f(key + ".speed")
		t_radius[t] = Tuning.f(key + ".radius")
		t_hp[t] = Tuning.f(key + ".hp")
		t_contact[t] = Tuning.f(key + ".contact")
		t_xp[t] = Tuning.i(key + ".xp")
		t_mass[t] = Tuning.f(key + ".mass", 1.0)
		var art_id := "enemy." + TYPE_NAMES[t]
		t_size.append(ArtRegistry.size(art_id))
		t_rotate.append(ArtRegistry.rotates(art_id))
		t_tint.append(ArtRegistry.tint(art_id))
	_flash_color = ArtRegistry.color("fx.enemy_flash")
	_flee_color = ArtRegistry.color("fx.fleeing")
	_build_render()


func _build_render() -> void:
	for m in _mm:
		m.queue_free()
	_mm.clear()
	_buf.clear()
	var quad := _unit_quad()
	for t in N_TYPES:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = cap
		mm.visible_instance_count = 0
		# Fixed bounds: skips per-frame AABB recompute and avoids stale-AABB culling.
		mm.custom_aabb = AABB(Vector3(-5000, -5000, -1), Vector3(10000, 10000, 2))
		var node := MultiMeshInstance2D.new()
		node.multimesh = mm
		node.texture = ArtRegistry.tex("enemy." + TYPE_NAMES[t])
		node.z_index = 1 if t == T_OFFICER else 0
		add_child(node)
		_mm.append(node)
		var b := PackedFloat32Array()
		b.resize(cap * STRIDE)
		_buf.append(b)


static func _unit_quad() -> ArrayMesh:
	var verts := PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# ------------------------------------------------------------------ lifecycle

func spawn(type: int, p: Vector2, squad_id: int = -1) -> int:
	if n_free <= 0:
		return -1
	n_free -= 1
	var i := free_stack[n_free]
	pos[i] = p
	face[i] = (target - p).normalized()
	kb[i] = Vector2.ZERO
	hp[i] = t_hp[type] * hp_mult
	flash[i] = 0.0
	flee[i] = 0.0
	etype[i] = type
	squad[i] = squad_id
	last_seen[i] = target  # spawned by the noise of the hunt: it knows roughly where you are
	lost_t[i] = 0.0
	active[n_active] = i
	slot[i] = n_active
	n_active += 1
	return i


func is_alive(i: int) -> bool:
	return i >= 0 and i < cap and slot[i] >= 0


func despawn(i: int) -> void:
	var s := slot[i]
	if s < 0:
		return
	n_active -= 1
	var last := active[n_active]
	active[s] = last
	slot[last] = s
	slot[i] = -1
	free_stack[n_free] = i
	n_free += 1


func clear_all() -> void:
	while n_active > 0:
		despawn(active[n_active - 1])


func kill(i: int, cause: int = CAUSE_WEAPON) -> void:
	if slot[i] < 0:
		return
	if on_kill.is_valid():
		on_kill.call(i, pos[i], etype[i], cause)
	despawn(i)


## Returns true if the enemy died.
func damage(i: int, amount: float, knock: Vector2 = Vector2.ZERO, cause: int = CAUSE_WEAPON) -> bool:
	if slot[i] < 0:
		return false
	hp[i] -= amount
	flash[i] = flash_time
	if knock != Vector2.ZERO:
		kb[i] += knock / t_mass[etype[i]]
	if hp[i] <= 0.0:
		kill(i, cause)
		return true
	return false


## Officer down: every live member of the squad flees and despawns after rout_time.
## Returns the routed member ids (caller drops XP / counts KOs).
func rout_squad(squad_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if squad_id < 0:
		return out
	for k in n_active:
		var i := active[k]
		if squad[i] == squad_id and flee[i] <= 0.0:
			flee[i] = rout_time
			squad[i] = -1
			out.append(i)
	return out


func count_type(type: int) -> int:
	var c := 0
	for k in n_active:
		if etype[active[k]] == type:
			c += 1
	return c


# ------------------------------------------------------------------ queries
# All queries use the spatial hash built at the start of step(); they also
# re-check positions exactly, so they are correct even after mid-frame moves.

func query_circle(c: Vector2, r: float, include_fleeing: bool = true) -> PackedInt32Array:
	var out := PackedInt32Array()
	var pad := r + 24.0
	for i in hash.candidates(Rect2(c.x - pad, c.y - pad, pad * 2.0, pad * 2.0)):
		if slot[i] < 0:
			continue
		if not include_fleeing and flee[i] > 0.0:
			continue
		var rr := r + t_radius[etype[i]]
		if pos[i].distance_squared_to(c) <= rr * rr:
			out.append(i)
	return out


## Arc (pie slice) of radius r around c facing dir (unit), half-angle in radians.
func query_arc(c: Vector2, r: float, dir: Vector2, half_angle: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var pad := r + 24.0
	var cos_h := cos(half_angle)
	for i in hash.candidates(Rect2(c.x - pad, c.y - pad, pad * 2.0, pad * 2.0)):
		if slot[i] < 0:
			continue
		var rad := t_radius[etype[i]]
		var d := pos[i] - c
		var dl := d.length()
		if dl > r + rad:
			continue
		if dl <= rad + 6.0 or d.dot(dir) >= cos_h * dl:
			out.append(i)
		elif half_angle < PI:
			# graze: within radius of either edge ray
			var e1 := dir.rotated(half_angle)
			var e2 := dir.rotated(-half_angle)
			if _seg_dist(pos[i], c, c + e1 * r) <= rad or _seg_dist(pos[i], c, c + e2 * r) <= rad:
				out.append(i)
	return out


## Capsule from a to b with half-width w.
func query_line(a: Vector2, b: Vector2, w: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var pad := w + 24.0
	var rect := Rect2(a, Vector2.ZERO).expand(b).grow(pad)
	for i in hash.candidates(rect):
		if slot[i] < 0:
			continue
		var rr := w + t_radius[etype[i]]
		if _seg_dist(pos[i], a, b) <= rr:
			out.append(i)
	return out


func count_in_circle(c: Vector2, r: float) -> int:
	var n := 0
	var r2 := r * r
	for i in hash.candidates(Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0)):
		if slot[i] >= 0 and flee[i] <= 0.0 and pos[i].distance_squared_to(c) <= r2:
			n += 1
	return n


## Highest contact damage among non-fleeing enemies touching a circle (the player).
## `last_contact_pos` is where that enemy stands (shields block by direction).
func contact_damage(c: Vector2, r: float) -> float:
	var best := 0.0
	last_contact_pos = c
	var pad := r + 24.0
	for i in hash.candidates(Rect2(c.x - pad, c.y - pad, pad * 2.0, pad * 2.0)):
		if slot[i] < 0 or flee[i] > 0.0:
			continue
		var t := etype[i]
		var rr := r + t_radius[t]
		if pos[i].distance_squared_to(c) <= rr * rr and t_contact[t] > best:
			best = t_contact[t]
			last_contact_pos = pos[i]
	return best


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ------------------------------------------------------------------ simulation

## Rebuild the hash only (used before weapon queries when step() hasn't run yet).
func rebuild_hash() -> void:
	hash.build(pos, active, n_active, target)


func step(dt: float) -> void:
	_frame += 1
	hash.build(pos, active, n_active, target)
	var tgt := target
	var tvel := target_vel
	var moving := tvel.length_squared() > 100.0
	var tperp := tvel.normalized().orthogonal() if moving else Vector2.ZERO
	var decay := exp(-kb_decay * dt)
	var parity := _frame & 1
	var hs := hash
	var cs := hs.cell_start
	var items := hs.items
	var ox := hs.origin.x
	var oy := hs.origin.y
	var ic := hs.inv_cell
	var hcols := hs.cols
	var cmax := hs.cols - 1
	var rmax := hs.rows - 1
	var sm := speed_mult
	var fl := field
	# flow-field locals (inlined sample/is_blocked: function calls dominate GDScript cost)
	var fmox := fl.map_origin.x
	var fmoy := fl.map_origin.y
	var finv := fl.inv_cell
	var fwin := fl.win
	var fx0 := fl.win_x0
	var fy0 := fl.win_y0
	var fdist := fl.dist
	var fver := fl.version
	var fbl := fl.blocked
	var fcols := fl.map_cols
	var frows := fl.map_rows
	_despawn_queue.clear()
	for k in n_active:
		var i := active[k]
		var p := pos[i]
		var to := tgt - p
		var d2 := to.length_squared()
		var t := etype[i]
		var desired: Vector2
		var spd := t_speed[t] * sm
		var fleeing := flee[i] > 0.0
		if fleeing:
			flee[i] -= dt
			if flee[i] <= 0.0:
				_despawn_queue.append(i)
				continue
			desired = -to.normalized()
			spd *= flee_speed_mult
		else:
			if d2 > despawn_dist_sq:
				_despawn_queue.append(i)
				continue
			# Where to go. In sight: lead the hunter and flank to the side, so a chasing crowd
			# fans out and cuts across your path instead of filing along your trail. Out of
			# sight: walk to where you last saw it; if it isn't there, mill about, then give up.
			var goal := tgt
			var searching := false
			if d2 <= sight_sq:
				last_seen[i] = tgt
				lost_t[i] = 0.0
				if moving and d2 > direct_chase_sq:
					var dl0 := sqrt(d2)
					goal = tgt + tvel * minf(dl0 / spd, lead_max) * lead_factor + tperp * (flank[i] * minf(dl0 * flank_frac, flank_max))
			else:
				goal = last_seen[i]
				if p.distance_squared_to(goal) <= lost_reach_sq:
					searching = true
					lost_t[i] += dt
					if lost_t[i] >= lost_time:
						_despawn_queue.append(i)
						lost_despawns += 1
						continue
			to = goal - p
			var g2 := to.length_squared()
			if searching:
				# mill about: drift along the enemy's own wobble direction at a third of its speed
				desired = Vector2(wob_c[i], wob_s[i]) * 0.35
			elif g2 < direct_chase_sq:
				desired = to / sqrt(g2) if g2 > 0.01 else Vector2.ZERO
			else:
				var dl := sqrt(g2)
				desired = to / dl
				# Straight at the goal unless the line ahead is obstructed — then follow the
				# flow field. (Pure grid fields funnel crowds into axis-aligned lanes.)
				var la := minf(dl, look_ahead)
				var ax := p.x + desired.x * la * 0.45
				var ay := p.y + desired.y * la * 0.45
				var bx := p.x + desired.x * la
				var by := p.y + desired.y * la
				var g1x := int((ax - fmox) * finv)
				var g1y := int((ay - fmoy) * finv)
				var g2x := int((bx - fmox) * finv)
				var g2y := int((by - fmoy) * finv)
				var obstructed := ax < fmox or ay < fmoy or bx < fmox or by < fmoy \
					or g1x >= fcols or g1y >= frows or g2x >= fcols or g2y >= frows \
					or fbl[g1y * fcols + g1x] != 0 or fbl[g2y * fcols + g2x] != 0
				var wx := int((p.x - fmox) * finv) - fx0
				var wy := int((p.y - fmoy) * finv) - fy0
				if obstructed and wx >= 0 and wy >= 0 and wx < fwin and wy < fwin:
					var idx := wy * fwin + wx
					if fdist[idx] > 0:
						if fl.stamp[idx] != fver:
							fl._compute_next(idx, wx, wy)
						desired = (fl.next_pt[idx] - p).normalized()
				if d2 > wobble_min_sq:
					var wc := wob_c[i]
					var ws := wob_s[i]
					desired = Vector2(desired.x * wc - desired.y * ws, desired.x * ws + desired.y * wc)
		var v := desired * spd
		# light separation, every other frame per enemy
		if ((i + parity) & 1) == 0:
			var cx := clampi(int((p.x - ox) * ic), 0, cmax)
			var cy := clampi(int((p.y - oy) * ic), 0, rmax)
			var c := cy * hcols + cx
			var s := cs[c]
			var e := mini(cs[c + 1], s + sep_checks + 1)
			var r_i := t_radius[t]
			var push := Vector2.ZERO
			for kk in range(s, e):
				var j := items[kk]
				if j == i:
					continue
				var dd := p - pos[j]
				var rr := r_i + t_radius[etype[j]]
				var l2 := dd.length_squared()
				if l2 < rr * rr and l2 > 0.0001:
					var l := sqrt(l2)
					push += dd * ((rr - l) / l)
			v += push * (sep_strength / maxf(dt, 0.001)) * 0.5
		var kv := kb[i]
		if kv != Vector2.ZERO:
			v += kv
			kv *= decay
			if kv.length_squared() < 4.0:
				kv = Vector2.ZERO
			kb[i] = kv
		var np := p + v * dt
		var bgx := int((np.x - fmox) * finv)
		var bgy := int((np.y - fmoy) * finv)
		if np.x < fmox or np.y < fmoy or bgx >= fcols or bgy >= frows or fbl[bgy * fcols + bgx] != 0:
			if not fl.is_blocked(Vector2(np.x, p.y)):
				np = Vector2(np.x, p.y)
			elif not fl.is_blocked(Vector2(p.x, np.y)):
				np = Vector2(p.x, np.y)
			else:
				np = p
		pos[i] = np
		if desired != Vector2.ZERO:
			face[i] = desired
		if flash[i] > 0.0:
			flash[i] -= dt
	for i in _despawn_queue:
		despawn(i)
	if render_enabled:
		update_render()


func update_render() -> void:
	var counts := PackedInt32Array([0, 0, 0, 0])
	var b0 := _buf[0]
	var b1 := _buf[1]
	var b2 := _buf[2]
	var b3 := _buf[3]
	# Packed arrays are copy-on-write: work on locals, then hand them back.
	_buf[0] = PackedFloat32Array()
	_buf[1] = PackedFloat32Array()
	_buf[2] = PackedFloat32Array()
	_buf[3] = PackedFloat32Array()
	var fc := _flash_color
	var flc := _flee_color
	for k in n_active:
		var i := active[k]
		var t := etype[i]
		var o := counts[t] * STRIDE
		counts[t] += 1
		var sz := t_size[t]
		var c := 1.0
		var s := 0.0
		if t_rotate[t]:
			var f := face[i]
			c = f.x
			s = f.y
		var p := pos[i]
		var col: Color
		if flash[i] > 0.0:
			col = fc
		elif flee[i] > 0.0:
			col = flc
		else:
			col = t_tint[t]
		match t:
			0:
				b0[o] = c * sz.x; b0[o + 1] = -s * sz.y; b0[o + 2] = 0.0; b0[o + 3] = p.x
				b0[o + 4] = s * sz.x; b0[o + 5] = c * sz.y; b0[o + 6] = 0.0; b0[o + 7] = p.y
				b0[o + 8] = col.r; b0[o + 9] = col.g; b0[o + 10] = col.b; b0[o + 11] = col.a
			1:
				b1[o] = c * sz.x; b1[o + 1] = -s * sz.y; b1[o + 2] = 0.0; b1[o + 3] = p.x
				b1[o + 4] = s * sz.x; b1[o + 5] = c * sz.y; b1[o + 6] = 0.0; b1[o + 7] = p.y
				b1[o + 8] = col.r; b1[o + 9] = col.g; b1[o + 10] = col.b; b1[o + 11] = col.a
			2:
				b2[o] = c * sz.x; b2[o + 1] = -s * sz.y; b2[o + 2] = 0.0; b2[o + 3] = p.x
				b2[o + 4] = s * sz.x; b2[o + 5] = c * sz.y; b2[o + 6] = 0.0; b2[o + 7] = p.y
				b2[o + 8] = col.r; b2[o + 9] = col.g; b2[o + 10] = col.b; b2[o + 11] = col.a
			_:
				b3[o] = c * sz.x; b3[o + 1] = -s * sz.y; b3[o + 2] = 0.0; b3[o + 3] = p.x
				b3[o + 4] = s * sz.x; b3[o + 5] = c * sz.y; b3[o + 6] = 0.0; b3[o + 7] = p.y
				b3[o + 8] = col.r; b3[o + 9] = col.g; b3[o + 10] = col.b; b3[o + 11] = col.a
	_buf[0] = b0
	_buf[1] = b1
	_buf[2] = b2
	_buf[3] = b3
	for t in N_TYPES:
		var mm := _mm[t].multimesh
		RenderingServer.multimesh_set_buffer(mm.get_rid(), _buf[t])
		mm.visible_instance_count = counts[t]
