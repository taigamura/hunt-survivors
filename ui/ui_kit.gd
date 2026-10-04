class_name UIKit
extends RefCounted
## Code-built UI helpers so every screen shares one look (colors from ArtRegistry).


static func style(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s


static func label(text: String, size: int, color_id: String = "ui.text", align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ArtRegistry.color(color_id))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, size: int = 34, accent: bool = false, min_h: int = 96) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", size)
	var bg := ArtRegistry.color("ui.accent") if accent else ArtRegistry.color("ui.panel_hi")
	var fg := Color(0.08, 0.08, 0.1) if accent else ArtRegistry.color("ui.text")
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_stylebox_override("normal", style(bg, Color(1, 1, 1, 0.12), 2))
	b.add_theme_stylebox_override("hover", style(bg.lightened(0.12), Color(1, 1, 1, 0.3), 2))
	b.add_theme_stylebox_override("pressed", style(bg.darkened(0.2), Color(1, 1, 1, 0.3), 2))
	b.add_theme_stylebox_override("focus", style(bg, ArtRegistry.color("ui.accent2"), 3))
	b.focus_mode = Control.FOCUS_NONE
	return b


static func bg_rect(color_id: String = "ui.bg", alpha: float = 1.0) -> ColorRect:
	var r := ColorRect.new()
	var c := ArtRegistry.color(color_id)
	c.a = alpha
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## Full-rect margin container respecting the safe area.
static func safe_margin(vp: Viewport, extra: int = 24) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ins := GameState.safe_insets(vp)
	m.add_theme_constant_override("margin_top", int(ins["top"]) + extra)
	m.add_theme_constant_override("margin_bottom", int(ins["bottom"]) + extra)
	m.add_theme_constant_override("margin_left", int(ins["left"]) + extra)
	m.add_theme_constant_override("margin_right", int(ins["right"]) + extra)
	return m


static func fmt_time(sec: float) -> String:
	var s := int(maxf(sec, 0.0))
	return "%02d:%02d" % [s / 60, s % 60]


static func fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
