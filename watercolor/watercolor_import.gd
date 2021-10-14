

tool # Needed so it runs in the editor.
extends EditorScenePostImport

# add the watercolor resource to each mesh
func convert_to_watercolor(node: Node):
	if node.get_class() == "MeshInstance":
		print("Importing as watercolor: ", node.name)
		var surface = node.mesh.surface_get_material(0)
		var wcRes = load("res://watercolor/watercolor_resource.tres").duplicate()
		wcRes.set_shader_param("use_albedo_texture", true)
		wcRes.set_shader_param("albedo_texture", surface.albedo_texture)
		var aabb = node.get_aabb()
		wcRes.next_pass = wcRes.next_pass.duplicate()
		wcRes.next_pass.set_shader_param("mesh_size", aabb.size)
		node.mesh.surface_set_material(0, wcRes)
	
	for child in node.get_children():
		convert_to_watercolor(child)

func post_import(scene):
	convert_to_watercolor(scene)
	return scene

# MeshInstance / mesh / surface_1 / material <- replace material with WC .tres
# Albedo / Texture <- move origional texture to watercolor texture (base color)

# uniform sampler2D albedo;
# uniform bool use_albedo_texture = false;
