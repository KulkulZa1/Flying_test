extends SceneTree

const SUITES := [
	"res://tests/test_config.gd",
	"res://tests/test_flight_model.gd",
	"res://tests/test_terrain.gd",
	"res://tests/test_aircraft.gd",
	"res://tests/test_camera.gd",
	"res://tests/test_controls.gd",
	"res://tests/test_game.gd",
	"res://tests/test_hud.gd",
	"res://tests/test_touch.gd",
	"res://tests/test_boundary.gd",
	"res://tests/test_boundary_integration.gd",
	"res://tests/test_ballistics.gd",
	"res://tests/test_weapon.gd",
]

var _checks := 0
var _failures: Array[String] = []
var _suites_completed := 0
var _current := ""

func _initialize() -> void:
	for path in SUITES:
		_run_suite(path)
	if _suites_completed != SUITES.size():
		_failures.append("only %d of %d suites ran to completion - scan the output above for SCRIPT ERROR"
			% [_suites_completed, SUITES.size()])
	print("checks: %d  failures: %d" % [_checks, _failures.size()])
	for message in _failures:
		print("FAIL: ", message)
	quit(1 if _failures.size() > 0 else 0)

## Runs one suite. GDScript has no exception handling, but a runtime error
## unwinds only the function it occurs in. Keeping load/new/runner-assignment
## in here means such an error returns control to _initialize()'s loop instead
## of aborting it, so quit() is always reached and the process can never hang.
## _suites_completed is incremented only on a clean finish.
## A test that asserts once and then errors still reports green here; failures: 0
## is not proof every assertion ran. tests/run.sh catches that via SCRIPT ERROR.
func _run_suite(path: String) -> void:
	var script: GDScript = load(path)
	var suite: TestCase = script.new()
	suite.runner = self
	var seen := {}
	for method in suite.get_method_list():
		var name: String = method.name
		if name.begins_with("test_") and not seen.has(name):
			seen[name] = true
			_current = "%s#%s" % [path.get_file(), name]
			var before := _checks
			suite.call(name)
			if _checks == before:
				_failures.append("[%s] recorded no checks - it probably errored before asserting" % _current)
	_suites_completed += 1

func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("[%s] %s" % [_current, message])

func check_approx(actual: float, expected: float, tol: float, message: String) -> void:
	check(actual == expected or absf(actual - expected) <= tol,
		"%s (got %.6f, expected %.6f +/- %.6f)" % [message, actual, expected, tol])
