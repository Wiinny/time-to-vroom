# Caméra poursuite lissée. Purement cosmétique, en float — n'influence jamais
# la simulation.
class_name ChaseCamera
extends Camera3D

@export var distance: float = 8.0
@export var height: float = 3.5
@export var smoothing: float = 6.0

var _target: Node3D

func set_target(target: Node3D) -> void:
	_target = target
	if target != null:
		global_position = _desired_position()

func _desired_position() -> Vector3:
	var back: Vector3 = _target.global_transform.basis.z.normalized()
	return _target.global_position + back * distance + Vector3(0.0, height, 0.0)

func _process(delta: float) -> void:
	if _target == null:
		return
	var t: float = 1.0 - exp(-smoothing * delta)
	global_position = global_position.lerp(_desired_position(), t)
	look_at(_target.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
