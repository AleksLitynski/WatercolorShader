

tool # Needed so it runs in the editor.
extends EditorScenePostImport

# add watercolor resource to each mesh, use vertex colors instead of texture
func convert_to_watercolor(node: Node):
	if node.get_class() == "MeshInstance":
		var wcRes = load("res://watercolor/watercolor_resource.tres").duplicate()
		wcRes.set_shader_param("use_albedo_texture", false)
		var aabb = node.get_aabb()
		wcRes.next_pass = wcRes.next_pass.duplicate()
		wcRes.next_pass.set_shader_param("mesh_size", aabb.size)
		node.mesh.surface_set_material(0, wcRes)
	
	for child in node.get_children():
		convert_to_watercolor(child)

func post_import(scene):
	convert_to_watercolor(scene)
	return scene
