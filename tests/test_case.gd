class_name TestCase
extends RefCounted

var runner: Object = null

func check(condition: bool, message: String) -> void:
	runner.check(condition, message)

func check_approx(actual: float, expected: float, tol: float, message: String) -> void:
	runner.check_approx(actual, expected, tol, message)
