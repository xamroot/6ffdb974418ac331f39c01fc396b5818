extends Node2D

@onready var cam : Camera2D = $Camera2D

@onready var forces_label : Label = $"../CanvasLayer/Control/VSplitContainer/Label"
@onready var selected_label : Label = $"../CanvasLayer/Control/VSplitContainer/Label2"

var cities = []

var movement_locked = false

var velocity : Vector2 = Vector2.ZERO

var growth_amount = 0

var _forces = 1
var forces = 0
var selected = 0
var percentage = 0
var cooldown = 0.0

var min_acceleration = 2.0
var max_acceleration = 3.0
var acceleration = 0.0

var accel_counter = 0.0
var accel_timer = 0.4
var to_remove = 0

var default_zoom : Vector2

var owned_lands = {
	"grass":0,
	"mountainous":0,
	"peaks":0
}


func _ready()->void:
	default_zoom = cam.zoom

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.is_action_pressed("primary") and not movement_locked:
			var _evt : InputEventMouseMotion = event as InputEventMouseMotion
			# mouse movement, map camera travel
			if cam.zoom.x > default_zoom.x:
				if accel_counter >0.0:
					acceleration = min(acceleration+0.05, max_acceleration)
				velocity += _evt.screen_relative.normalized() * 10.0 * acceleration*(1/cam.zoom.x)
				accel_counter = accel_timer

func _physics_process(delta: float) -> void:
	
	if accel_counter > 0.0:
		accel_counter -= delta
	
	if to_remove > 0:
		_forces -= to_remove
		forces = int(_forces)
		to_remove = 0
	
	if growth_amount > 0:
		if cooldown <= 0.0:
			# growth and forces calculations
			var max_forces = 3000 + owned_lands["grass"] * 2 + owned_lands["mountainous"]
			print(max_forces)
			
			var _delta_forces = delta *( owned_lands["grass"] + owned_lands["mountainous"]*0.5)*(growth_amount/2)*(_forces/16)
			if _forces + _delta_forces <= max_forces:
				_forces += _delta_forces
			cooldown = 3.0
		else:
			cooldown -= 5*delta
	forces = int(_forces)
	var zoom_speed = 5.0
	if Input.is_action_pressed("zoom_in") or Input.is_action_just_released("zoom_in"):
		var _tmp_zoom = cam.zoom + delta*Vector2(zoom_speed,zoom_speed)
		if _tmp_zoom.x < zoom_speed and _tmp_zoom.y < zoom_speed:
			cam.zoom = _tmp_zoom
	if Input.is_action_pressed("zoom_out") or Input.is_action_just_released("zoom_out"):
		var _tmp_zoom = cam.zoom - delta*Vector2(zoom_speed,zoom_speed)
		if _tmp_zoom.x > default_zoom.x and _tmp_zoom.y > default_zoom.y:
			cam.zoom = _tmp_zoom
	
	global_position -= velocity*delta
	if accel_counter <= 0:
		velocity = lerp(velocity, Vector2.ZERO, delta*10.0)
		
	velocity = lerp(velocity, Vector2.ZERO, delta*2.0)
	
	forces_label.text = "Forces: " + str(forces)
	selected = int(forces*(percentage/100))
	selected_label.text = "Selected: (" + str(percentage)+"%) " + str(selected)


func _on_h_slider_value_changed(value: float) -> void:
	percentage = value 
	selected_label.text = "Selected: (" + str(percentage)+"%) " + str(forces*(percentage/100))


func _on_h_slider_drag_started() -> void:
	movement_locked = true
	pass # Replace with function body.


func _on_h_slider_drag_ended(value_changed: bool) -> void:
	movement_locked = false
	pass # Replace with function body.
