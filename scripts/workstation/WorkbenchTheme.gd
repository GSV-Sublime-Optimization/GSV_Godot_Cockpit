extends RefCounted

## Native Godot UI theme, no external assets or required plugins.
const BG := Color("#0b111c")
const SURFACE := Color("#141e2c")
const PANEL := Color("#192537")
const HOVER := Color("#25364a")
const EDGE := Color("#30445c")
const TEXT := Color("#e7f0f7")
const MUTED := Color("#9db0c3")
const CYAN := Color("#63d8ed")
const GOLD := Color("#eab968")
const GREEN := Color("#78d4aa")
const RED := Color("#eb8c96")

static func panel_style(fill: Color = SURFACE, outline: Color = EDGE) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = outline
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

static func button_style(fill: Color, outline: Color) -> StyleBoxFlat:
	var box := panel_style(fill, outline)
	box.set_corner_radius_all(6)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box

static func make_theme() -> Theme:
	var result := Theme.new()
	result.set_color("font_color", "Label", TEXT)
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_pressed_color", "Button", CYAN)
	result.set_color("font_color", "LineEdit", TEXT)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("font_color", "ItemList", TEXT)
	result.set_color("font_selected_color", "ItemList", TEXT)
	result.set_color("font_color", "TabBar", MUTED)
	result.set_color("font_selected_color", "TabBar", CYAN)
	result.set_color("font_unselected_color", "TabBar", MUTED)
	result.set_stylebox("panel", "PanelContainer", panel_style())
	result.set_stylebox("normal", "Button", button_style(PANEL, EDGE))
	result.set_stylebox("hover", "Button", button_style(HOVER, CYAN))
	result.set_stylebox("pressed", "Button", button_style(HOVER, GOLD))
	result.set_stylebox("disabled", "Button", button_style(SURFACE, EDGE))
	result.set_stylebox("normal", "LineEdit", panel_style(PANEL))
	result.set_stylebox("focus", "LineEdit", panel_style(PANEL, CYAN))
	result.set_stylebox("panel", "TabContainer", panel_style())
	result.set_stylebox("tab_selected", "TabBar", button_style(PANEL, CYAN))
	result.set_stylebox("tab_unselected", "TabBar", button_style(SURFACE, EDGE))
	result.set_stylebox("tab_hovered", "TabBar", button_style(HOVER, CYAN))
	result.set_stylebox("panel", "ItemList", panel_style(SURFACE))
	result.set_stylebox("selected", "ItemList", button_style(HOVER, CYAN))
	result.set_stylebox("selected_focus", "ItemList", button_style(HOVER, CYAN))
	result.set_font_size("font_size", "Label", 14)
	result.set_font_size("font_size", "Button", 12)
	result.set_font_size("font_size", "ItemList", 13)
	result.set_font_size("font_size", "TabBar", 12)
	return result
