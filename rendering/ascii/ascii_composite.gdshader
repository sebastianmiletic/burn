shader_type canvas_item;
render_mode unshaded, blend_disabled;
// Draws the glyph grid at native screen resolution from the cell textures the
// AsciiEffect produced, then adds the FX layer (fire, sparks, spells and their
// bloom) on top. Also applies the chosen render style.

// Cell data (Texture2DRD wrapping AsciiEffect's RD textures).
uniform sampler2D cell_color : filter_nearest;        // rgb = exposed linear colour, a = glyph index
uniform sampler2D cell_color_soft : filter_linear;    // same texture, filtered, for glyph glow
uniform sampler2D cell_aux : filter_nearest;          // r = mode, g = material, b = edge dir, a = brightness
uniform sampler2D atlas : filter_nearest;             // one row of glyphs, each cell_px in size
uniform sampler2D fx_layer : filter_linear;           // 3D viewport output: FX + glow (or the raw scene)

uniform vec2 target_px = vec2(1920.0, 1080.0);        // physical size of this rect
uniform vec2 cell_px = vec2(8.0, 14.0);
uniform vec2 grid = vec2(240.0, 78.0);

uniform int style = 0;              // 0 ember, 1 full colour, 2 classic (full colour), 3 phosphor
uniform bool raw_mode = false;      // ASCII off / debug views: show the 3D viewport as is
uniform float brightness = 1.0;
uniform float glyph_gain = 1.25;
uniform float bg_fill = 0.32;       // how much of the cell colour fills the background
uniform float glyph_glow = 0.35;
uniform float vignette = 0.3;
uniform float grain = 0.04;
uniform float shimmer = 0.0;
uniform float fx_strength = 1.0;
uniform float flash = 0.0;          // lightning / hit flash, 0..1
uniform vec3 tint = vec3(1.0);      // damage vignette, underworld tint
uniform float time = 0.0;
uniform int debug_mode = 0;         // 1 cell colour, 2 atlas, 3 glyph index

vec3 aces(vec3 x) {
	const float a = 2.51;
	const float b = 0.03;
	const float c = 2.43;
	const float d = 0.59;
	const float e = 0.14;
	return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// The warm duotone of the Ember style, in sRGB: near-black brown -> blood ->
// burnt orange -> peach -> cream.
vec3 ember(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 c0 = vec3(0.035, 0.016, 0.012);
	vec3 c1 = vec3(0.17, 0.055, 0.03);
	vec3 c2 = vec3(0.45, 0.17, 0.075);
	vec3 c3 = vec3(0.74, 0.4, 0.21);
	vec3 c4 = vec3(0.92, 0.68, 0.49);
	vec3 c5 = vec3(1.0, 0.9, 0.78);
	if (t < 0.18) return mix(c0, c1, t / 0.18);
	if (t < 0.4) return mix(c1, c2, (t - 0.18) / 0.22);
	if (t < 0.62) return mix(c2, c3, (t - 0.4) / 0.22);
	if (t < 0.82) return mix(c3, c4, (t - 0.62) / 0.2);
	return mix(c4, c5, (t - 0.82) / 0.18);
}

vec3 phosphor(float t) {
	t = clamp(t, 0.0, 1.0);
	return mix(vec3(0.0, 0.03, 0.01), vec3(0.55, 1.0, 0.6), pow(t, 0.9));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float ink_at(float g, ivec2 local, ivec2 csz) {
	local = clamp(local, ivec2(0), csz - 1);
	return texelFetch(atlas, ivec2(int(g + 0.5) * csz.x + local.x, local.y), 0).r;
}

void fragment() {
	vec2 px = UV * target_px;
	vec3 fx = to_linear(texture(fx_layer, UV).rgb);

	if (raw_mode) {
		COLOR = vec4(to_srgb(clamp(fx * tint, 0.0, 1.0)), 1.0);
	} else {
		ivec2 csz = ivec2(cell_px);
		ivec2 cell = min(ivec2(floor(px / cell_px)), ivec2(grid) - 1);
		ivec2 local = ivec2(px) - cell * csz;
		vec4 cc = texelFetch(cell_color, cell, 0);
		vec4 aux = texelFetch(cell_aux, cell, 0);
		bool pass_through = abs(aux.r - 1.0) < 0.5;

		vec3 lin = max(cc.rgb, vec3(0.0)) * brightness;
		vec3 mapped = aces(lin);
		float lum = dot(mapped, vec3(0.2126, 0.7152, 0.0722));

		float ink = ink_at(cc.a, local, csz);
		vec3 fg;
		vec3 bg;
		if (style == 0) {
			// Perceptual brightness drives the duotone; reds keep a little hue.
			float t = pow(lum, 0.6);
			t = clamp((t - 0.45) * 1.45 + 0.47, 0.0, 1.0);
			float warm = clamp((mapped.r - max(mapped.g, mapped.b)) * 2.5, 0.0, 1.0);
			vec3 hue = to_srgb(mapped);
			fg = mix(ember(clamp(t * 1.18 + 0.06, 0.3, 1.0)), hue * 1.1, warm * 0.35);
			bg = ember(t * 0.6) * bg_fill * 2.0 * t;
			fg = to_linear(fg);
			bg = to_linear(bg);
		} else if (style == 3) {
			float t = pow(lum, 0.55);
			fg = to_linear(phosphor(t * 1.1));
			bg = to_linear(phosphor(t * 0.5)) * bg_fill;
		} else {
			fg = aces(lin * glyph_gain);
			bg = mapped * bg_fill * 0.45;
		}

		if (shimmer > 0.0 && lum > 0.7) {
			float s = sin(time * 3.0 + float(cell.x) * 0.7 + float(cell.y) * 1.3);
			int off = s > 0.33 ? 1 : (s < -0.33 ? -1 : 0);
			vec3 inks = vec3(ink_at(cc.a, local + ivec2(off, 0), csz), ink, ink_at(cc.a, local - ivec2(off, 0), csz));
			inks = mix(vec3(ink), inks, shimmer);
			COLOR.rgb = bg * (1.0 - inks) + fg * inks;
		} else {
			COLOR.rgb = mix(bg, fg, ink);
		}
		if (pass_through) {
			COLOR.rgb = vec3(0.0);
		}

		// Glyph glow: bright cells bleed soft light onto their neighbours.
		if (glyph_glow > 0.0) {
			vec2 cuv = (vec2(cell) + 0.5) / grid;
			vec2 o = 1.6 / grid;
			vec3 g = vec3(0.0);
			g += texture(cell_color_soft, cuv + vec2(o.x, 0.0)).rgb;
			g += texture(cell_color_soft, cuv - vec2(o.x, 0.0)).rgb;
			g += texture(cell_color_soft, cuv + vec2(0.0, o.y)).rgb;
			g += texture(cell_color_soft, cuv - vec2(0.0, o.y)).rgb;
			g = max(g * 0.25 * brightness - vec3(0.9), vec3(0.0));
			vec3 gl = style == 0 ? to_linear(ember(0.85)) * dot(g, vec3(0.33)) : g;
			COLOR.rgb += gl * glyph_glow * 0.25;
		}

		vec3 fx_c = fx * fx_strength;
		if (style == 0) {
			// FX keep their fire colours but lean into the palette.
			float fl = dot(fx_c, vec3(0.2126, 0.7152, 0.0722));
			fx_c = mix(fx_c, to_linear(ember(clamp(fl * 1.3, 0.0, 1.0))) * 1.2, 0.35);
		} else if (style == 3) {
			fx_c = to_linear(phosphor(dot(fx_c, vec3(0.33)) * 1.2)) * 1.3;
		}
		COLOR.rgb += fx_c;
		COLOR.rgb *= tint;
		COLOR.rgb += vec3(flash) * (style == 0 ? to_linear(ember(0.95)) : vec3(0.9, 0.95, 1.0)) * 0.8;
		COLOR.rgb = to_srgb(clamp(COLOR.rgb, 0.0, 1.0));
	}

	vec2 uv = UV - 0.5;
	COLOR.rgb *= clamp(1.0 - vignette * dot(uv, uv) * 2.4, 0.0, 1.0);
	if (grain > 0.0) {
		COLOR.rgb *= 1.0 + (hash12(px + fract(time * 13.7) * 1000.0) - 0.5) * grain;
	}
	if (debug_mode == 1) {
		COLOR.rgb = to_srgb(clamp(aces(texture(cell_color, UV).rgb), 0.0, 1.0));
	} else if (debug_mode == 2) {
		COLOR.rgb = vec3(texture(atlas, vec2(UV.x, UV.y * 8.0)).r);
	} else if (debug_mode == 3) {
		COLOR.rgb = vec3(texture(cell_color, UV).a / 90.0, texture(cell_aux, UV).r / 3.0, texture(cell_aux, UV).a);
	}
	COLOR.a = 1.0;
}
