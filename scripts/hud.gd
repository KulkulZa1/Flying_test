class_name HUD
extends Control

const HUD_COLOR := Color(0.85, 1.0, 0.85, 0.9)

var target: Aircraft = null
var scoring: Scoring = null
var enemies: Array = []
var _font: Font

## Public and advanced by an explicit call rather than read from _process, so the
## banner's lifetime can be tested without a scene tree.
var banner_seconds := 0.0
var banner_score := 0

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

## Sized as fractions of viewport height rather than fixed pixels. Fixed pixels
## were tuned in a 648-high desktop window and render at about a millimetre on a
## 1080-high phone, which is invisible at arm's length.
func _font_size() -> int:
	return int(maxf(14.0, size.y * 0.038))

func _line_width() -> float:
	return maxf(2.0, size.y * 0.0030)

func _reticle_radius() -> float:
	return maxf(10.0, size.y * 0.022)

func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_death(final_score: int) -> void:
	banner_score = final_score
	banner_seconds = Config.DEATH_BANNER_SECONDS

func advance_banner(delta: float) -> void:
	banner_seconds = maxf(banner_seconds - delta, 0.0)

func _process(delta: float) -> void:
	advance_banner(delta)
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
	if banner_seconds > 0.0:
		_draw_death_banner(centre)

func _draw_reticle(centre: Vector2) -> void:
	draw_arc(centre, _reticle_radius(), 0.0, TAU, 32, HUD_COLOR, _line_width())
	draw_line(centre + Vector2(-_reticle_radius() * 1.85, 0.0), centre + Vector2(-_reticle_radius() * 1.15, 0.0), HUD_COLOR, _line_width())
	draw_line(centre + Vector2(_reticle_radius() * 1.15, 0.0), centre + Vector2(_reticle_radius() * 1.85, 0.0), HUD_COLOR, _line_width())

func _draw_horizon(centre: Vector2) -> void:
	var pitch := asin(clampf(target.model.forward().y, -1.0, 1.0))
	var mid := centre + Vector2(0.0, horizon_offset(pitch, size.y))
	var half := horizon_direction(target.model.bank_angle()) * (size.x * 0.22)
	draw_line(mid - half, mid - half * 0.25, HUD_COLOR, _line_width())
	draw_line(mid + half * 0.25, mid + half, HUD_COLOR, _line_width())

func _draw_readouts() -> void:
	var model := target.model
	_text(Vector2(size.y * 0.04, size.y * 0.5), "SPD %4d" % int(round(model.speed)))
	_text(Vector2(size.x - size.y * 0.26, size.y * 0.5), "ALT %5d" % int(round(model.position.y)))
	_text(Vector2(size.y * 0.04, size.y - size.y * 0.055), "THR %3d%%" % int(round(model.throttle * 100.0)))

func _text(at: Vector2, content: String) -> void:
	draw_string(_font, at, content, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(), HUD_COLOR)

func _draw_health() -> void:
	var fraction := clampf(target.hp / maxf(target.max_hp, 1.0), 0.0, 1.0)
	var bar := Rect2(size.y * 0.04, size.y - size.y * 0.115, size.x * 0.18, size.y * 0.022)
	draw_rect(bar, HUD_COLOR, false, _line_width())
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), HUD_COLOR)

func _draw_score() -> void:
	if scoring == null:
		return
	_text(Vector2(size.x - size.y * 0.42, size.y * 0.06), "SCORE %7d" % scoring.score)
	_text(Vector2(size.x - size.y * 0.42, size.y * 0.11), "BEST  %7d" % scoring.high_score)
	if scoring.multiplier > 1.0:
		_text(Vector2(size.x - size.y * 0.42, size.y * 0.16), "x%.1f" % scoring.multiplier)

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
		draw_circle(centre + marker_direction(view, relative) * (size.y * 0.40), maxf(5.0, size.y * 0.010), HUD_COLOR)

## Deliberately drawn over everything else: the only other signal that a run
## ended is the score snapping to zero, which reads as a glitch rather than a
## death.
func _draw_death_banner(centre: Vector2) -> void:
	_text(centre + Vector2(-size.y * 0.13, -size.y * 0.04), "SHOT DOWN")
	_text(centre + Vector2(-size.y * 0.13, size.y * 0.01), "SCORE %d" % banner_score)
