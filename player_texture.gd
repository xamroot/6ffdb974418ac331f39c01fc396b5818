extends Control
# Attach to a Control that has a child TextureRect called "Map" with your map texture.

# ----- Tunables -----
const START_RADIUS_PX := 4          # size of the initial owned blob
const CLICK_PAINT_RADIUS_PX := 6    # left-click paint size
const OWNER_FORMAT := Image.FORMAT_RF  # 1 channel float
const GROW_PIXELS_PER_SECOND := 200  # how many new pixels per second to absorb
const WRAP_X := true                # keep your horizontal wrap behavior
const OWNED_COLOR := Color(1.0, 0, 0)

# Nodes
@onready var Map: TextureRect = $Map

var Overlay: TextureRect

# Owner data
var W:int
var H:int
var owner_img: Image
var owner_tex: ImageTexture

# Boolean masks
var owned: BitMap              # true = already owned
var queued: BitMap             # true = already in frontier queue
var owned_pixels = []

var img = null
var map_shader : ShaderMaterial

# Growth control
var growth_counter: float = 0.0

# RNG
var rng := RandomNumberGenerator.new()

# Cached to avoid realloc in hot paths
const NEIGHBORS := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
const NEIGHBORS_DIAG := [Vector2i(1,1), Vector2i(-1,-1)] # if you want diagonals like your sample
var C_OWNED := OWNED_COLOR

var spot_chosen := false

@onready var debug = $TextureRect

# --- neighbors: use either 4-way OR full 8-way, but never a lopsided subset
const N4 := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
const N8 := [
	Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
	Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)
]
var USE_DIAGONALS := true  # toggle if you want rounder growth

var frontier := PackedInt32Array()
var frontier_head := 0  # index of next item to read

var frontier_data = []
var center = Vector2(0,0)
func _frontier_push(idx:int) -> void:
	frontier.push_back(idx)

func _frontier_pop() -> int:
	var idx := frontier[frontier_head]
	frontier_head += 1
	# compact occasionally to avoid unbounded growth of the array
	if frontier_head > 8192 and frontier_head > frontier.size() / 2:
		frontier = frontier.slice(frontier_head, frontier.size() - frontier_head)
		frontier_head = 0
	return idx

var DIRECTIONS = [ Vector2(0,1), Vector2(1,0), Vector2(0,-1), Vector2(-1,0), Vector2(1,1), Vector2(-1,-1),Vector2(-1,1), Vector2(1,-1)  ]

func _frontier_empty() -> bool:
	return frontier_head >= frontier.size()

func _enqueue_neighbors(p: Vector2i) -> void:
	var neigh := N4
	if USE_DIAGONALS:
		neigh = N8
	# optional shuffle to remove any directional bias even more:
	# neigh.shuffle()
	for d in neigh:
		_enqueue_if_new(p + d)


# --- safer integer index <-> xy
func _xy(idx:int) -> Vector2i:
	# use integer division; in Godot 4 the operator is `//`
	return Vector2i(idx % W, int(idx) / int(W))

var poly : Polygon2D
var points := PackedVector2Array()


func _ready() -> void:
	# In a Node2D scene:
	poly = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(20, 20), Vector2(200, 40), Vector2(240, 160), Vector2(80, 180)
	])
	poly.z_index = 100
	poly.color = Color(1, 0, 0, 0.7)  # semi-transparent fill
	# Optional: poly.texture = some_texture; poly.uv = matching UVs
	add_child(poly)
	
	
	
	assert(Map and Map.texture, "Place a TextureRect named 'Map' with a texture")
	rng.randomize()
	_create_overlay()
	_create_owner_mask()

	# Random starting seed
	var start_px := Vector2i(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1))
	_paint_owned_disc_px(start_px, START_RADIUS_PX)
	_seed_frontier_from_owned_disc(start_px, START_RADIUS_PX)
	
	img = Map.texture.get_image()
	map_shader = Map.material as ShaderMaterial

	# Hook owner_tex to shader param
	var smat := Overlay.material as ShaderMaterial
	smat.set_shader_parameter("owner_tex", owner_tex)

	Overlay.z_index = Map.z_index + 1

func make_circle_points(center: Vector2, radius: float, segments := 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var angle = TAU * float(i) / segments  # TAU = 2 * PI
		var x = center.x + radius * cos(angle)
		var y = center.y + radius * sin(angle)
		pts.append(Vector2(x, y))
	return pts

func _process(delta: float) -> void:
	if growth_counter <= 0.0 or frontier.is_empty():
		return
	var to_process := int(GROW_PIXELS_PER_SECOND * delta)
	var processed := 0
	
	var next_frontier_data = []
	
	# Simple LIFO for speed; FIFO is fine too—order is not visually critical
	if growth_counter > 0.0:
		while processed < to_process and not frontier_data.is_empty():
			#if processed < to_process and not frontier.is_empty() and not frontier_data.is_empty():
			#var idx := _frontier_pop()
			#frontier.resize(frontier.size() - 1)
			#var xy := _xy(idx)
			var xy = frontier_data.pop_front()
			print(xy)
			debug.global_position = xy			
			if not owned.get_bitv(xy):
				if img.get_pixelv(xy)[0] > 0.419:
					print(img.get_pixelv(xy))
					owned.set_bitv(xy, true)
					owner_img.set_pixel(xy.x, xy.y, C_OWNED)
					# Enqueue its neighbors
					#_enqueue_neighbors(xy)
					for dir in DIRECTIONS:
						var next_frontier = dir + xy
						if not owned.get_bitv(next_frontier):
							next_frontier_data.append(next_frontier)
					
					#processed += 1
					processed+=1
	
	frontier_data.append_array(next_frontier_data)

	# One GPU upload per frame
	owner_tex.update(owner_img)

	# Countdown growth
	growth_counter = maxf(0.0, growth_counter - delta)

# ----------------- Core helpers -----------------

func _create_overlay() -> void:
	Overlay = TextureRect.new()
	Overlay.name = "Overlay"
	Overlay.stretch_mode = TextureRect.STRETCH_SCALE
	Overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL

	Overlay.anchor_left = Map.anchor_left
	Overlay.anchor_top = Map.anchor_top
	Overlay.anchor_right = Map.anchor_right
	Overlay.anchor_bottom = Map.anchor_bottom
	Overlay.offset_left = Map.offset_left
	Overlay.offset_top = Map.offset_top
	Overlay.offset_right = Map.offset_right
	Overlay.offset_bottom = Map.offset_bottom

	Overlay.texture = Map.texture

	var shader_code := """
shader_type canvas_item;
uniform sampler2D owner_tex;
uniform float owner_threshold = 0.5;
uniform vec4 owner_color : source_color = vec4(0.95, 0.80, 0.20, 0.85);
uniform bool premultiply = false;

void fragment() {
    float owned = texture(owner_tex, UV).r;
    if (owned > owner_threshold) {
        COLOR = owner_color;
        if (premultiply) { COLOR.rgb *= COLOR.a; }
    } else {
        discard;
    }
}
"""
	var sh := Shader.new()
	sh.code = shader_code
	var sm := ShaderMaterial.new()
	sm.shader = sh
	Overlay.material = sm

	add_child(Overlay)

func _create_owner_mask() -> void:
	var map_tex := Map.texture
	assert(map_tex, "Map needs a texture")
	W = map_tex.get_width()
	print(W)
	H = map_tex.get_height()
	print(H)
	owner_img = Image.create(W, H, false, OWNER_FORMAT)
	owner_img.fill(Color(0,0,0,1))
	owner_tex = ImageTexture.create_from_image(owner_img)

	owned = BitMap.new()
	owned.create(Vector2(W, H))
	#owned.
	#owned.clear()

	queued = BitMap.new()
	queued.create(Vector2(W, H))
	#queued.clear()

func _idx(x:int, y:int) -> int:
	return x + y * W

func _wrap_x(x:int) -> int:
	if WRAP_X:
		var nx := x % W
		if nx < 0: nx += W
		return nx
	return x

func _in_bounds(x:int, y:int) -> bool:
	return y >= 0 and y < H and x >= 0 and x < W

func _enqueue_if_new(p: Vector2i) -> void:
	var x := _wrap_x(p.x)
	if not _in_bounds(x, p.y):
		return
	var v := Vector2i(x, p.y)
	if owned.get_bitv(v) or queued.get_bitv(v):
		return
	queued.set_bitv(v, true)
	_frontier_push(_idx(v.x, v.y))


# ----------------- Seeding / painting -----------------

func _paint_owned_disc_px(center_px: Vector2i, radius_px:int) -> void:
	var x0 := center_px.x
	var y0 := center_px.y
	var rr := float(radius_px) * float(radius_px)

	var y_min := maxi(0, y0 - radius_px)
	var y_max := mini(H - 1, y0 + radius_px)

	for y in range(y_min, y_max + 1):
		var dy := float(y - y0)
		var dx_max := int(floor(sqrt(max(0.0, rr - dy * dy))))
		for dx in range(-dx_max, dx_max + 1):
			var x := _wrap_x(x0 + dx)
			if not _in_bounds(x, y):
				continue
			var v := Vector2i(x, y)
			if owned.get_bitv(v):
				continue
			owned.set_bitv(v, true)
			owner_img.set_pixel(x, y, C_OWNED)
			frontier_data.append(Vector2(x+1,y+1))
			frontier_data.append(Vector2(x-1,y-1))
			frontier_data.append(Vector2(x,y+1))
			frontier_data.append(Vector2(x,y-1))
			frontier_data.append(Vector2(x+1,y))
			frontier_data.append(Vector2(x-1,y))
	owner_tex.update(owner_img)

func _seed_frontier_from_owned_disc(center_px: Vector2i, radius_px:int) -> void:
	# Add just the ring around the disc to the queue so growth starts at the border.
	var x0 := center_px.x
	var y0 := center_px.y
	var rr := float(radius_px + 1) * float(radius_px + 1)

	var y_min := maxi(0, y0 - (radius_px + 1))
	var y_max := mini(H - 1, y0 + (radius_px + 1))

	for y in range(y_min, y_max + 1):
		var dy := float(y - y0)
		var dx_max := int(floor(sqrt(max(0.0, rr - dy * dy))))
		for dx in range(-dx_max, dx_max + 1):
			var x := _wrap_x(x0 + dx)
			if not _in_bounds(x, y):
				continue
			var v := Vector2i(x, y)
			if not owned.get_bitv(v): # only queue border pixels
				_enqueue_if_new(v)

# --------------- Input to kick off growth ---------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var uv := _screen_to_map_uv(event.position)
		if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
			return
		var px := Vector2i(
			clamp(int(round(uv.x * float(W - 1))), 0, W - 1),
			clamp(int(round(uv.y * float(H - 1))), 0, H - 1)
		)
		if not spot_chosen:
			
			points = make_circle_points(px, 16.0, 128)
			center = Vector2(px.x, px.y)
			_paint_owned_disc_px(px, CLICK_PAINT_RADIUS_PX)
			_seed_frontier_from_owned_disc(px, CLICK_PAINT_RADIUS_PX)
			spot_chosen = true
		else:
			if growth_counter <= 0.0:
				growth_counter = 2.0  # grow for ~1s; click again to add more time

func _screen_to_map_uv(screen_pos: Vector2) -> Vector2:
	var r := Map.get_global_rect()
	print("HIT")
	print(r)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return Vector2(-1, -1)
	return ((screen_pos - r.position) / r.size).clamp(Vector2.ZERO, Vector2.ONE)
