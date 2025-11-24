shader_type canvas_item;

uniform float tolerance : hint_range(0.0, 1.0) = 0.2;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);

    // Determine if pixel is "green" based on relative channel dominance
    float green_strength = tex_color.g - max(tex_color.r, tex_color.b);

    // If green dominates above tolerance, discard (make invisible)
    if (green_strength > tolerance) {
        discard;
    }

    COLOR = tex_color;
}
