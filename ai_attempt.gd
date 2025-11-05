extends Control

const GROW_PIXELS_PER_SECOND := 50
const OWNED_COLOR := Color(1,0,0,0.5)
const WRAP_X := true

# --- terrain thresholds (tune to your map) ---
const WATER_R_MIN := 0.420  # water if col.r < this (your current rule was >0.419 pass-land)
const MOUNTAIN_B_MIN := 0.705  # example: high blue = mountain; change to your rule
const MOUNTAIN_COST := 6    # how many "budget units" a mountain pixel costs
const SLOW_COST_SHARE := 0.45   # 30% of per-frame cost goes to mountains (tune)

@onready var Map: TextureRect = $Map
@onready var user = $"../User"

var map_image: Image

var W:int
var H:int
var owner_img: Image
var owner_tex: ImageTexture
var owned: BitMap
var queued: BitMap

# ---- two ring-buffer queues (fast = normal, slow = mountain) ----
var fx := PackedInt32Array()
var fy := PackedInt32Array()
var f_head := 0
var f_tail := 0
var f_cap := 0

var sx := PackedInt32Array()
var sy := PackedInt32Array()
var s_head := 0
var s_tail := 0
var s_cap := 0

var sent_forces := 0
var spot_chosen := false
var first_spot_chosen := false

var owned_lands = {
	
}

func _ready() -> void:
	var base_tex := Map.texture
	W = base_tex.get_width()
	H = base_tex.get_height()

	owner_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	owner_tex = ImageTexture.create_from_image(owner_img)

	owned = BitMap.new();  owned.create(Vector2i(W, H))
	queued = BitMap.new(); queued.create(Vector2i(W, H))

	map_image = Map.texture.get_image()

	_q_init_fast(W * H / 8 + 1024)
	_q_init_slow(W * H / 8 + 1024)

	var overlay := TextureRect.new()
	overlay.stretch_mode = TextureRect.STRETCH_SCALE
	overlay.texture = owner_tex
	overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Map.add_sibling(overlay)

func _screen_to_map_uv(screen_pos: Vector2) -> Vector2:
	var r := Map.get_global_rect()
	if r.size.x <= 0.0 or r.size.y <= 0.0: return Vector2(-1, -1)
	return ((screen_pos - r.position) / r.size).clamp(Vector2.ZERO, Vector2.ONE)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_released() and event.button_index == MOUSE_BUTTON_LEFT:
		var uv := _screen_to_map_uv(event.position)
		if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0: return
		var px := Vector2i(
			clamp(int(round(uv.x * float(W - 1))), 0, W - 1),
			clamp(int(round(uv.y * float(H - 1))), 0, H - 1)
		)
		if map_image.get_pixelv(px).r > 0.419:
		
			if not spot_chosen:
					spot_chosen = true
					_seed_circle(px.x, px.y, 4)
			else:
				sent_forces += 20

func _process(delta: float) -> void:
	if spot_chosen and not first_spot_chosen:
		first_spot_chosen = true
		user.growth_amount = 5
		sent_forces = 1

	if sent_forces <= 0: return

	var cost_budget := int(GROW_PIXELS_PER_SECOND * delta * sent_forces)
	if cost_budget <= 0: return

	var batch_pts := PackedInt32Array()

	# 1) Split the cost budget
	var slow_budget := int(floor(float(cost_budget) * SLOW_COST_SHARE))
	var fast_budget := cost_budget - slow_budget

	# 2) Spend slow bucket first (guaranteed mountain progress)
	while slow_budget >= MOUNTAIN_COST and _slow_has():
		var x := sx[s_head]; var y := sy[s_head]
		s_head = (s_head + 1) % s_cap
		if _claim_if_allowed(x, y, batch_pts):
			_enqueue_neighbors(x, y)
			slow_budget -= MOUNTAIN_COST
		# if claim failed (water/already owned), no cost consumed; keep looping

	# 3) Spend fast bucket
	while fast_budget >= 1 and _fast_has():
		var x := fx[f_head]; var y := fy[f_head]
		f_head = (f_head + 1) % f_cap
		if _claim_if_allowed(x, y, batch_pts):
			_enqueue_neighbors(x, y)
			fast_budget -= 1
		# if claim failed, no cost consumed

	# 4) Reallocate any leftovers so we don’t waste the frame
	var leftovers := slow_budget + fast_budget
	# Prefer to burn leftovers on fast (cheap) first for snappier feel.
	while leftovers >= 1 and (_fast_has() or (_slow_has() and leftovers >= MOUNTAIN_COST)):
		if _fast_has():
			var x2 := fx[f_head]; var y2 := fy[f_head]
			f_head = (f_head + 1) % f_cap
			if _claim_if_allowed(x2, y2, batch_pts):
				_enqueue_neighbors(x2, y2)
				leftovers -= 1
			else:
				# no cost consumed
				pass
		elif _slow_has() and leftovers >= MOUNTAIN_COST:
			var xs := sx[s_head]; var ys := sy[s_head]
			s_head = (s_head + 1) % s_cap
			if _claim_if_allowed(xs, ys, batch_pts):
				_enqueue_neighbors(xs, ys)
				leftovers -= MOUNTAIN_COST
			else:
				# no cost consumed
				pass
		else:
			break

	# Apply batch
	if batch_pts.size() > 0:
		for i in batch_pts.size():
			var packed := batch_pts[i]
			var bx := packed & 0xFFFF
			var by := (packed >> 16) & 0xFFFF
			owner_img.set_pixel(bx, by, OWNED_COLOR)
		owner_tex.update(owner_img)

	sent_forces -= 10*delta


# -------- terrain logic --------
func is_water(col: Color) -> bool:
	# Your rule was "if col.r > 0.419 it's OK (land)"; invert for water:
	return col.r < WATER_R_MIN

func is_mountain(col: Color) -> bool:
	# Example rule: very bright/blue-ish pixels are mountains.
	# Replace with whatever matches your map (e.g., col.g < t, or col.h in HSV range)
	return col.b >= MOUNTAIN_B_MIN

# Attempt to claim this pixel if it’s valid terrain and not owned.
func _claim_if_allowed(x:int, y:int, batch_pts: PackedInt32Array) -> bool:
	var p := Vector2i(x, y)
	if owned.get_bitv(p):
		return false
	var col := map_image.get_pixelv(p)
	if is_water(col):
		return false

	# Claim
	owned.set_bitv(p, true)
	queued.set_bitv(p, false)
	batch_pts.push_back((y << 16) | x)
	return true

# Enqueue neighbors into fast/slow queues based on their terrain type
func _enqueue_neighbors(x:int, y:int) -> void:
	_enqueue_neighbor(x+1, y)
	_enqueue_neighbor(x-1, y)
	_enqueue_neighbor(x, y+1)
	_enqueue_neighbor(x, y-1)

func _enqueue_neighbor(nx:int, ny:int) -> void:
	if WRAP_X:
		if nx < 0: nx = W - 1
		elif nx >= W: nx = 0
	else:
		if nx < 0 or nx >= W: return
	if ny < 0 or ny >= H: return

	var p := Vector2i(nx, ny)
	if owned.get_bitv(p) or queued.get_bitv(p):
		return

	var col := map_image.get_pixelv(p)
	if is_water(col):
		return

	queued.set_bitv(p, true)
	if is_mountain(col):
		_slow_push(nx, ny)   # mountain: expensive queue
	else:
		_fast_push(nx, ny)   # normal: cheap queue

# -------- queues --------
func _q_init_fast(cap:int) -> void:
	f_cap = max(1024, cap)
	fx.resize(f_cap); fy.resize(f_cap)
	f_head = 0; f_tail = 0

func _q_init_slow(cap:int) -> void:
	s_cap = max(1024, cap)
	sx.resize(s_cap); sy.resize(s_cap)
	s_head = 0; s_tail = 0

func _fast_has() -> bool: return f_head != f_tail
func _slow_has() -> bool: return s_head != s_tail

func _fast_push(x:int, y:int) -> void:
	var next := (f_tail + 1) % f_cap
	if next == f_head: _grow_fast()
	fx[f_tail] = x; fy[f_tail] = y; f_tail = (f_tail + 1) % f_cap

func _slow_push(x:int, y:int) -> void:
	var next := (s_tail + 1) % s_cap
	if next == s_head: _grow_slow()
	sx[s_tail] = x; sy[s_tail] = y; s_tail = (s_tail + 1) % s_cap

func _grow_fast() -> void:
	var new_cap := f_cap * 2
	var nx := PackedInt32Array(); nx.resize(new_cap)
	var ny := PackedInt32Array(); ny.resize(new_cap)
	var i := 0
	while f_head != f_tail:
		nx[i] = fx[f_head]; ny[i] = fy[f_head]
		f_head = (f_head + 1) % f_cap; i += 1
	fx = nx; fy = ny; f_cap = new_cap; f_head = 0; f_tail = i

func _grow_slow() -> void:
	var new_cap := s_cap * 2
	var nx := PackedInt32Array(); nx.resize(new_cap)
	var ny := PackedInt32Array(); ny.resize(new_cap)
	var i := 0
	while s_head != s_tail:
		nx[i] = sx[s_head]; ny[i] = sy[s_head]
		s_head = (s_head + 1) % s_cap; i += 1
	sx = nx; sy = ny; s_cap = new_cap; s_head = 0; s_tail = i

# ------- seeding -------
func _seed_circle(cx:int, cy:int, r:int) -> void:
	var r2 := r * r
	for dy in range(-r, r+1):
		var yy := cy + dy
		if yy < 0 or yy >= H: continue
		for dx in range(-r, r+1):
			if dx*dx + dy*dy > r2: continue
			var xx := cx + dx
			if WRAP_X:
				if xx < 0: xx = W - 1
				elif xx >= W: xx = 0
			else:
				if xx < 0 or xx >= W: continue

			var p := Vector2i(xx, yy)
			if owned.get_bitv(p) or queued.get_bitv(p): continue

			var col := map_image.get_pixelv(p)
			if is_water(col): continue
			queued.set_bitv(p, true)
			if is_mountain(col):
				_slow_push(xx, yy)
			else:
				_fast_push(xx, yy)
