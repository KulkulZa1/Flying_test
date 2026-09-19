class_name HUD
extends Control

const HUD_COLOR := Color(0.85, 1.0, 0.85, 0.9)

var target: Aircraft = null
var scoring: Scoring = null
var enemies: Array = []
var _font: Font

## Nose up puts the real horizon BELOW the reticle, and screen Y grows downward,
## so positive pitch gives a positive offset.
static func horizon_offset(pitch: float, view_height: float) -> float:
	return (pitch / deg_to_rad(45.0)) * (view_height * 0.35)

## The horizon counter-rotates against the aircraft: a right bank drops the right
## wing, so the horizon's right end rises on screen, which is negative Y.
static func horizon_direction(bank: float) -> Vector2:
	return Vector2(cos(bank), -sin(bank))

## True when a world-relative offset lies behind the viewer. Forward is -Z, so a
## positive local Z is astern.
static func is_behind(view: Basis, relative: Vector3) -> bool:
	return (view.inverse() * relative).z > 0.0

## Screen-space direction from the reticle toward a world point, in the pilot's
## own frame. Y is negated because screen Y grows downward.
static func marker_direction(view: Basis, relative: Vector3) -> Vector2:
	var local := view.inverse() * relative
	var flat := Vector2(local.x, -local.y)
	if flat.length_squared() < 1e-6:
		return Vector2(0.0, 1.0)  # dead astern with no lateral offset: mark below
	return flat.normalized()

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
	_draw_health()
	_draw_score()
	_draw_enemy_markers(centre)

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

func _draw_health() -> void:
	var fraction := clampf(target.hp / maxf(target.max_hp, 1.0), 0.0, 1.0)
	var bar := Rect2(28.0, size.y - 76.0, 220.0, 14.0)
	draw_rect(bar, HUD_COLOR, false, 2.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), HUD_COLOR)

func _draw_score() -> void:
	if scoring == null:
		return
	_text(Vector2(size.x - 220.0, 44.0), "SCORE %7d" % scoring.score)
	_text(Vector2(size.x - 220.0, 68.0), "BEST  %7d" % scoring.high_score)
	if scoring.multiplier > 1.0:
		_text(Vector2(size.x - 220.0, 92.0), "x%.1f" % scoring.multiplier)

## A chevron at the screen edge for every enemy that is not comfortably ahead, so
## a dogfight does not become a hunt for something behind you.
func _draw_enemy_markers(centre: Vector2) -> void:
	var view := target.model.basis
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var relative: Vector3 = enemy.model.position - target.model.position
		if relative.length_squared() < 1e-6:
			continue
		if not is_behind(view, relative) and target.model.forward().angle_to(relative.normalized()) < 0.5:
			continue  # already on screen
		draw_circle(centre + marker_direction(view, relative) * (size.y * 0.40), 6.0, HUD_COLOR)
