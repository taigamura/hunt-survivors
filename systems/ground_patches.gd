class_name GroundPatches
extends RefCounted
## Lingering damage zones (burning ground, afterimages). All patches hit together every `tick`.

var ppos := PackedVector2Array()
var prad := PackedFloat32Array()
var plife := PackedFloat32Array()
var pmax := PackedFloat32Array()
var pdmg := PackedFloat32Array()
var cap: int = 60
var tick: float = 0.3
var _tick_timer: float = 0.0
var hits_total: int = 0


func _init(p_cap: int = 60, p_tick: float = 0.3) -> void:
	cap = p_cap
	tick = p_tick


func size() -> int:
	return ppos.size()


func add(p: Vector2, r: float, life: float, damage: float) -> void:
	if ppos.size() >= cap:
		ppos.remove_at(0)
		prad.remove_at(0)
		plife.remove_at(0)
		pmax.remove_at(0)
		pdmg.remove_at(0)
	ppos.append(p)
	prad.append(r)
	plife.append(life)
	pmax.append(life)
	pdmg.append(damage)


func update(dt: float, hunt: HuntContext, flags: int = 0) -> void:
	var k := 0
	while k < ppos.size():
		plife[k] -= dt
		if plife[k] <= 0.0:
			ppos.remove_at(k)
			prad.remove_at(k)
			plife.remove_at(k)
			pmax.remove_at(k)
			pdmg.remove_at(k)
		else:
			k += 1
	_tick_timer -= dt
	if _tick_timer <= 0.0:
		_tick_timer = tick
		for j in ppos.size():
			hits_total += hunt.hit_circle(ppos[j], prad[j], pdmg[j], 0.0, flags | HuntContext.HIT_DOT)


func draw_flames(ci: CanvasItem) -> void:
	var base := ArtRegistry.color("fx.flame")
	for j in ppos.size():
		var fade := clampf(plife[j] / 0.4, 0.0, 1.0)
		var flick := 0.85 + 0.15 * sin(float(j) * 1.7 + plife[j] * 17.0)
		var c := base
		c.a *= fade
		ci.draw_circle(ppos[j], prad[j] * flick, c)
		ci.draw_circle(ppos[j], prad[j] * 0.5 * flick, Color(1.0, 0.85, 0.35, c.a * 0.8))


func draw_afterimages(ci: CanvasItem, radius: float) -> void:
	var base := ArtRegistry.color("fx.trail")
	for j in ppos.size():
		var t := plife[j] / pmax[j]
		var c := base
		c.a *= t
		ci.draw_circle(ppos[j], radius * (0.7 + 0.3 * t), c)
