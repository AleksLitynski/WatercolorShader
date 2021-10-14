shader_type spatial;
render_mode unshaded;

uniform sampler2D tex;


void fragment() {
	vec2 tex_size = vec2(textureSize(tex, 0));
	vec2 frag_coord = UV * tex_size;
	ALBEDO = texture(tex, frag_coord / tex_size).xyz;

}
