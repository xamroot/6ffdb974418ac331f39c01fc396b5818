shader_type canvas_item;

/* ---- polygon ---- */
uniform int point_count = 0;                          // how many points in `poly`
uniform vec2 poly[128];                               // polygon points in UV space [0..1], in order

/* ---- colors & edge ---- */
uniform vec4 fill_color : source_color = vec4(0.12,0.70,0.95,1.0);
uniform vec4 outside_color : source_color = vec4(0.0,0.0,0.0,0.0); // transparent outside
uniform float edge_softness_px : hint_range(0.0, 4.0) = 1.0;       // AA width in pixels

/* ---- choose coord space ----
   0 = use UV (typical for textured rects/sprites),
   1 = use SCREEN_UV (full-screen effects).
*/
uniform float range = 0.925;
uniform int coord_space = 0;

/* ----------------- helpers ----------------- */

float seg_dist_sq(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
    vec2 q = a + t * ab;
    vec2 d = p - q;
    return dot(d, d);
}

// Even-odd (ray-cast) test
bool point_in_poly(vec2 p) {
    bool c = false;
    for (int i = 0; i < point_count; i++) {
        vec2 a = poly[i];
        vec2 b = poly[(i + 1) % point_count];
        // edge crosses horizontal ray?
        bool cond = ((a.y > p.y) != (b.y > p.y)) &&
                    (p.x < (b.x - a.x) * (p.y - a.y) / max((b.y - a.y), 1e-6) + a.x);
        if (cond) c = !c;
    }
    return c;
}

// Minimum distance from p to polygon edges (in UV units)
float min_edge_dist(vec2 p) {
    float md2 = 1e9;
    for (int i = 0; i < point_count; i++) {
        vec2 a = poly[i];
        vec2 b = poly[(i + 1) % point_count];
        md2 = min(md2, seg_dist_sq(p, a, b));
    }
    return sqrt(md2);
}

void fragment() {
    // pick coordinate space
    vec2 p = UV;
	
	bool done_flag = false;
	
	for (int i = 0; i < point_count; i++) {
        vec2 a = poly[i];
		if (p.x < a.x + range && p.x > a.x - range)
		{
			if (p.y < a.y + range && p.y > a.y - range)
			{
				COLOR = fill_color;
				done_flag = true;
				break;
			}
		}
    }
	
	if (!done_flag)
	{
		discard;
	}
}
