class_name TrainingDummy
extends StaticBody3D

## Тренировочный манекен для проверки оружия и физики попаданий.
## Реагирует на выстрелы, взрывы и удары, отображает покачивание при попадании
## и автоматически восстанавливается после "нокаута".

@export var max_health: float = 100.0
@export var health: float = 100.0
@export var wobble_strength: float = 0.2
@export var reset_delay: float = 1.5

@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")

var _is_recovering: bool = false
var _initial_transform: Transform3D
var _current_tween: Tween = null
var _original_material: Material = null

func _ready() -> void:
	add_to_group("target_dummy")
	add_to_group("damageable")
	health = max_health
	_initial_transform = transform
	
	if mesh_instance and mesh_instance.get_surface_override_material(0):
		_original_material = mesh_instance.get_surface_override_material(0)

func take_damage(amount: float, weapon_data: WeaponData = null) -> void:
	if _is_recovering:
		return
		
	health = maxf(0.0, health - amount)
	var weapon_name = weapon_data.weapon_name if weapon_data else "Unknown"
	
	# Эффект покачивания при попадании
	_play_hit_wobble()
	
	if health <= 0.0:
		_knockdown()

func _play_hit_wobble() -> void:
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
		
	_current_tween = create_tween()
	var tilt_angle = deg_to_rad(randf_range(5.0, 15.0) * wobble_strength * 10.0)
	var wobble_rot = Vector3(
		randf_range(-tilt_angle, tilt_angle),
		0.0,
		randf_range(-tilt_angle, tilt_angle)
	)
	
	_current_tween.tween_property(self, "rotation", wobble_rot, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_current_tween.tween_property(self, "rotation", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _knockdown() -> void:
	_is_recovering = true
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
		
	_current_tween = create_tween()
	# Падение назад на 90 градусов
	var knocked_rot = Vector3(deg_to_rad(-85.0), 0.0, 0.0)
	_current_tween.tween_property(self, "rotation", knocked_rot, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_current_tween.tween_interval(reset_delay)
	_current_tween.tween_callback(_reset_dummy)

func _reset_dummy() -> void:
	health = max_health
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
		
	_current_tween = create_tween()
	# Пружинный подъем обратно
	_current_tween.tween_property(self, "rotation", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_current_tween.tween_callback(func(): _is_recovering = false)

func interact(interactor: Node = null) -> void:
	# Ручной сброс манекена
	_reset_dummy()
