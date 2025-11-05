extends Node2D

@onready var cam : Camera2D = $Camera2D

@onready var forces_label : Label = $"../CanvasLayer/Control/VSplitContainer/Label"
@onready var selected_label : Label = $"../CanvasLayer/Control/VSplitContainer/Label2"

var movement_locked = false

var velocity : Vector2 = Vector2.ZERO

var growth_amount = 0

var _forces = 1
var forces = 0
var selected = 0
var percentage = 0
var cooldown = 0.0

var default_zoom : Vector2

func _ready()->void:
	default_zoom = cam.zoom

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.is_action_pressed("primary") and not movement_locked:
			var _evt : InputEventMouseMotion = event as InputEventMouseMotion
			if cam.zoom.x > default_zoom.x:
				velocity += _evt.velocity.normalized() * 10.0

func _physics_process(delta: float) -> void:
	
	if growth_amount > 0:
		if cooldown <= 0.0:
			_forces = _forces + (growth_amount * delta*(_forces))
			cooldown = 3.0
		else:
			cooldown -= 5*delta
	forces = int(_forces)
	
	if Input.is_action_pressed("zoom_in"):
		var _tmp_zoom = cam.zoom + delta*Vector2(3.0,3.0)
		if _tmp_zoom.x < 4.0 and _tmp_zoom.y < 4.0:
			cam.zoom = _tmp_zoom
		else:
			global_position = Vector2.ZERO
	if Input.is_action_pressed("zoom_out"):
		var _tmp_zoom = cam.zoom - delta*Vector2(3.0,3.0)
		if _tmp_zoom.x > default_zoom.x and _tmp_zoom.y > default_zoom.y:
			cam.zoom = _tmp_zoom
	
	global_position -= velocity*delta
	velocity = lerp(velocity, Vector2.ZERO, delta*2.0)
	
	forces_label.text = "Forces: " + str(forces)
	selected_label.text = "Selected: (" + str(percentage)+"%) " + str(forces*(percentage/100))


func _on_h_slider_value_changed(value: float) -> void:
	percentage = value 
	selected_label.text = "Selected: (" + str(percentage)+"%) " + str(forces*(percentage/100))


func _on_h_slider_drag_started() -> void:
	movement_locked = true
	pass # Replace with function body.


func _on_h_slider_drag_ended(value_changed: bool) -> void:
	movement_locked = false
	pass # Replace with function body.
