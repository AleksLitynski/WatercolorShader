extends Camera

onready var target = $"../exterior"

func _process(delta):
	var t = target.find_node("__camera_hook")
	var lt = target.find_node("__camera_target")
	global_transform.origin = lerp(
		global_transform.origin, 
		t.global_transform.origin,
		3.0 * delta)

	var l_at = global_transform.looking_at(lt.global_transform.origin, Vector3.UP)

	global_transform.basis = Basis(Quat(
		global_transform.basis).slerp(
			l_at.basis, 
			3.0 * delta))

func _on_show_exterior_pressed():
	target = $"../exterior"

func _on_show_interior_pressed():
	target = $"../interior"
