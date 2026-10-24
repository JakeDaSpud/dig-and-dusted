class_name Player
extends CharacterBody3D

@export var move_speed := 5.0
@export var turn_sens := 2.0 # radians per second at turn = 1.0
@export var action_is_toggle := true # false: hold action to move. true: press action to switch move on/off.
@export var digital_steps := true # true: each key press adds a step. false: analog axis.
@export var step_size := 0.2 # change in turn per key press
@export var opposite_cancels := true # true: opposite press sets turn to 0.0

@export var rumble_weak := 0.0 # high-frequency motor (0.0 to 1.0)
@export var rumble_strong := 0.6 # low-frequency motor (0.0 to 1.0)
@export var rumble_time := 0.15 # seconds
@export var rumble_interval := 0.5
var rumble_timer := 0.0

@export var use_gyro_yaw := false
@export var gyro_sens := 3.0
@export var gyro_deadzone := 0.05 # ignores small drift
@export var gyro_invert := false
@export var calibration_time := 2.0 # seconds. Keep the controller still on a flat surface.

var gyro_device := -1
var gyro_ready := false

@export var gyro_tilt_mode := true
@export var tilt_deadzone_deg := 5.0
@export var tilt_max_deg := 45.0   

@onready var interact_area: Area3D = $InteractArea
var turn := 0.0 # -1.0 (full left) to 1.0 (full right)
var moving := false
var action_eaten := false # true: this hold was used to interact, cannot move


func _ready() -> void:
	interact_area.body_entered.connect(_on_overlap_entered)
	interact_area.area_entered.connect(_on_overlap_entered)
	
	if use_gyro_yaw:
		_setup_gyro()


func _physics_process(delta: float) -> void:
	_update_action()
	_update_turn()
	_update_rumble(delta)

	if use_gyro_yaw:
		if gyro_tilt_mode:
			rotate_y(-_get_gyro_yaw() * turn_sens * delta)
		else:
			rotate_y(_get_gyro_yaw() * gyro_sens * delta)
	else:
		rotate_y(-turn * turn_sens * delta)

	var speed := move_speed if moving else 0.0
	velocity = -transform.basis.z * speed
	move_and_slide()


func _setup_gyro() -> void:
	for device in Input.get_connected_joypads():
		if Input.has_joy_motion_sensors(device):
			gyro_device = device
			break

	if gyro_device == -1:
		push_warning("No controller with motion sensors found.")
		return

	Input.set_joy_motion_sensors_enabled(gyro_device, true)
	Input.start_joy_motion_sensors_calibration(gyro_device)
	await get_tree().create_timer(calibration_time).timeout
	Input.stop_joy_motion_sensors_calibration(gyro_device)
	gyro_ready = true


func _get_gyro_yaw() -> float:
	if not gyro_ready:
		return 0.0
	if gyro_tilt_mode:
		return _get_tilt_turn()

	var yaw := Input.get_joy_gyroscope(gyro_device).y
	if absf(yaw) < gyro_deadzone:
		return 0.0
	return -yaw if gyro_invert else yaw


func _get_tilt_turn() -> float:
	var g := Input.get_joy_gravity(gyro_device)
	var tilt := rad_to_deg(atan2(g.x, sqrt(g.y * g.y + g.z * g.z)))

	if absf(tilt) < tilt_deadzone_deg:
		return 0.0

	# remove deadzone, then scale to (-1.0 to 1.0)
	var t := (absf(tilt) - tilt_deadzone_deg) / (tilt_max_deg - tilt_deadzone_deg)
	var value := clampf(t, 0.0, 1.0) * signf(tilt)
	return -value if gyro_invert else value


func _on_overlap_entered(other: Node3D) -> void:
	if other is Interactable:
		_rumble()


func _update_rumble(delta: float) -> void:
	if _get_interactable():
		rumble_timer -= delta
		if rumble_timer <= 0.0:
			_rumble()
			rumble_timer = rumble_interval
	else:
		rumble_timer = 0.0 # reset, so the next entry rumbles immediately


func _rumble() -> void:
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, rumble_weak, rumble_strong, rumble_time)


func _update_turn() -> void:
	if not digital_steps:
		turn = Input.get_axis("turn_left", "turn_right")
		return

	if Input.is_action_just_pressed("turn_left"):
		_step(-1)
	if Input.is_action_just_pressed("turn_right"):
		_step(1)


func _get_interactable() -> Interactable:
	var overlapping := interact_area.get_overlapping_bodies() + interact_area.get_overlapping_areas()
	for n: Node3D in overlapping:
		print("checking overlap ", n)
		if n is Interactable:
			print("it found: ", n)
			return n
	return null


func _update_action() -> void:
	if Input.is_action_just_pressed("action"):
		var target := _get_interactable()
		if target:
			target.interact(self)
			action_eaten = true
			return

	if action_is_toggle:
		if Input.is_action_just_pressed("action"):
			moving = not moving
	else:
		if not Input.is_action_pressed("action"):
			action_eaten = false
		moving = Input.is_action_pressed("action") and not action_eaten


func _step(dir: int) -> void:
	if opposite_cancels and turn != 0.0 and signf(turn) != dir:
		turn = 0.0 # L, L, R = 0.0
	else:
		turn = clampf(turn + dir * step_size, -1.0, 1.0) # L, L, R = -0.2
	turn = snappedf(turn, 0.01)
