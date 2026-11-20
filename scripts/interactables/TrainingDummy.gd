class_name TrainingDummy
extends StaticBody3D

## Мишень / Тренировочный советский манекен для проверки всех 13 видов оружия.

@export var max_health: float = 500.0
var health: float = 500.0
@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")

func _ready() -> void:
	health = max_health

func take_damage(amount: float, _weapon_data: WeaponData = null) -> void:
	health -= amount
	
	# Визуальная вспышка и покачивание от удара
	if mesh_instance:
		var mat = mesh_instance.get_active_material(0)
		if mat is StandardMaterial3D:
			var prev_color = mat.albedo_color
			mat.albedo_color = Color(1.0, 0.2, 0.2)
			var tween = create_tween()
			tween.tween_property(mat, "albedo_color", prev_color, 0.15)
			
	var wobble = create_tween()
	wobble.tween_property(self, "rotation_degrees:x", 12.0, 0.05)
	wobble.tween_property(self, "rotation_degrees:x", 0.0, 0.1)
	
	if health <= 0:
		health = max_health
