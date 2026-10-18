shader_type canvas_item;
// Screen post effects over the finished (upscaled) 3D image, all optional:
//  * camera motion blur from turning (pixel motion of a camera rotation does
//    not depend on depth, so it needs only the old and new view rotation);
//  * sun shafts: a radial blur of the bright sky towards the sun;
//  * lens flare: a few soft ghosts along the line through the screen centre;
//  * chromatic aberration towards the edges.
// WorldView enables the rect only while one of them is active.
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float blur_amount = 0.0;
uniform mat3 reproject = mat3(1.0);   // old view rotation * inverse(new view rotation)
uniform vec2 tan_half_fov = vec2(0.7, 0.4);
uniform float aberration = 0.0;
uniform vec2 sun_uv = vec2(0.5, 0.2);
uniform float shafts = 0.0;
uniform float flare = 0.0;
uniform vec3 sun_color = vec3(1.0, 0.9, 0.75);

vec2 prev_uv(vec2 uv) {
	vec3 ray = vec3((uv.x * 2.0 - 1.0) * tan_half_fov.x, (1.0 - uv.y * 2.0) * tan_half_fov.y, -1.0);
	vec3 old = reproject * ray;
	if (old.z > -0.01) {
		return uv;
	}
	vec2 ndc = old.xy / (-old.z) / tan_half_fov;
	return vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

vec3 sample_ca(vec2 uv) {
	if (aberration <= 0.0) {
		return textureLod(screen_tex, uv, 0.0).rgb;
	}
	vec2 d = (uv - 0.5) * aberration * 0.012 * dot(uv - 0.5, uv - 0.5) * 4.0;
	return vec3(textureLod(screen_tex, uv + d, 0.0).r, textureLod(screen_tex, uv, 0.0).g, textureLod(screen_tex, uv - d, 0.0).b);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = sample_ca(uv);
	if (blur_amount > 0.0) {
		vec2 vel = (uv - prev_uv(uv)) * blur_amount;
		float len = length(vel);
		if (len > 0.0008) {
			vel *= min(1.0, 0.05 / len);   // clamp the streak to 5% of the screen
			vec3 acc = col;
			for (int i = 1; i < 8; i++) {
				float t = float(i) / 7.0 - 0.5;
				acc += sample_ca(uv + vel * t);
			}
			col = acc / 8.0;
		}
	}
	if (shafts > 0.0) {
		// Bright sky pixels smeared towards the sun (bloom alone is round).
		vec2 to_sun = sun_uv - uv;
		vec3 acc = vec3(0.0);
		float decay = 1.0;
		for (int i = 0; i < 16; i++) {
			vec2 p = uv + to_sun * (float(i) / 16.0) * 0.85;
			vec3 c = textureLod(screen_tex, p, 2.0).rgb;
			float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
			acc += c * smoothstep(0.62, 0.95, lum) * decay;
			decay *= 0.93;
		}
		float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		float fall = 1.0 - smoothstep(0.0, 0.75, length(to_sun * vec2(aspect, 1.0)));
		col += acc / 16.0 * sun_color * shafts * fall * 0.9;
	}
	if (flare > 0.0) {
		float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		vec2 axis = vec2(0.5) - sun_uv;
		vec3 f = vec3(0.0);
		// Ghosts: position along the axis, radius, tint.
		const float pos[4] = float[](0.55, 1.1, 1.45, 1.9);
		const float rad[4] = float[](0.035, 0.07, 0.025, 0.11);
		const vec3 tint[4] = vec3[](vec3(0.9, 0.6, 0.3), vec3(0.3, 0.6, 0.9), vec3(0.7, 0.9, 0.5), vec3(0.6, 0.4, 0.8));
		for (int i = 0; i < 4; i++) {
			vec2 c = sun_uv + axis * pos[i];
			float d = length((uv - c) * vec2(aspect, 1.0));
			f += tint[i] * (1.0 - smoothstep(rad[i] * 0.6, rad[i], d)) * 0.06;
		}
		// Soft halo around the sun itself.
		float hd = length((uv - sun_uv) * vec2(aspect, 1.0));
		f += sun_color * exp(-hd * 9.0) * 0.08;
		col += f * flare * sun_color;
	}
	COLOR = vec4(col, 1.0);
}
