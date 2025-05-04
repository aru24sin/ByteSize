extends CharacterBody3D

var sensitivity = 0.1
var direction = Vector3()
var wish_jump = false
var friction = 4

# Movement Constants
const BASE_MAX_VELOCITY_AIR = 2
const BASE_MAX_VELOCITY_GROUND = 8.0
const MAX_ACCELERATION = 20 * BASE_MAX_VELOCITY_GROUND
const GRAVITY = 19.34
const STOP_SPEED = 8
const JUMP_IMPULSE = sqrt(5 * GRAVITY * 0.85)

# Modifiers
const SPRINT_MULT = 1.5
const CROUCH_MULT = 0.5
const SLIDE_TIME = 0.6
const WALLRUN_MIN_SPEED = 1.0
const WALLRUN_CAMERA_TILT = 0.3

# State
var is_sprinting = false
var is_crouching = false
var is_sliding = false
var is_wallrunning = false
var just_wall_jumped = false

var slide_timer = 0.0
var wall_normal = Vector3.ZERO

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_handle_camera_rotation(event)

func _handle_camera_rotation(event: InputEvent):
	rotate_y(deg_to_rad(-event.relative.x * sensitivity))
	$Head.rotate_x(deg_to_rad(-event.relative.y * sensitivity))
	$Head.rotation.x = clamp($Head.rotation.x, deg_to_rad(-60), deg_to_rad(90))

func _physics_process(delta):
	process_input()
	process_movement(delta)
	update_camera_tilt(delta)

func process_input():
	direction = Vector3()

	if Input.is_action_pressed("forward"):
		direction -= transform.basis.z
	elif Input.is_action_pressed("backward"):
		direction += transform.basis.z
	if Input.is_action_pressed("left"):
		direction -= transform.basis.x
	elif Input.is_action_pressed("right"):
		direction += transform.basis.x

	wish_jump = Input.is_action_just_pressed("jump")
	is_sprinting = Input.is_action_pressed("sprint")
	is_crouching = Input.is_action_pressed("crouch")

func process_movement(delta):
	var wish_dir = direction.normalized()
	var speed_mult = 1.0

	if is_sprinting and is_on_floor() and !is_crouching:
		speed_mult = SPRINT_MULT
	elif is_crouching:
		speed_mult = CROUCH_MULT

	var target_head_height = 0.05 if is_crouching else 1.0
	$Head.position.y = lerp($Head.position.y, target_head_height, 10 * delta)

	if is_on_floor():
		is_wallrunning = false
		if wish_jump:
			velocity.y = JUMP_IMPULSE
			if is_sliding:
				var flat_dir = direction.normalized(); flat_dir.y = 0
				velocity += flat_dir * 6.0
			velocity = update_velocity_air(wish_dir, delta, speed_mult)
			wish_jump = false
		else:
			if is_crouching and velocity.length() > BASE_MAX_VELOCITY_GROUND * 0.5 and !is_sliding:
				is_sliding = true
				slide_timer = SLIDE_TIME
			if is_sliding:
				slide_timer -= delta
				if slide_timer <= 0 or !is_crouching:
					is_sliding = false
					speed_mult = CROUCH_MULT
				var slide_dir = wish_dir
				if slide_dir.length() > 0:
					velocity.x = slide_dir.x * BASE_MAX_VELOCITY_GROUND * 1.5
					velocity.z = slide_dir.z * BASE_MAX_VELOCITY_GROUND * 1.5
				else:
					# Decelerate when not pressing input during slide
					var flat_velocity = velocity
					flat_velocity.y = 0
					var decel = flat_velocity.normalized() * -10.0 * delta
					velocity.x += decel.x
					velocity.z += decel.z
					if flat_velocity.length() < 0.5:
						velocity.x = 0
						velocity.z = 0
			else:
				velocity = update_velocity_ground(wish_dir, delta, speed_mult)
	else:
		velocity.y -= GRAVITY * delta
		velocity = update_velocity_air(wish_dir, delta, speed_mult)
		handle_wall_interactions(wish_dir, delta)

	move_and_slide()

func accelerate(wish_dir: Vector3, max_velocity: float, delta):
	var current_speed = velocity.dot(wish_dir)
	var add_speed = clamp(max_velocity - current_speed, 0, MAX_ACCELERATION * delta)
	return velocity + add_speed * wish_dir

func update_velocity_ground(wish_dir: Vector3, delta, speed_mult: float):
	var speed = velocity.length()
	if speed != 0:
		var control = max(STOP_SPEED, speed)
		var drop = control * friction * delta
		velocity *= max(speed - drop, 0) / speed
	return accelerate(wish_dir, BASE_MAX_VELOCITY_GROUND * speed_mult, delta)

func update_velocity_air(wish_dir: Vector3, delta, speed_mult: float):
	return accelerate(wish_dir, BASE_MAX_VELOCITY_AIR * speed_mult, delta)

func handle_wall_interactions(wish_dir: Vector3, delta):
	if just_wall_jumped:
		just_wall_jumped = false
		is_wallrunning = false
		return

	var space_state = get_world_3d().direct_space_state
	var from_pos = global_position
	var directions = [
		transform.basis.x,
		-transform.basis.x,
		transform.basis.z,
		-transform.basis.z
	]

	is_wallrunning = false
	for dir in directions:
		var ray_params = PhysicsRayQueryParameters3D.create(from_pos, from_pos + dir.normalized() * 1.2)
		ray_params.exclude = [self]
		var result = space_state.intersect_ray(ray_params)

		if result and not is_on_floor():
			wall_normal = result.normal
			var wall_dir = -wall_normal.cross(Vector3.UP).normalized()

			is_wallrunning = true

			var wall_velocity = wall_dir * velocity.dot(wall_dir)
			velocity.x = wall_velocity.x
			velocity.z = wall_velocity.z
			velocity.y = 0.0

			if wish_jump:
				var forward = -transform.basis.z
				var jump_dir = (forward * 2.5 + wall_normal).normalized()
				var jump_speed = max(velocity.length(), BASE_MAX_VELOCITY_GROUND * 1.8)
				velocity = jump_dir * jump_speed
				velocity.y = JUMP_IMPULSE * 0.6
				just_wall_jumped = true
			break

	if not is_wallrunning:
		wall_normal = Vector3.ZERO

func update_camera_tilt(delta):
	var target_tilt = 0.0
	if is_wallrunning:
		target_tilt = -wall_normal.dot(transform.basis.x) * WALLRUN_CAMERA_TILT
	$Head.rotation.z = lerp($Head.rotation.z, target_tilt, 5 * delta)
