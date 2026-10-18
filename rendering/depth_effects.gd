class_name DepthEffects
extends CompositorEffect
## Depth-aware screen effects, run by the renderer after the transparent pass
## (so the water surface, which writes depth, is included), at the internal
## 3D resolution before tonemapping:
##  * weather haze: rain, snow and dust soften the distance - a depth-weighted
##    separable blur whose radius grows with distance and precipitation
##    (heavier in storms and blizzards) plus a little extra veil of the fog
##    colour; near things stay sharp and never bleed into the far ones;
##  * under water (the camera below the surface): distance absorption and
##    in-scattering in the water's colour, darker with depth, caustics dancing
##    over every surface below the waterline, and god rays - sunlight shafts
##    through the moving surface, marched along each view ray.
## WorldView owns one, feeds the parameters each frame and attaches it to the
## camera's Compositor. Both passes are skipped while nothing is active.

## 0..1 precipitation softening.
var haze := 0.0
var haze_color := Vector3(0.5, 0.55, 0.6)
## 0..1 camera under water.
var underwater := 0.0
var water_y := 0.0
var extinction := Vector3(0.48, 0.16, 0.13)
var water_light := Vector3(0.02, 0.07, 0.07)
var sun_dir := Vector3.UP
var sun_color := Vector3.ONE
var time := 0.0
var daylight := 1.0
## The camera's clip planes and vertical field of view (from WorldView).
var cam_near := 0.05
var cam_far := 4000.0
var tan_half_fov_y := 0.7

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _sampler := RID()
var _params := RID()
var _tmp := RID()
var _tmp_size := Vector2i.ZERO
var _failed := false

const PARAM_VECS := 12

const GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D src_image;
layout(rgba16f, set = 0, binding = 1) uniform image2D dst_image;
layout(set = 0, binding = 2) uniform sampler2D depth_tex;
layout(set = 0, binding = 3, std430) restrict readonly buffer Params {
	vec4 bx;        // camera basis x, w near
	vec4 by;        // camera basis y, w far
	vec4 bz;        // camera basis z, w tan(half fov x)
	vec4 cam;       // camera position, w tan(half fov y)
	vec4 haze;      // amount, start m, range m, max radius px
	vec4 haze_col;  // rgb, a veil
	vec4 water;     // underwater, surface y, time, daylight
	vec4 ext;       // extinction rgb per m, a caustics
	vec4 wlight;    // in-scattered water colour
	vec4 sun_dir;
	vec4 sun_col;
	vec4 pad;
} p;
layout(push_constant, std430) uniform Push {
	vec2 size;
	float pass_id;
	float pad;
} pc;

float dist_at(ivec2 px) {
	float d = texelFetch(depth_tex, clamp(px, ivec2(0), ivec2(pc.size) - 1), 0).r;
	float n = p.bx.w;
	float f = p.by.w;
	float z = n * f / (d * (f - n) + n);   // reverse-Z: 1 at near, 0 at far
	vec2 uv = (vec2(px) + 0.5) / pc.size;
	vec3 ray = vec3((uv.x * 2.0 - 1.0) * p.bz.w, (1.0 - uv.y * 2.0) * p.cam.w, -1.0);
	return z * length(ray);
}

vec3 world_ray(vec2 uv) {
	vec3 r = vec3((uv.x * 2.0 - 1.0) * p.bz.w, (1.0 - uv.y * 2.0) * p.cam.w, -1.0);
	return normalize(p.bx.xyz * r.x + p.by.xyz * r.y + p.bz.xyz * r.z);
}

float radius_for(float dist) {
	float k = clamp((dist - p.haze.y) / p.haze.z, 0.0, 1.0);
	return p.haze.x * k * k * (3.0 - 2.0 * k) * p.haze.w;
}

float hash12(vec2 q) {
	vec3 p3 = fract(vec3(q.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float caustic(vec2 q0, float t) {
	vec2 q = mod(q0 * 0.55, 6.2831853) - 250.0;
	vec2 i = q;
	float c = 1.0;
	const float inten = 0.005;
	for (int n = 0; n < 4; n++) {
		float tt = t * 0.45 * (1.0 - (3.5 / float(n + 1)));
		i = q + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(q.x / (sin(i.x + tt) / inten), q.y / (cos(i.y + tt) / inten)));
	}
	c /= 4.0;
	c = 1.17 - pow(c, 1.4);
	return clamp(pow(abs(c), 8.0), 0.0, 2.0);
}

// Soft light shafts: the surface's focusing pattern, broad and slow.
float shafts(vec2 q, float t) {
	float a = sin(q.x * 0.9 + t * 0.6 + sin(q.y * 0.7 + t * 0.3) * 1.8);
	float b = sin(q.y * 1.1 - t * 0.5 + sin(q.x * 0.5 - t * 0.4) * 2.1);
	float c = sin((q.x + q.y) * 0.63 + t * 0.35);
	return pow(clamp((a * b + c * 0.5) * 0.5 + 0.5, 0.0, 1.0), 3.0);
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(pc.size.x) || px.y >= int(pc.size.y)) {
		return;
	}
	vec4 center = imageLoad(src_image, px);
	float dist = dist_at(px);
	float r = radius_for(dist);
	vec3 col = center.rgb;
	if (r > 0.35) {
		ivec2 axis = pc.pass_id < 0.5 ? ivec2(1, 0) : ivec2(0, 1);
		float step_px = max(r / 4.0, 1.0);
		vec3 acc = center.rgb;
		float wsum = 1.0;
		for (int i = -4; i <= 4; i++) {
			if (i == 0) {
				continue;
			}
			float o = float(i) * step_px;
			ivec2 q = clamp(px + axis * int(round(o)), ivec2(0), ivec2(pc.size) - 1);
			float w = exp(-(o * o) / (2.0 * r * r * 0.45));
			// Only gather from pixels at least as soft (no near haloes).
			w *= clamp(radius_for(dist_at(q)) / max(r, 1e-3), 0.0, 1.0);
			acc += imageLoad(src_image, q).rgb * w;
			wsum += w;
		}
		col = acc / wsum;
	}
	if (pc.pass_id > 0.5) {
		// The veil: precipitation scatters the fog colour over the distance.
		float veil = p.haze_col.a * clamp(r / max(p.haze.w, 1e-3), 0.0, 1.0);
		col = mix(col, p.haze_col.rgb, veil);
		if (p.water.x > 0.0) {
			vec2 uv = (vec2(px) + 0.5) / pc.size;
			vec3 rd = world_ray(uv);
			float d = min(dist, 300.0);
			vec3 wp = p.cam.xyz + rd * d;
			float t = p.water.z;
			float surf = p.water.y;
			vec3 sd = normalize(p.sun_dir.xyz + vec3(0.0, 1e-3, 0.0));
			vec2 slant = sd.xz / max(sd.y, 0.25);
			float sky_far = step(p.by.w * 0.97, dist);
			// Caustics on surfaces below the water line.
			float below = surf - wp.y;
			if (below > 0.0 && sky_far < 0.5) {
				float c = caustic(wp.xz + slant * below, t);
				col *= 1.0 + c * p.ext.a * 2.2 * exp(-below * 0.07) * p.water.w * smoothstep(0.0, 0.4, below);
			}
			// Absorption and in-scattering along the view ray; deeper is darker.
			float cam_below = max(surf - p.cam.y, 0.0);
			vec3 light = p.wlight.rgb * exp(-p.ext.rgb * (cam_below * 0.5 + max(below, 0.0) * 0.25));
			vec3 tr = exp(-p.ext.rgb * d);
			vec3 under_col = col * tr + light * (1.0 - tr);
			// God rays: march towards the scene, sample the shaft pattern
			// projected up along the sun to the surface.
			float march = min(d, 36.0);
			// Interleaved gradient noise, kept mild: soft shafts, no visible grain.
			float ign = fract(52.9829189 * fract(dot(vec2(px), vec2(0.06711056, 0.00583715))));
			float jitter = 0.5 + (ign - 0.5) * 0.35;
			float rays = 0.0;
			for (int i = 0; i < 10; i++) {
				float s = (float(i) + jitter) / 10.0 * march;
				vec3 q = p.cam.xyz + rd * s;
				float qb = max(surf - q.y, 0.0);
				float sh = shafts((q.xz + slant * qb) * 0.35, t);
				rays += sh * exp(-p.ext.g * (s * 0.6 + qb * 0.35));
			}
			rays *= march / 10.0 * 0.16 * p.water.w;
			float facing_sun = 0.55 + 0.45 * max(dot(rd, sd), 0.0);
			under_col += p.sun_col.rgb * vec3(0.55, 0.9, 0.85) * rays * facing_sun;
			col = mix(col, under_col, p.water.x);
		}
	}
	imageStore(dst_image, px, vec4(col, center.a));
}
"""


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = false
	RenderingServer.call_on_render_thread(_setup)


## Frees the GPU resources (on the render thread, while the device lives).
## Call when the view goes away; the effect does nothing afterwards.
func release() -> void:
	_failed = true
	RenderingServer.call_on_render_thread(_free)


func _free() -> void:
	if _rd == null:
		return
	for rid: RID in [_tmp, _params, _sampler, _pipeline, _shader]:
		if rid.is_valid():
			_rd.free_rid(rid)
	_tmp = RID()
	_params = RID()
	_sampler = RID()
	_pipeline = RID()
	_shader = RID()


## Whether either effect needs the passes this frame.
func active() -> bool:
	return haze > 0.002 or underwater > 0.002


func _setup() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		_failed = true
		return
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = GLSL
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("DepthEffects: %s" % spirv.compile_error_compute)
		_failed = true
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		_failed = true
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = _rd.sampler_create(ss)
	var zero := PackedFloat32Array()
	zero.resize(PARAM_VECS * 4)
	_params = _rd.storage_buffer_create(zero.size() * 4, zero.to_byte_array())


func _render_callback(type: int, render_data: RenderData) -> void:
	if _failed or _rd == null or type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or not active():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data()
	if buffers == null or scene == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	if _tmp_size != size or not _tmp.is_valid():
		if _tmp.is_valid():
			_rd.free_rid(_tmp)
		var tf := RDTextureFormat.new()
		tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		tf.width = size.x
		tf.height = size.y
		tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		_tmp = _rd.texture_create(tf, RDTextureView.new())
		_tmp_size = size
	var xf := scene.get_cam_transform()
	var near := cam_near
	var far := cam_far
	var tan_y := tan_half_fov_y
	var tan_x := tan_y * float(size.x) / float(size.y)
	var b := xf.basis
	var data := PackedFloat32Array([
		b.x.x, b.x.y, b.x.z, near,
		b.y.x, b.y.y, b.y.z, far,
		b.z.x, b.z.y, b.z.z, tan_x,
		xf.origin.x, xf.origin.y, xf.origin.z, tan_y,
		haze, lerpf(70.0, 18.0, haze), lerpf(420.0, 140.0, haze), 7.0 * clampf(size.y / 560.0, 0.6, 2.5),
		haze_color.x, haze_color.y, haze_color.z, 0.35 * haze,
		underwater, water_y, time, daylight,
		extinction.x, extinction.y, extinction.z, 1.0,
		water_light.x, water_light.y, water_light.z, 0.0,
		sun_dir.x, sun_dir.y, sun_dir.z, 0.0,
		sun_color.x, sun_color.y, sun_color.z, 0.0,
		0.0, 0.0, 0.0, 0.0,
	])
	_rd.buffer_update(_params, 0, data.size() * 4, data.to_byte_array())
	var groups_x := (size.x - 1) / 8 + 1
	var groups_y := (size.y - 1) / 8 + 1
	for view in buffers.get_view_count():
		var color := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)
		for pass_id in 2:
			var src := color if pass_id == 0 else _tmp
			var dst := _tmp if pass_id == 0 else color
			var set_rid := UniformSetCacheRD.get_cache(_shader, 0, [
				_image_uniform(0, src), _image_uniform(1, dst), _depth_uniform(2, depth), _buffer_uniform(3, _params)])
			var push := PackedFloat32Array([size.x, size.y, float(pass_id), 0.0]).to_byte_array()
			var list := _rd.compute_list_begin()
			_rd.compute_list_bind_compute_pipeline(list, _pipeline)
			_rd.compute_list_bind_uniform_set(list, set_rid, 0)
			_rd.compute_list_set_push_constant(list, push, push.size())
			_rd.compute_list_dispatch(list, groups_x, groups_y, 1)
			_rd.compute_list_end()


func _image_uniform(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u


func _depth_uniform(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(_sampler)
	u.add_id(tex)
	return u


func _buffer_uniform(binding: int, buf: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(buf)
	return u
