class_name Ballistics
extends RefCounted

## True when the swept segment a->b passes within radius of centre. Swept rather
## than point-sampled because a 600 m/s round covers 10 m in a single tick against
## a 6 m target: testing only the endpoints would let it pass straight through.
static func segment_hits_sphere(a: Vector3, b: Vector3, centre: Vector3, radius: float) -> bool:
	var travel := b - a
	var length_squared := travel.length_squared()
	if length_squared < 1e-9:
		return a.distance_squared_to(centre) <= radius * radius
	var t := clampf((centre - a).dot(travel) / length_squared, 0.0, 1.0)
	return (a + travel * t).distance_squared_to(centre) <= radius * radius

## Where to aim so a round of the given speed meets a target holding its current
## velocity. Solves the intercept quadratic; falls back to the target's present
## position whenever there is no positive solution, so an unreachable target
## yields a usable aim point rather than a NaN.
static func lead_point(shooter: Vector3, target: Vector3, target_velocity: Vector3,
		speed: float) -> Vector3:
	var offset := target - shooter
	var a := target_velocity.length_squared() - speed * speed
	var b := 2.0 * offset.dot(target_velocity)
	var c := offset.length_squared()
	if absf(a) < 1e-6:
		if absf(b) < 1e-6:
			return target
		return target + target_velocity * maxf(-c / b, 0.0)
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return target
	var root := sqrt(discriminant)
	var t1 := (-b + root) / (2.0 * a)
	var t2 := (-b - root) / (2.0 * a)
	var t := maxf(t1, t2) if minf(t1, t2) < 0.0 else minf(t1, t2)
	if t < 0.0:
		return target
	return target + target_velocity * t
