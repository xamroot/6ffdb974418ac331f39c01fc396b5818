extends Node2D

@onready var ownership_map : TextureRect = $"../Control/Map"

var shader_material

var spot_chosen : bool = false

var velocity : Vector2 = Vector2.ZERO

func _screen_to_map_uv(screen_pos: Vector2) -> Vector2:
	# Works for TextureRect with STRETCH_SCALE (default). If you change layout, adjust this.
	# Map.get_global_rect() gives the drawn rect; convert to normalized UV inside that rect.
	var r := ownership_map.get_global_rect()
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return Vector2(-1, -1)
	var p := (screen_pos - r.position) / r.size
	return p.clamp(Vector2.ZERO, Vector2.ONE)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mat : ShaderMaterial = ownership_map.material as ShaderMaterial
		shader_material = mat
		var _ev = event as InputEventMouseButton
		if not spot_chosen:
			shader_material.get_shader_parameter("point_count")
			var poly = shader_material.get_shader_parameter("poly")
			
			var target = _screen_to_map_uv(_ev.global_position)
			poly[0] = Vector2(target.x,target.y)
			shader_material.set_shader_parameter("point_count", 1)
			shader_material.set_shader_parameter("poly", poly)
			print(poly)

func _physics_process(delta: float) -> void:
	pass

func _process(delta:float)->void:
	pass
