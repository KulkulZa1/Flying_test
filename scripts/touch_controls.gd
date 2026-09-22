class_name TouchControls
extends Control

const UI_COLOR := Color(1.0, 1.0, 1.0, 0.35)

var aim := Vector2.ZERO        # -1..1, read by PlayerController
var throttle_delta := 0.0      # -1..1
var fire := false

var _stick_touch := -1
var _throttle_touch := -1
var _fire_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_current := Vector2.ZERO

## A drag of TOUCH_STICK_RADIUS is full deflection; beyond that it saturates.
static func stick_aim(origin: Vector2, current: Vector2) -> Vector2:
	return ((current - origin) / Config.TOUCH_STICK_RADIUS).limit_length(1.0)

## Gated on the platform, not on touch availability. is_touchscreen_available()
## returns true whenever mouse-to-touch emulation is enabled - which it is, so
## that the touch layout can be exercised on desktop - and also on any touch
## laptop or 2-in-1. Either would silently replace the keyboard and mouse with
## the touch layout on a desktop build.
static func is_active() -> bool:
	return Config.FORCE_TOUCH_UI or OS.has_feature("mobile")

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

## The drawn shapes and the live hit zones are the same geometry, deliberately.
## They used to differ: the whole right half moved the throttle while the drawn
## boxes did nothing, so the controls were invisible and the visible ones inert.
func fire_centre() -> Vector2:
	return Vector2(size.x - size.y * 0.16, size.y * 0.74)

func fire_radius() -> float:
	return size.y * 0.13

func throttle_rect() -> Rect2:
	var width := size.y * 0.16
	return Rect2(size.x - size.y * 0.42, size.y * 0.10, width, size.y * 0.52)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)

func _press(index: int, at: Vector2) -> void:
	if at.x < size.x * 0.5:
		if _stick_touch == -1:
			_stick_touch = index
			_stick_origin = at
			_stick_current = at
			aim = Vector2.ZERO
		return
	if at.distance_to(fire_centre()) <= fire_radius():
		_fire_touch = index
		fire = true
	elif throttle_rect().has_point(at):
		_throttle_touch = index
		throttle_delta = _throttle_at(at)

## Only the finger that lifted loses its role. Clearing unconditionally meant
## letting go of the throttle also stopped you shooting.
func _release(index: int) -> void:
	if index == _stick_touch:
		_stick_touch = -1
		aim = Vector2.ZERO
	elif index == _fire_touch:
		_fire_touch = -1
		fire = false
	elif index == _throttle_touch:
		_throttle_touch = -1
		throttle_delta = 0.0

func _drag(index: int, at: Vector2) -> void:
	if index == _stick_touch:
		_stick_current = at
		aim = stick_aim(_stick_origin, _stick_current)
	elif index == _throttle_touch:
		# A drag retargets the throttle, so it behaves as the slider the spec
		# describes rather than as two latching buttons.
		throttle_delta = _throttle_at(at)

func _throttle_at(at: Vector2) -> float:
	var rect := throttle_rect()
	return 1.0 if at.y < rect.position.y + rect.size.y * 0.5 else -1.0

## Called on focus loss: Android may cancel touches wholesale when the app goes
## to the background, which would otherwise resume with a stuck stick and a
## stuck trigger.
func release_all() -> void:
	_stick_touch = -1
	_throttle_touch = -1
	_fire_touch = -1
	aim = Vector2.ZERO
	throttle_delta = 0.0
	fire = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()

func _draw() -> void:
	if _stick_touch != -1:
		draw_arc(_stick_origin, Config.TOUCH_STICK_RADIUS, 0.0, TAU, 40, UI_COLOR, 2.0)
		draw_circle(_stick_current, Config.TOUCH_STICK_RADIUS * 0.22, UI_COLOR)
	var rect := throttle_rect()
	draw_rect(rect, UI_COLOR, false, 2.0)
	draw_line(Vector2(rect.position.x, rect.get_center().y),
		Vector2(rect.end.x, rect.get_center().y), UI_COLOR, 2.0)
	draw_arc(fire_centre(), fire_radius(), 0.0, TAU, 32, UI_COLOR, 3.0)
