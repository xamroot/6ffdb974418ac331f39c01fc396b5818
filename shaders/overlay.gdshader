shader_type canvas_item;

uniform sampler2D mask_tex : source_color;   // set to owner_tex
uniform vec4 overlay_color : source_color = vec4(1.0, 0.0, 0.0, 0.5);
uniform vec2 texel;// = vec2(1.0/1024.0, 1.0/1024.0); // set to (1/W, 1/H)
uniform float feather_px = 1.25; // feather radius in pixels

void fragment() {
    vec2 uv = UV;
    // Read red channel as your mask (1 = owned, 0 = not)
    float c00 = texture(mask_tex, uv).r;

    // 3x3 box around the pixel (cheap blur for boundary)
    float sum = 0.0;
    sum += texture(mask_tex, uv + vec2(-texel.x, -texel.y)).r;
    sum += texture(mask_tex, uv + vec2(0.0,       -texel.y)).r;
    sum += texture(mask_tex, uv + vec2(texel.x,  -texel.y)).r;
    sum += texture(mask_tex, uv + vec2(-texel.x,  0.0)).r;
    sum += c00;
    sum += texture(mask_tex, uv + vec2(texel.x,   0.0)).r;
    sum += texture(mask_tex, uv + vec2(-texel.x,  texel.y)).r;
    sum += texture(mask_tex, uv + vec2(0.0,        texel.y)).r;
    sum += texture(mask_tex, uv + vec2(texel.x,    texel.y)).r;

    float avg = sum / 9.0;

    // Feather width in UV (convert pixels -> uv)
    float w = feather_px * max(texel.x, texel.y);

    // Smooth transition; tweak thresholds for harder/softer edges
    float a = smoothstep(0.35 - w, 0.65 + w, avg);

    COLOR = vec4(overlay_color.rgb, overlay_color.a * a);
}
