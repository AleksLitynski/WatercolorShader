shader_type spatial;
render_mode unshaded;

uniform sampler2D albedo_texture;
uniform bool use_albedo_texture = false;

void vertex() {
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(
			pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), 
			vec3(2.4)), COLOR.rgb * (1.0 / 12.92),
			lessThan(COLOR.rgb,vec3(0.04045)) );
	}
}

void fragment() {
	// just pass along the unshaded color as a opaque layer
	// in the next shader pass, we'll use face colors for edge detection
	if (use_albedo_texture) {
		ALBEDO = texture(albedo_texture, UV).rgb;
	} else {
		ALBEDO = COLOR.rgb;	
	}
	
}
