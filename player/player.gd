class_name Player
extends Node2D
## The hunter. Movement only — all attacks come from weapons reading movement state.

var radius: float = 15.0
var base_speed: float = 215.0
var base_max_hp: float = 120.0
var max_hp: float = 120.0
var hp: float = 120.0
var iframe_time: float = 0.45
var pickup_radius: float = 26.0
var magnet_radius: float = 120.0
var slow_mult: float = 0.5

# passive multipliers (set by UpgradePool)
var dmg_mult: float = 1.0
var area_mult: float = 1.0
var haste_mult: float = 1.0  ## >1 = faster attacks (divide cooldowns)
var speed_mult: float = 1.0
var magnet_mult: float = 1.0
var musou_mult: float = 1.0
var regen: float = 0.0
var bonus_hp: float = 0.0

## extra multiplier set by the main weapon each frame (Dual Blades momentum)
var weapon_speed_mult: float = 1.0

var move_input: Vector2 = Vector2.ZERO  ## post-curve, magnitude 0..1
var move_dir: Vector2 = Vector2.RIGHT     ## last non-zero direction
var facing: Vector2 = Vector2.RIGHT
var velocity: Vector2 = Vector2.ZERO
var iframes: float = 0.0
var invuln: bool = false
var slow_timer: float = 0.0
var hurt_flash: float = 0.0

var dash_timer: float = 0.0
var dash_vel: Vector2 = Vector2.ZERO

var weapons: Array[Weapon] = []
var sprite: Sprite2D
var map_rect: Rect2 = Rect2(-3000, -3000, 6000, 6000)
var rocks: Array[Vector3] = []  ## (x, y, radius)


func setup() -> void:
	radius = Tuning.f("player.radius", 15.0)
	base_speed = Tuning.f("player.speed", 215.0)
	base_max_hp = Tuning.f("player.max_hp", 120.0)
	iframe_time = Tuning.f("player.iframes", 0.45)
	pickup_radius = Tuning.f("player.pickup_radius", 26.0)
	magnet_radius = Tuning.f("player.magnet_radius", 120.0)
	slow_mult = Tuning.f("player.roar_slow_mult", 0.5)
	max_hp = base_max_hp
	hp = max_hp
	if sprite == null:
		sprite = Sprite2D.new()
		add_child(sprite)
	ArtRegistry.apply_to_sprite(sprite, "player.body")


func is_moving() -> bool:
	return move_input.length_squared() > 0.0001


func current_speed() -> float:
	var s := base_speed * speed_mult * weapon_speed_mult
	if slow_timer > 0.0:
		s *= slow_mult
	return s


func recompute_max_hp() -> void:
	var old := max_hp
	max_hp = base_max_hp + bonus_hp
	hp += max_hp - old


func start_dash(dir: Vector2, distance: float, duration: float) -> void:
	dash_timer = duration
	dash_vel = dir.normalized() * (distance / maxf(duration, 0.01))


func is_dashing() -> bool:
	return dash_timer > 0.0


## Integrates movement and resolves collisions with rocks and the map edge.
func move_step(dt: float, input: Vector2) -> void:
	move_input = input
	if input.length_squared() > 0.0001:
		move_dir = input.normalized()
		facing = move_dir
	if dash_timer > 0.0:
		dash_timer -= dt
		velocity = dash_vel
	else:
		velocity = input * current_speed()
	var p := position + velocity * dt
	for rk in rocks:
		var c := Vector2(rk.x, rk.y)
		var rr := rk.z + radius
		var d := p - c
		var l2 := d.length_squared()
		if l2 < rr * rr:
			var l := sqrt(l2)
			p = c + (d / l if l > 0.001 else Vector2.RIGHT) * rr
	p.x = clampf(p.x, map_rect.position.x + radius, map_rect.end.x - radius)
	p.y = clampf(p.y, map_rect.position.y + radius, map_rect.end.y - radius)
	position = p
	if sprite != null:
		sprite.rotation = facing.angle()
	if iframes > 0.0:
		iframes -= dt
	if slow_timer > 0.0:
		slow_timer -= dt
	if hurt_flash > 0.0:
		hurt_flash -= dt
	if regen > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + regen * dt)
	if sprite != null:
		if hurt_flash > 0.0:
			sprite.modulate = Color(1.0, 0.35, 0.35)
		elif invuln or dash_timer > 0.0:
			sprite.modulate = Color(1.6, 1.6, 1.6)
		else:
			sprite.modulate = ArtRegistry.tint("player.body")
	queue_redraw()


## Returns true if damage was applied.
func take_damage(amount: float) -> bool:
	if invuln or iframes > 0.0 or dash_timer > 0.0 or amount <= 0.0:
		return false
	hp -= amount
	iframes = iframe_time
	hurt_flash = 0.2
	return true


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


func _draw() -> void:
	# weapon indicators (charge / momentum rings, orbiting shards)
	for w in weapons:
		w.draw_local(self)
	# HP bar under the hunter
	var bw := 44.0
	var y := radius + 12.0
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-bw * 0.5 - 2, y - 2, bw + 4, 9), Color(0, 0, 0, 0.7))
	var col := ArtRegistry.color("ui.hp") if frac > 0.3 else ArtRegistry.color("ui.danger")
	draw_rect(Rect2(-bw * 0.5, y, bw * frac, 5), col)
