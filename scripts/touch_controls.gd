class_name TouchControls
extends Control

const UI_COLOR := Color(1.0, 1.0, 1.0, 0.35)

var aim := Vector2.ZERO        # -1..1, read by PlayerController
var throttle_delta := 0.0      # -1..1
var fire := false

var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_current := Vector2.ZERO

## A drag of TOUCH_STICK_RADIUS is full deflection; beyond that it saturates.
static func stick_aim(origin: Vector2, current: Vector2) -> Vector2:
	return ((current - origin) / Config.TOUCH_STICK_RADIUS).limit_length(1.0)

static func is_active() -> bool:
	return Config.FORCE_TOUCH_UI or DisplayServer.is_touchscreen_available()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag and event.index == _stick_touch:
		_stick_current = event.position
		aim = stick_aim(_stick_origin, _stick_current)

func _handle_touch(event: InputEventScreenTouch) -> void:
	var on_left := event.position.x < size.x * 0.5
	if event.pressed and on_left and _stick_touch == -1:
		_stick_touch = event.index
		_stick_origin = event.position
		_stick_current = event.position
		aim = Vector2.ZERO
	elif event.pressed and not on_left:
		_press_right(event.position)
	elif not event.pressed:
		if event.index == _stick_touch:
			_stick_touch = -1
			aim = Vector2.ZERO
		else:
			throttle_delta = 0.0
			fire = false

func _press_right(at: Vector2) -> void:
	if at.x > size.x * 0.8 and at.y > size.y * 0.6:
		fire = true
	elif at.y < size.y * 0.5:
		throttle_delta = 1.0
	else:
		throttle_delta = -1.0

func _draw() -> void:
	if _stick_touch != -1:
		draw_arc(_stick_origin, Config.TOUCH_STICK_RADIUS, 0.0, TAU, 40, UI_COLOR, 2.0)
		draw_circle(_stick_current, 26.0, UI_COLOR)
	var throttle_x := size.x * 0.78
	draw_rect(Rect2(throttle_x, size.y * 0.18, 64.0, size.y * 0.30), UI_COLOR, false, 2.0)
	draw_rect(Rect2(throttle_x, size.y * 0.52, 64.0, size.y * 0.30), UI_COLOR, false, 2.0)
	draw_circle(Vector2(size.x * 0.90, size.y * 0.80), 44.0, UI_COLOR)
