shader_type spatial;

uniform vec2 cursor_dir;

const float max_dist = 5000.0;

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

void fragment() {
	ALBEDO = texture(SCREEN_TEXTURE, FRAGCOORD.xy / VIEWPORT_SIZE).xyz;

	vec2 pt = VIEWPORT_SIZE * 0.5;
	vec2 dir = vec2(-1.0, 0.0); // cursor_dir;
	if (distance(FRAGCOORD.xy, pt) < 8.0) ALBEDO = vec3(0.0);

	int t_axes = 8;
	float max_range = 50.0;
	int iterations = 8;
	int tunnel_checks = 3;
	for (int i = 0; i < t_axes; i++) {
		vec2 angle = rotate(vec2(0.0, 1.0), (radians(360)) * (float(i) / float(t_axes)) * 0.5);
		vec4 cp = color_axis(SCREEN_TEXTURE, VIEWPORT_SIZE, pt, angle, max_range, iterations, tunnel_checks);
		if (distance(FRAGCOORD.xy, cp.xy) < 5.0) {
			ALBEDO = vec3(angle, 1.0);
		}
		if (distance(FRAGCOORD.xy, cp.zw) < 5.0) {
			ALBEDO = vec3(rotate(angle, radians(180)), 1.0);
		}
	}

	float min_margin_ratio = 1.0;
	float small_cutoff = 30.0;
	float very_small_length = 0.0;
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
		
		float mr = min(margin1_ratio, margin2_ratio);
		if (dist_a < small_cutoff || dist_b < small_cutoff) {
			very_small_length++;
		}
	}
	
	float stm = very_small_length / float(t_axes);
	if (stm > 0.1) {
		ALBEDO *= smoothstep(0.0, 1.0, min_margin_ratio + 0.4);
	}
}
