class_name HUD
extends Control

const HUD_COLOR := Color(0.85, 1.0, 0.85, 0.9)

var target: Aircraft = null
var _font: Font

## Nose up puts the real horizon BELOW the reticle, and screen Y grows downward,
## so positive pitch gives a positive offset.
static func horizon_offset(pitch: float, view_height: float) -> float:
	return (pitch / deg_to_rad(45.0)) * (view_height * 0.35)

## The horizon counter-rotates against the aircraft: a right bank drops the right
## wing, so the horizon's right end rises on screen, which is negative Y.
static func horizon_direction(bank: float) -> Vector2:
	return Vector2(cos(bank), -sin(bank))

func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if target == null:
		return
	var centre := size * 0.5
	_draw_reticle(centre)
	_draw_horizon(centre)
	_draw_readouts()

func _draw_reticle(centre: Vector2) -> void:
	draw_arc(centre, 14.0, 0.0, TAU, 32, HUD_COLOR, 2.0)
	draw_line(centre + Vector2(-26.0, 0.0), centre + Vector2(-16.0, 0.0), HUD_COLOR, 2.0)
	draw_line(centre + Vector2(16.0, 0.0), centre + Vector2(26.0, 0.0), HUD_COLOR, 2.0)

func _draw_horizon(centre: Vector2) -> void:
	var pitch := asin(clampf(target.model.forward().y, -1.0, 1.0))
	var mid := centre + Vector2(0.0, horizon_offset(pitch, size.y))
	var half := horizon_direction(target.model.bank_angle()) * (size.x * 0.22)
	draw_line(mid - half, mid - half * 0.25, HUD_COLOR, 2.0)
	draw_line(mid + half * 0.25, mid + half, HUD_COLOR, 2.0)

func _draw_readouts() -> void:
	var model := target.model
	_text(Vector2(28.0, size.y * 0.5), "SPD %4d" % int(round(model.speed)))
	_text(Vector2(size.x - 130.0, size.y * 0.5), "ALT %5d" % int(round(model.position.y)))
	_text(Vector2(28.0, size.y - 40.0), "THR %3d%%" % int(round(model.throttle * 100.0)))

func _text(at: Vector2, content: String) -> void:
	draw_string(_font, at, content, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, HUD_COLOR)
