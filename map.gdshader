shader_type canvas_item;

/* ---------- thresholds & debug ---------- */
uniform float t_water    : hint_range(0.0,1.0) = 0.01;
uniform float t_shore    : hint_range(0.0,1.0) = 0.30;
uniform float t_mountain : hint_range(0.0,1.0) = 0.90;

/* 0=original, 1=class colors, 2=elevation grayscale */
uniform int debug_view = 1;

/* optional screen-space “parallax” (in pixels), done in fragment() */
uniform float disp_pixels = 0.0;

/* class colors for debug_view=1 */
uniform vec4 col_water     : source_color = vec4(0.06, 0.21, 0.54, 1.0);
uniform vec4 col_shore     : source_color = vec4(0.37, 0.61, 0.80, 1.0);
uniform vec4 col_land      : source_color = vec4(0.25, 0.63, 0.17, 1.0);
uniform vec4 col_mountain  : source_color = vec4(0.71, 0.24, 0.16, 1.0);

/* ---------- helpers ---------- */
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1e-10;
    float h = abs(q.z + (q.w - q.y) / (6.0 * d + e));
    float s = d / (q.x + e);
    float v = q.x;
    return vec3(h, s, v);
}

/* hue→elevation mapping (tuned for rainbow relief maps) */
float hue_to_elev_index(float hue01, float sat, float val) {
    float hdeg = hue01 * 360.0;
    float e = 0.0;
    if (hdeg <= 200.0 && hdeg > 180.0) {
        e = (1.0 - (hdeg - 180.0) / 20.0) * 0.10;
    } else if (hdeg <= 180.0 && hdeg > 120.0) {
        e = 0.10 + ((180.0 - hdeg) / 60.0) * (0.45 - 0.10);
    } else if (hdeg <= 120.0 && hdeg > 60.0) {
        e = 0.45 + ((120.0 - hdeg) / 60.0) * (0.75 - 0.45);
    } else if (hdeg <= 60.0) {
        e = 0.75 + ((60.0 - hdeg) / 60.0) * (1.00 - 0.75);
    } else {
        e = 0.0; // clamp violets (>200°) to low
    }
    e *= (0.8 + 0.2 * sat); // slight saturation modulation
    return clamp(e, 0.0, 1.0);
}

int elev_to_class(float ei) {
    if (ei < t_water)    return 0;
    if (ei < t_shore)    return 1;
    if (ei < t_mountain) return 2;
    return 3;
}

/* ---------- no vertex() texture sampling! ---------- */

void fragment() {
    // Optional small screen-space offset based on elevation.
    // We must pre-sample to estimate ei, convert pixels→UV with TEXTURE_PIXEL_SIZE.
    vec2 duv = vec2(0.0);
    if (disp_pixels != 0.0) {
        vec4 pre = texture(TEXTURE, UV);
        vec3 hsv0 = rgb2hsv(pre.rgb);
        float ei0 = hue_to_elev_index(hsv0.x, hsv0.y, hsv0.z);
        duv = -ei0 * disp_pixels * TEXTURE_PIXEL_SIZE.xy;
    }

    vec4 col = texture(TEXTURE, UV + duv);
    vec3 hsv = rgb2hsv(col.rgb);
    float ei = hue_to_elev_index(hsv.x, hsv.y, hsv.z);
    int klass = elev_to_class(ei);

    if (debug_view == 0) {
        COLOR = col;
    } else if (debug_view == 1) {
        COLOR = (klass == 0) ? col_water
              : (klass == 1) ? col_shore
              : (klass == 2) ? col_land
              :                col_mountain;
    } else { // 2
        COLOR = vec4(vec3(ei), 1.0);
    }
}
