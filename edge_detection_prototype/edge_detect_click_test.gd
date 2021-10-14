tool
extends MeshInstance


		
func _process(delta):
	get_surface_material(0).set_shader_param("cursor_dir", get_viewport().get_mouse_position().normalized() - Vector2(0.5, 0.5))

