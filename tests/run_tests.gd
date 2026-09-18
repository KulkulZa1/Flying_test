extends SceneTree

const SUITES := [
	"res://tests/test_smoke.gd",
]

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	for path in SUITES:
		var script: GDScript = load(path)
		var suite: TestCase = script.new()
		suite.runner = self
		var seen := {}
		for method in suite.get_method_list():
			var name: String = method.name
			if name.begins_with("test_") and not seen.has(name):
				seen[name] = true
				suite.call(name)
	print("checks: %d  failures: %d" % [_checks, _failures.size()])
	for message in _failures:
		print("FAIL: ", message)
	quit(1 if _failures.size() > 0 else 0)

func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func check_approx(actual: float, expected: float, tol: float, message: String) -> void:
	check(absf(actual - expected) <= tol,
		"%s (got %.6f, expected %.6f +/- %.6f)" % [message, actual, expected, tol])
