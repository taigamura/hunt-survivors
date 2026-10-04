class_name Geom
extends RefCounted
## Small overlap helpers shared by the monster, outposts and tests.


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func circle_circle(c1: Vector2, r1: float, c2: Vector2, r2: float) -> bool:
	return c1.distance_squared_to(c2) <= (r1 + r2) * (r1 + r2)


## Pie slice (center c, radius r, facing unit dir, half-angle) vs circle (pc, pr).
static func arc_circle(c: Vector2, r: float, dir: Vector2, half: float, pc: Vector2, pr: float) -> bool:
	var d := pc - c
	var dl := d.length()
	if dl > r + pr:
		return false
	if dl <= pr or half >= PI:
		return true
	var ang := absf(dir.angle_to(d))
	return ang <= half + asin(clampf(pr / dl, 0.0, 1.0))


## Capsule (segment a-b, half-width w) vs circle.
static func capsule_circle(a: Vector2, b: Vector2, w: float, pc: Vector2, pr: float) -> bool:
	return seg_dist(pc, a, b) <= w + pr
