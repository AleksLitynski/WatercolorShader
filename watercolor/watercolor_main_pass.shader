shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;

uniform sampler2D paper;
uniform sampler2D paper_normal;
uniform sampler2D paint_blur;
uniform sampler2D ink_blots;
uniform sampler2D watercolor_ramp;
uniform float outline_width = 3.0;
uniform float outline_draw_depth = 5.0;
uniform vec3 mesh_size = vec3(1.8);

float uv_size() {
	return ((mesh_size.x + mesh_size.y + mesh_size.z) / 3.0) * 0.06;
}
float inv(float a) {
	return 1.0 - a;
}
vec3 vinv(vec3 a) {
	return vec3(inv(a.x), inv(a.y), inv(a.z));
}
float sample_depth(mat4 ipm, sampler2D dt, vec2 uv) {
	float depth = texture(dt, uv).x;
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
	vec4 view = ipm * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}

float sobel_color(sampler2D to_sample, vec2 screen_size, vec2 uv) {
	// https://gist.github.com/kzerot/b60cee18a62a80091b2f54a366f07411
	float w = 1.0 / screen_size.x;
	float h = 1.0 / screen_size.y;

	vec4 n0 = texture(to_sample, uv + vec2( -w, -h));
	vec4 n1 = texture(to_sample, uv + vec2(0.0, -h));
	vec4 n2 = texture(to_sample, uv + vec2(  w, -h));
	vec4 n3 = texture(to_sample, uv + vec2( -w, 0.0));
	vec4 n4 = texture(to_sample, uv);
	vec4 n5 = texture(to_sample, uv + vec2(  w, 0.0));
	vec4 n6 = texture(to_sample, uv + vec2( -w, h));
	vec4 n7 = texture(to_sample, uv + vec2(0.0, h));
	vec4 n8 = texture(to_sample, uv + vec2(  w, h));

	vec4 sobel_edge_h = n2 + (2.0*n5) + n8 - (n0 + (2.0*n3) + n6);
  	vec4 sobel_edge_v = n0 + (2.0*n1) + n2 - (n6 + (2.0*n7) + n8);
	vec4 sobel = sqrt((sobel_edge_h * sobel_edge_h) + (sobel_edge_v * sobel_edge_v));
    float alpha = sobel.r;
    alpha += sobel.g;
    alpha +=  sobel.b;
    alpha /= 3.0;
	return alpha;
}

vec3 fix_color(bool srgb, vec3 color) {
	if (srgb) return color;
	return mix(
		pow((color + vec3(0.055)) * (1.0 / (1.0 + 0.055)),
		vec3(2.4)), color * (1.0 / 12.92),
		lessThan(color, vec3(0.04045)));
}
vec3 mix_saturation(vec3 rgb, float adjustment)
{
    // https://github.com/CesiumGS/cesium/blob/master/Source/Shaders/Builtin/Functions/saturation.glsl
    const vec3 W = vec3(0.2125, 0.7154, 0.0721);
    vec3 intensity = vec3(dot(rgb, W));
    return mix(intensity, rgb, adjustment);
}
float greyscale(vec3 col) {
	return dot(col, vec3(0.299, 0.587, 0.114));
}
vec2 paper_coords(vec2 fragcoords) {
	return ((fragcoords.xy / vec2(textureSize(paper, 0)))) * 0.75;
}
vec3 scaled_mult(vec3 a, vec3 b, float scale) {
	return ((a * scale) * (b * scale)) / scale;
}
float map_range(float v, vec2 old, vec2 new) {
	float ratio = (v - old.x) / (old.y - old.x);
	return mix(new.x, new.y, ratio);
}
float map_range_set_new(float v, float start, float end) {
	return map_range(v, vec2(0.0, 1.0), vec2(start, end));
}
float map_range_set_old(float v, float start, float end) {
	return map_range(v, vec2(start, end), vec2(0.0, 1.0));
}
float map_clamp_set_old(float v, float start, float end) {
	return map_range_set_old(clamp(v, start, end), start, end);
}
float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

float vec_to_rad(vec2 vec) {
	vec2 normalized = normalize(vec);
	float angle = atan(normalized.y, normalized.x);
	if (angle == 0.0) {
		angle = radians(180) * 2.0;
	}
	return angle;
}

vec2 rotate(vec2 dir, float rotation) {
	float angle = vec_to_rad(dir) + rotation;
	return vec2(cos(angle), sin(angle));
}

vec2 nearest_intercept(vec2 self, vec2 dir, vec2 bounds, float max_distance) {
	// The point self is somewhere in the box from (0, 0) to bounds
	// project a ray in the direction dir, and find the distance to
	// the first wall of the bounding box that it hits
	float vert_bound = dir.x > 0.0 ? bounds.x : 0.0; // | | (left, right)
	float horz_bound = dir.y > 0.0 ? bounds.y : 0.0; //  == (above, below)
	float slope = dir.y / dir.x;
	float y_intercept = self.y - (slope * self.x);

	vec2 vert_intercept = vec2(vert_bound, slope * (vert_bound) + y_intercept);
	vec2 horz_intercept = dir.x == 0.0
        ? vec2(self.x, horz_bound)
        : vec2((horz_bound - y_intercept)/slope, horz_bound);

	vec2 close_intercept = distance(self, vert_intercept) < distance(self, horz_intercept)
        ? vert_intercept
        : horz_intercept;

	return distance(self, close_intercept) > max_distance
		? self + (dir * max_distance)
		: close_intercept;
}

bool is_close(vec4 a, vec4 b, float threshold) {
	return all(lessThan(a - threshold, b)) && all(greaterThan(a + threshold, b));
}

bool any_samples_off_color(sampler2D screen_texture, vec4 expected_color, vec2 start, vec2 end, int samples) {
	vec2 offset = distance(start, end) * (1.0 / float(samples)) * normalize(end - start);
	vec2 next = start;
	bool any_off_colors = false;
	for(int i = 0; i < samples; i++) {
		next = next + offset;
		vec4 next_color = texelFetch(screen_texture, ivec2(next), 0);
		if (!is_close(next_color, expected_color, 0.1)) {
			any_off_colors = true;
		}
	}
	return any_off_colors;
}

vec2 color_edge(sampler2D screen_texture, vec2 viewport_size, vec2 fragcoords, vec2 dir, float max_distance, int iterations, int tunneling_checks) {
	// normalize direction and get current point's color
	dir = normalize(dir);
	vec4 own_color = texelFetch(screen_texture, ivec2(fragcoords), 0);

	// get the initial step size and point
	vec2 nearest_point = nearest_intercept(fragcoords, dir, viewport_size, max_distance);
	vec2 diff = (nearest_point - fragcoords) * 0.5;
	nearest_point = fragcoords + diff;

	for(int i = 0; i < iterations; i++) {
		// each iteration, shift the other point in or out by 1/2 the distance between self and the nearest point
		vec4 other_color = texelFetch(screen_texture, ivec2(nearest_point), 0);
		// if they're the same color, go outside, if they're different colors, go inside
		diff = diff * 0.5;
		if (!any_samples_off_color(screen_texture, own_color, fragcoords, nearest_point, tunneling_checks)) {
			nearest_point += diff;
		} else {
			nearest_point -= diff;
		}
	}

	// once we've done a fixed number of iterations, return the point
	return nearest_point;
}

vec4 color_axis(sampler2D screen_texture, vec2 viewport_size, vec2 fragcoords, vec2 dir, float max_distance, int iterations, int tunneling_checks) {
	vec2 axis1 = color_edge(screen_texture, viewport_size, fragcoords, dir, max_distance, iterations, tunneling_checks);
	vec2 axis2 = color_edge(screen_texture, viewport_size, fragcoords, -dir, max_distance, iterations, tunneling_checks);
	return vec4(axis1.x, axis1.y, axis2.x, axis2.y);
}


float invstep(float cutoff, float value) {
	return step(cutoff, value) == 1.0 ? 0.0 : 1.0;
}

void fragment() {

	// get the color from the previous shader pass
	vec3 color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	
	// probe out along 8 radial axis to find the nearest color gradiants
	// this is too expensive, but produces a nice effect (8 * 5 * num pixels)
	int t_axes = 8;
	float max_range = 50.0;
	int iterations = 8;
	int tunnel_checks = 5;
	float min_margin_ratio = 1.0;
	for (int i = 0; i < t_axes; i++) {
		vec2 angle = rotate(vec2(0.0, 1.0), (radians(360)) * (float(i) / float(t_axes)) * 0.5);
		vec4 cp = color_axis(SCREEN_TEXTURE, VIEWPORT_SIZE, FRAGCOORD.xy, angle, max_range, iterations, tunnel_checks);
		float dist_a = distance(FRAGCOORD.xy, cp.xy);
		float dist_b = distance(FRAGCOORD.xy, cp.zw);
		float total = distance(cp.xy, cp.zw);
		float margin1_ratio = dist_a / total;
		float margin2_ratio = dist_b / total;
		if (margin1_ratio < min_margin_ratio) {
			min_margin_ratio = margin1_ratio;
		}
		if (margin2_ratio < min_margin_ratio) {
			min_margin_ratio = margin2_ratio;
		}
	}
	// mix in some noise and blotchyness based on the distance from an edge
	// (darker closer to the middle of a color island, goes to white at edges)
	float noise = greyscale(texture(paint_blur, UV * uv_size()).xyz);
	float margin_size = 0.5;
	float noise_level = 1.3;
	float edge_strength = 1.65;
	float paper_cutoff = 0.36; // go completely white at a cutoff close to the edge so it looks like
							   // the brushstroke didn't quite reach the edge of an area
	float margin_between_light_and_dark = 0.3;
	float c = 1.0 - smoothstep(0.0, 1.0, (smoothstep(0.0, 1.0, min_margin_ratio + 0.4) * noise_level) - margin_size);
	float merged = smoothstep(0.0, 1.0, c * noise * edge_strength);
	float watercolored = texture(watercolor_ramp, vec2(merged, 0.0)).x * 0.5;
	if (watercolored < paper_cutoff) {
		color += watercolored * margin_between_light_and_dark;
	} else {
		vec3 paper_tex = smoothstep(-1.0, 1.0, texture(paper, paper_coords(FRAGCOORD.xy)).rgb * greyscale(color) / 1.3 + (1.3 * 0.1));
		color = paper_tex + 0.2; // mix in a little paper texture to the albedo
	}
	
	// use the underlying color gradiant to outline the faces
	float sob = 0.5 - sobel_color(SCREEN_TEXTURE, VIEWPORT_SIZE, SCREEN_UV);
	color = mix(color, vec3(sob), 0.1);

	// fix colorspace if srgb
	ALBEDO = fix_color(OUTPUT_IS_SRGB, color);

	// show the paper texture via normals as well
	NORMAL += texture(paper_normal, paper_coords(FRAGCOORD.xy)).rgb * 0.1;
}


vec3 blotch_color(vec2 uv, float noise, float seed, float scale) {
	vec2 uv2 = (uv + mod(seed, 1.0)) * (1.0 / scale);
	float color = texture(ink_blots, uv2).x - 0.5;
	float gn = smoothstep(0.0, 1.0, color * noise * 20.0);
	float ramped = inv(texture(watercolor_ramp, vec2(inv(gn), 0.0) ).x);
	return vec3(inv(ramped)) * 0.6;
}

void light() {
	// watercolor outline around light sources
	vec3 light = LIGHT_COLOR * 0.1 * 20.0;
	float noise = greyscale(texture(paint_blur, UV * uv_size()).xyz) * length(LIGHT) * greyscale(light);
	float darkness = smoothstep(0.0, 1.0, greyscale(light * ATTENUATION * noise));
	vec3 bw_color = texture(watercolor_ramp, vec2(darkness, 0.0)).xyz;
	vec3 color = clamp(bw_color * clamp(ALBEDO + (bw_color / 30.0), 0.0, 1.0) * light, -1.0, 1.0);
	
	// add blotches of color, more where there's less light
	vec3 total_blotch = vinv(blotch_color(UV * uv_size(), noise, 1.2, 0.3));
	for (int i = 0; i < 4; i++) {
		total_blotch = mix(total_blotch, vinv(blotch_color(UV * uv_size(), noise, rand(vec2(exp(float(i)), log(float(i)))), float(i) * 0.15)), 0.5);
	}
	color = mix(total_blotch * ALBEDO * 0.8, color, 0.4);

	// show paper texture where there's more light, less color (eg, less layers of paint)
	vec3 paper_tex = smoothstep(-1.0, 1.0, texture(paper, paper_coords(FRAGCOORD.xy)).rgb * darkness);
	color *= paper_tex;

 	// get that color in there
	DIFFUSE_LIGHT = min(vec3(0.5), mix(color, DIFFUSE_LIGHT, 0.7)) * 1.6;
}


// 1. hard transitions between light levels
// 2. watercolor bleed around light edges (https://forum.unity.com/threads/watercolour-shadow-shader-effect.379102/)
