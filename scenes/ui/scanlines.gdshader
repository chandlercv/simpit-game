// CRT-style scanlines + vignette for the Tactical display. Purely cosmetic
// darkening drawn over the amber UI; cheap enough for a spacedesk-streamed
// 2D window (plan risk #5: keep secondary windows cheap).
shader_type canvas_item;

uniform float line_strength : hint_range(0.0, 1.0) = 0.14;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	float scan = 0.5 + 0.5 * sin(FRAGCOORD.y * PI);
	float dark = line_strength * scan;
	vec2 uv = UV - 0.5;
	dark += vignette_strength * dot(uv, uv) * 1.4;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(dark, 0.0, 0.8));
}
