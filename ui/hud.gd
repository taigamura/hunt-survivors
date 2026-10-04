class_name HUD
extends Control
## Portrait HUD drawn in one pass: KO counter, timer, monster bar, banners, XP bar,
## Musou button, off-screen indicators, damage vignette. Handles the two on-screen buttons.

var hunt: Node  ## Hunt (untyped to avoid a cyclic class reference)
var font: Font

var banners: Array[Dictionary] = []
var banner_time: float = 0.0
var milestone_text: String = ""
var milestone_time: float = 0.0
var vignette: float = 0.0
var flash: float = 0.0
var musou_rect: Rect2
var pause_rect: Rect2
var insets: Dictionary = {}
var _clock: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	insets = GameState.safe_insets(get_viewport())


func banner(text: String, color_id: String = "ui.accent", time: float = 1.6) -> void:
	if banners.size() > 3:
		banners.pop_front()
	banners.append({"text": text, "color": ArtRegistry.color(color_id), "time": time})


func milestone(text: String) -> void:
	milestone_text = text
	milestone_time = 1.4


func hurt() -> void:
	vignette = Tuning.f("juice.vignette_time", 0.4)


func flash_screen(strength: float = 0.8) -> void:
	flash = strength


func layout() -> void:
	var sz := get_viewport_rect().size
	var b := float(insets.get("bottom", 10.0))
	var t := float(insets.get("top", 10.0))
	var l := float(insets.get("left", 10.0))
	var r := float(insets.get("right", 10.0))
	var mr := 66.0
	var cy := sz.y - b - 44.0 - mr
	var cx := (l + 34.0 + mr) if GameState.musou_left else (sz.x - r - 34.0 - mr)
	musou_rect = Rect2(cx - mr - 10, cy - mr - 10, (mr + 10) * 2, (mr + 10) * 2)
	pause_rect = Rect2(l + 8, t + 8, 72, 72)


func blocked_rects() -> Array[Rect2]:
	return [musou_rect, pause_rect]


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		var p := (event as InputEventScreenTouch).position
		if musou_rect.has_point(p):
			hunt.call("request_musou")
			get_viewport().set_input_as_handled()
		elif pause_rect.has_point(p):
			hunt.call("toggle_pause")
			get_viewport().set_input_as_handled()


func step(dt: float) -> void:
	_clock += dt
	if not banners.is_empty():
		banner_time += dt
		if banner_time >= float(banners[0]["time"]):
			banners.pop_front()
			banner_time = 0.0
	if milestone_time > 0.0:
		milestone_time -= dt
	if vignette > 0.0:
		vignette -= dt
	if flash > 0.0:
		flash = maxf(0.0, flash - dt * 1.6)
	layout()
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, size: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, width: float = -1.0) -> void:
	var w := width
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER and width < 0.0:
		var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		p.x -= tw * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT and width < 0.0:
		var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		p.x -= tw
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, w, size, maxi(4, size / 6), Color(0, 0, 0, col.a * 0.9))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, w, size, col)


func _draw() -> void:
	if hunt == null:
		return
	var sz := get_viewport_rect().size
	var top := float(insets.get("top", 10.0))
	var bottom := float(insets.get("bottom", 10.0))
	var left := float(insets.get("left", 10.0))
	var right := float(insets.get("right", 10.0))
	var txt := ArtRegistry.color("ui.text")
	var dim := ArtRegistry.color("ui.text_dim")
	var accent := ArtRegistry.color("ui.accent")
	var danger := ArtRegistry.color("ui.danger")

	_draw_offscreen_indicators(sz)

	# --- vignette
	if vignette > 0.0:
		var a := clampf(vignette / 0.4, 0.0, 1.0) * 0.55
		_vignette(sz, Color(danger.r, danger.g * 0.3, danger.b * 0.3, a))
	var player: Player = hunt.get("player")
	if player != null and player.hp / player.max_hp < 0.3:
		var pulse := 0.5 + 0.5 * sin(_clock * 6.0)
		_vignette(sz, Color(0.8, 0.05, 0.05, 0.12 + 0.12 * pulse))

	# --- pause button
	draw_rect(pause_rect, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(pause_rect.position + Vector2(24, 20), Vector2(8, 32)), txt)
	draw_rect(Rect2(pause_rect.position + Vector2(40, 20), Vector2(8, 32)), txt)

	# --- timer (top right)
	var run_time: float = hunt.get("run_time")
	var limit: float = hunt.get("time_limit")
	var remain := limit - run_time
	var tcol := danger if remain < 60.0 else txt
	_text(Vector2(sz.x - right - 18, top + 50), UIKit.fmt_time(run_time), 36, tcol, HORIZONTAL_ALIGNMENT_RIGHT)

	# --- KO counter (top center)
	var kos: int = hunt.get("kos")
	_text(Vector2(sz.x * 0.5, top + 66), UIKit.fmt_int(kos), 60, accent)
	_text(Vector2(sz.x * 0.5, top + 94), "KOs", 22, dim)

	# --- monster bar
	var monster: Ironhorn = hunt.get("monster")
	var bar_y := top + 124.0
	if monster != null and monster.is_alive():
		var bx := left + 30.0
		var bw := sz.x - left - right - 60.0
		var name_col := danger if monster.enraged else txt
		_text(Vector2(bx, bar_y), String(Tuning.g("monster.name", "IRONHORN")) + ("  ENRAGED" if monster.enraged else ""), 24, name_col, HORIZONTAL_ALIGNMENT_LEFT)
		# part icons (right side)
		var ix := bx + bw - 3 * 46.0
		for pn in Ironhorn.PART_NAMES:
			var r := Rect2(ix, bar_y - 26, 40, 32)
			var broken := monster.is_broken(pn)
			draw_rect(r, Color(0, 0, 0, 0.55))
			draw_rect(r, accent if broken else dim, false, 2.0)
			_text(r.position + Vector2(20, 25), pn.substr(0, 1).to_upper(), 22, dim if broken else txt)
			if broken:
				draw_line(r.position, r.end, danger, 3.0)
				draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), danger, 3.0)
			ix += 46.0
		var frac := clampf(monster.hp / monster.max_hp, 0.0, 1.0)
		var br := Rect2(bx, bar_y + 12, bw, 20)
		draw_rect(br.grow(3), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(br.position, Vector2(br.size.x * frac, br.size.y)), ArtRegistry.color("ui.monster_hp"))
		var ef := monster.max_hp * Tuning.f("monster.enrage_hp_frac", 0.3) / monster.max_hp
		draw_line(Vector2(bx + bw * ef, br.position.y), Vector2(bx + bw * ef, br.end.y), Color(0, 0, 0, 0.6), 2.0)

	# --- milestone popup
	if milestone_time > 0.0:
		var t := 1.0 - milestone_time / 1.4
		var sc := 1.0 + 0.6 * maxf(0.0, 1.0 - t * 5.0)
		var a := clampf(milestone_time / 0.4, 0.0, 1.0)
		var c := ArtRegistry.color("ui.ko_popup")
		c.a = a
		_text(Vector2(sz.x * 0.5, top + 230), milestone_text, int(48 * sc), c)

	# --- banner
	if not banners.is_empty():
		var bn := banners[0]
		var t := banner_time / float(bn["time"])
		var a := clampf(minf(t * 6.0, (1.0 - t) * 4.0), 0.0, 1.0)
		var y := sz.y * 0.34
		var slide := (1.0 - clampf(t * 6.0, 0.0, 1.0)) * 120.0
		draw_rect(Rect2(0, y - 52, sz.x, 76), Color(0, 0, 0, 0.55 * a))
		var c: Color = bn["color"]
		c.a = a
		_text(Vector2(sz.x * 0.5 + slide, y), String(bn["text"]), 44, c)

	# --- XP bar (bottom edge)
	var prog: Progression = hunt.get("progression")
	var xy := sz.y - bottom - 18.0
	var xr := Rect2(left + 12, xy, sz.x - left - right - 24, 12)
	draw_rect(xr.grow(2), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(xr.position, Vector2(xr.size.x * prog.progress(), xr.size.y)), ArtRegistry.color("ui.xp"))
	_text(Vector2(left + 14, xy - 10), "Lv %d" % prog.level, 26, txt, HORIZONTAL_ALIGNMENT_LEFT)

	# --- musou button
	_draw_musou_button()

	# --- debug perf line
	if OS.is_debug_build():
		var en: EnemySystem = hunt.get("enemies")
		_text(Vector2(left + 14, xy - 44), "%d fps  %d foes" % [Engine.get_frames_per_second(), en.n_active], 18, dim, HORIZONTAL_ALIGNMENT_LEFT)

	# --- screen flash
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 0.97, 0.85, clampf(flash, 0.0, 1.0) * 0.8))


func _draw_musou_button() -> void:
	var gauge: MusouGauge = hunt.get("musou")
	var c := musou_rect.get_center()
	var r := musou_rect.size.x * 0.5 - 10.0
	var col := ArtRegistry.color("fx.musou")
	var full := gauge.is_full()
	var active: bool = float(hunt.get("musou_timer")) > 0.0
	if full:
		var pulse := 0.5 + 0.5 * sin(_clock * 8.0)
		draw_circle(c, r + 12.0 + 6.0 * pulse, Color(col.r, col.g, col.b, 0.25 + 0.2 * pulse))
	draw_circle(c, r, Color(0, 0, 0, 0.55) if not full else Color(col.r * 0.5, col.g * 0.4, col.b * 0.1, 0.9))
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.15), 8.0)
	draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * gauge.fraction(), 48, col, 8.0)
	var tc := Color(1, 1, 1) if full else Color(1, 1, 1, 0.5)
	if gauge.is_locked() and not active:
		_text(c + Vector2(0, 2), "MUSOU", 22, Color(1, 1, 1, 0.35))
		_text(c + Vector2(0, 30), "%ds" % ceili(gauge.lock_timer), 22, Color(1, 1, 1, 0.5))
	else:
		_text(c + Vector2(0, 10), "MUSOU" if not active else "!!!", 26, tc)


func _vignette(sz: Vector2, c: Color) -> void:
	var steps := 6
	for k in steps:
		var w := 14.0 * (k + 1)
		var a := c.a * (1.0 - float(k) / steps) * 0.5
		var cc := Color(c.r, c.g, c.b, a)
		draw_rect(Rect2(0, 0, sz.x, w), cc)
		draw_rect(Rect2(0, sz.y - w, sz.x, w), cc)
		draw_rect(Rect2(0, 0, w, sz.y), cc)
		draw_rect(Rect2(sz.x - w, 0, w, sz.y), cc)


func _draw_offscreen_indicators(sz: Vector2) -> void:
	var xf := get_viewport().get_canvas_transform()
	var margin := 46.0
	var rect := Rect2(Vector2(margin, margin + float(insets.get("top", 10.0)) + 140.0), sz - Vector2(margin * 2.0, margin * 2.0 + float(insets.get("top", 10.0)) + 140.0 + 70.0))
	var center := sz * 0.5
	# outposts
	var ops: Outposts = hunt.get("outposts")
	if ops != null:
		for k in ops.positions.size():
			var sp := xf * ops.positions[k]
			if rect.has_point(sp):
				continue
			var p := _edge_point(center, sp, rect)
			var col := ArtRegistry.color("outpost.captured") if ops.is_captured(k) else ArtRegistry.color("outpost.neutral")
			draw_circle(p, 13.0, Color(0, 0, 0, 0.6))
			draw_rect(Rect2(p + Vector2(-2, -9), Vector2(3, 18)), col)
			draw_colored_polygon(PackedVector2Array([p + Vector2(1, -9), p + Vector2(11, -5), p + Vector2(1, -1)]), col)
	# monster
	var monster: Ironhorn = hunt.get("monster")
	if monster != null and monster.is_alive():
		var sp := xf * monster.position
		if not rect.grow(40.0).has_point(sp):
			var p := _edge_point(center, sp, rect)
			var dir := (sp - center).normalized()
			var col := ArtRegistry.color("ui.danger")
			var pulse := 0.8 + 0.2 * sin(_clock * 10.0)
			var tip := p + dir * 22.0 * pulse
			var side := dir.orthogonal() * 16.0
			draw_colored_polygon(PackedVector2Array([tip, p - dir * 8.0 + side, p - dir * 8.0 - side]), col)
			draw_circle(p - dir * 22.0, 15.0, Color(0, 0, 0, 0.6))
			_text(p - dir * 22.0 + Vector2(0, 8), "!", 24, col)


static func _edge_point(center: Vector2, target: Vector2, rect: Rect2) -> Vector2:
	var d := target - center
	if d.length_squared() < 0.01:
		return center
	var tx := INF
	var ty := INF
	if absf(d.x) > 0.001:
		tx = ((rect.end.x if d.x > 0.0 else rect.position.x) - center.x) / d.x
	if absf(d.y) > 0.001:
		ty = ((rect.end.y if d.y > 0.0 else rect.position.y) - center.y) / d.y
	return center + d * minf(tx, ty)
