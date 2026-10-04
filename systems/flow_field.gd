class_name FlowField
extends RefCounted
## Grid flow field toward a target (the player).
## - `blocked` covers the whole map (obstacles + outside bounds).
## - BFS distances are computed in a square window centered on the target. The BFS is
##   time-sliced: a refresh runs in a back buffer over a few frames (budgeted nodes per frame)
##   and is swapped in when complete, so a refresh never causes a frame spike.
## - Each cell lazily caches the world point of its best downhill neighbor; enemies steer toward
##   it, which gives smooth (not 8-way) movement around obstacles.
## Enemies outside the window simply head straight for the target.

var cell: float
var inv_cell: float
var map_origin: Vector2
var map_cols: int
var map_rows: int
var blocked: PackedByteArray

var win: int
# --- active (readable) buffer
var win_x0: int = 0
var win_y0: int = 0
var dist: PackedInt32Array
var next_pt: PackedVector2Array
var stamp: PackedInt32Array
var version: int = 1
var target: Vector2 = Vector2.ZERO
var target_cell: Vector2i = Vector2i(-99999, -99999)  ## cell the active buffer was built for

# --- back buffer / in-progress job
var _wdist: PackedInt32Array
var _wx0: int = 0
var _wy0: int = 0
var _wcell: Vector2i = Vector2i(-99999, -99999)
var _queue: PackedInt32Array
var _head: int = 0
var _tail: int = 0
var job_active: bool = false
var builds_completed: int = 0
var node_budget: int = 1400


func _init(map_rect: Rect2, p_cell: float = 40.0, window_cells: int = 84) -> void:
	cell = p_cell
	inv_cell = 1.0 / p_cell
	map_origin = map_rect.position
	map_cols = int(ceil(map_rect.size.x * inv_cell))
	map_rows = int(ceil(map_rect.size.y * inv_cell))
	blocked.resize(map_cols * map_rows)
	blocked.fill(0)
	win = window_cells
	dist.resize(win * win)
	dist.fill(-1)
	_wdist.resize(win * win)
	next_pt.resize(win * win)
	stamp.resize(win * win)
	stamp.fill(0)
	_queue.resize(win * win)


func cell_center(gx: int, gy: int) -> Vector2:
	return map_origin + Vector2((gx + 0.5) * cell, (gy + 0.5) * cell)


## Marks every cell whose center lies within radius of center as blocked.
func block_circle(center: Vector2, radius: float) -> void:
	var r2 := radius * radius
	var gx0 := int(floor((center.x - radius - map_origin.x) * inv_cell))
	var gx1 := int(floor((center.x + radius - map_origin.x) * inv_cell))
	var gy0 := int(floor((center.y - radius - map_origin.y) * inv_cell))
	var gy1 := int(floor((center.y + radius - map_origin.y) * inv_cell))
	for gy in range(maxi(gy0, 0), mini(gy1, map_rows - 1) + 1):
		for gx in range(maxi(gx0, 0), mini(gx1, map_cols - 1) + 1):
			if cell_center(gx, gy).distance_squared_to(center) <= r2:
				blocked[gy * map_cols + gx] = 1


func is_blocked(p: Vector2) -> bool:
	var gx := int(floor((p.x - map_origin.x) * inv_cell))
	var gy := int(floor((p.y - map_origin.y) * inv_cell))
	if gx < 0 or gy < 0 or gx >= map_cols or gy >= map_rows:
		return true
	return blocked[gy * map_cols + gx] != 0


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - map_origin.x) * inv_cell)), int(floor((p.y - map_origin.y) * inv_cell)))


## Call every frame. Starts a background rebuild when the target changes cell and advances
## the running rebuild by `node_budget` nodes. force = rebuild synchronously right now.
## Returns true if a new field was swapped in this call.
func update(p_target: Vector2, force: bool = false) -> bool:
	target = p_target
	var tc := cell_of(p_target)
	if force:
		_start_job(tc)
		_run_job(1 << 30)
		return true
	if not job_active and tc != target_cell:
		_start_job(tc)
	if job_active:
		return _run_job(node_budget)
	return false


func _start_job(tc: Vector2i) -> void:
	_wcell = tc
	_wx0 = tc.x - win / 2
	_wy0 = tc.y - win / 2
	_wdist.fill(-1)
	var start := (tc.y - _wy0) * win + (tc.x - _wx0)
	_wdist[start] = 0
	_queue[0] = start
	_head = 0
	_tail = 1
	job_active = true


func _run_job(budget: int) -> bool:
	var w := win
	var mc := map_cols
	var mr := map_rows
	var x0 := _wx0
	var y0 := _wy0
	var wd := _wdist
	_wdist = PackedInt32Array()  # sole owner while we write (avoid copy-on-write)
	var q := _queue
	_queue = PackedInt32Array()
	var bl := blocked
	var head := _head
	var tail := _tail
	var processed := 0
	while head < tail and processed < budget:
		var cur := q[head]
		head += 1
		processed += 1
		var cx := cur % w
		var cy := cur / w
		var nd := wd[cur] + 1
		# +x
		if cx + 1 < w:
			var ni := cur + 1
			if wd[ni] == -1:
				var gx := cx + 1 + x0
				var gy := cy + y0
				if gx >= mc or gy < 0 or gy >= mr or bl[gy * mc + gx] != 0:
					wd[ni] = -2
				else:
					wd[ni] = nd
					q[tail] = ni
					tail += 1
		# -x
		if cx > 0:
			var ni := cur - 1
			if wd[ni] == -1:
				var gx := cx - 1 + x0
				var gy := cy + y0
				if gx < 0 or gy < 0 or gy >= mr or bl[gy * mc + gx] != 0:
					wd[ni] = -2
				else:
					wd[ni] = nd
					q[tail] = ni
					tail += 1
		# +y
		if cy + 1 < w:
			var ni := cur + w
			if wd[ni] == -1:
				var gx := cx + x0
				var gy := cy + 1 + y0
				if gx < 0 or gx >= mc or gy >= mr or bl[gy * mc + gx] != 0:
					wd[ni] = -2
				else:
					wd[ni] = nd
					q[tail] = ni
					tail += 1
		# -y
		if cy > 0:
			var ni := cur - w
			if wd[ni] == -1:
				var gx := cx + x0
				var gy := cy - 1 + y0
				if gx < 0 or gx >= mc or gy < 0 or bl[gy * mc + gx] != 0:
					wd[ni] = -2
				else:
					wd[ni] = nd
					q[tail] = ni
					tail += 1
	_head = head
	_tail = tail
	_queue = q
	if head < tail:
		_wdist = wd
		return false
	# done: swap into the active buffer
	_wdist = dist
	dist = wd
	win_x0 = _wx0
	win_y0 = _wy0
	target_cell = _wcell
	version += 1
	job_active = false
	builds_completed += 1
	return true


## Desired unit direction for an entity at p.
func sample(p: Vector2) -> Vector2:
	var gx := int(floor((p.x - map_origin.x) * inv_cell))
	var gy := int(floor((p.y - map_origin.y) * inv_cell))
	var wx := gx - win_x0
	var wy := gy - win_y0
	if wx < 0 or wy < 0 or wx >= win or wy >= win:
		return (target - p).normalized()
	var idx := wy * win + wx
	if dist[idx] <= 0:
		# target cell, blocked or unreachable: go straight
		return (target - p).normalized()
	if stamp[idx] != version:
		_compute_next(idx, wx, wy)
	return (next_pt[idx] - p).normalized()


func _compute_next(idx: int, wx: int, wy: int) -> void:
	stamp[idx] = version
	var best := dist[idx]
	var bx := wx
	var by := wy
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var nx := wx + ox
			var ny := wy + oy
			if nx < 0 or ny < 0 or nx >= win or ny >= win:
				continue
			var nd := dist[ny * win + nx]
			if nd < 0 or nd >= best:
				continue
			if ox != 0 and oy != 0:
				# no corner cutting: both orthogonal neighbors must be open
				if dist[wy * win + nx] < 0 or dist[ny * win + wx] < 0:
					continue
			best = nd
			bx = nx
			by = ny
	if (bx == wx and by == wy) or best == 0:
		next_pt[idx] = cell_center(target_cell.x, target_cell.y)
	else:
		next_pt[idx] = cell_center(bx + win_x0, by + win_y0)


## Path length in cells from p to the field's target (-1/-2 if unknown/unreachable). For tests.
func distance_at(p: Vector2) -> int:
	var gx := int(floor((p.x - map_origin.x) * inv_cell))
	var gy := int(floor((p.y - map_origin.y) * inv_cell))
	var wx := gx - win_x0
	var wy := gy - win_y0
	if wx < 0 or wy < 0 or wx >= win or wy >= win:
		return -1
	return dist[wy * win + wx]
