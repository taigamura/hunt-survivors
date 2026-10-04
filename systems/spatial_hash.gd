class_name SpatialHash
extends RefCounted
## Uniform-grid spatial hash over a window that follows the player.
## Rebuilt every frame with a counting sort (no per-cell arrays, no allocations).
## Items outside the window are clamped into the edge cells (they're far off-screen anyway).

var cell_size: float
var inv_cell: float
var cols: int
var rows: int
var origin: Vector2 = Vector2.ZERO
var half_extent: float

var cell_start: PackedInt32Array  ## size cols*rows + 1
var cell_count: PackedInt32Array
var items: PackedInt32Array        ## entity indices sorted by cell
var item_cell: PackedInt32Array
var n_items: int = 0


func _init(window_size: float = 3600.0, p_cell: float = 80.0) -> void:
	cell_size = p_cell
	inv_cell = 1.0 / p_cell
	cols = int(ceil(window_size * inv_cell))
	rows = cols
	half_extent = cols * cell_size * 0.5
	cell_start.resize(cols * rows + 1)
	cell_count.resize(cols * rows)


func cell_xy(p: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int((p.x - origin.x) * inv_cell), 0, cols - 1),
		clampi(int((p.y - origin.y) * inv_cell), 0, rows - 1))


func cell_of(p: Vector2) -> int:
	var cx := clampi(int((p.x - origin.x) * inv_cell), 0, cols - 1)
	var cy := clampi(int((p.y - origin.y) * inv_cell), 0, rows - 1)
	return cy * cols + cx


## positions: indexed by entity id. ids: the first n entries are the live entity ids.
func build(positions: PackedVector2Array, ids: PackedInt32Array, n: int, center: Vector2) -> void:
	origin = center - Vector2(half_extent, half_extent)
	n_items = n
	if items.size() < n:
		items.resize(n + 256)
		item_cell.resize(n + 256)
	cell_count.fill(0)
	var ox := origin.x
	var oy := origin.y
	var ic := inv_cell
	var cmax := cols - 1
	var rmax := rows - 1
	for k in n:
		var p := positions[ids[k]]
		var cx := clampi(int((p.x - ox) * ic), 0, cmax)
		var cy := clampi(int((p.y - oy) * ic), 0, rmax)
		var c := cy * cols + cx
		item_cell[k] = c
		cell_count[c] += 1
	var acc := 0
	var total := cols * rows
	for c in total:
		cell_start[c] = acc
		acc += cell_count[c]
	cell_start[total] = acc
	# Fill back-to-front using cell_count as a decrementing cursor.
	var k2 := n - 1
	while k2 >= 0:
		var c := item_cell[k2]
		cell_count[c] -= 1
		items[cell_start[c] + cell_count[c]] = ids[k2]
		k2 -= 1


## Candidate ids whose cells overlap the axis-aligned rect (caller filters exactly).
func candidates(rect: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var a := cell_xy(rect.position)
	var b := cell_xy(rect.end)
	for cy in range(a.y, b.y + 1):
		var row := cy * cols
		for cx in range(a.x, b.x + 1):
			var c := row + cx
			var s := cell_start[c]
			var e := cell_start[c + 1]
			for k in range(s, e):
				out.append(items[k])
	return out
