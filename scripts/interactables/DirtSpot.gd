class_name DirtSpot
extends Area3D

## Единичный элемент грязи, пыли или сорняка.
## Удаляется точечно в месте воздействия инструмента (щётки / скребка).

@export var reward_rubles: int = 1
@export var health: float = 0.4 ## Время непрерывной чистки (в секундах)
@export var spot_color: Color = Color(0.28, 0.22, 0.16)

var max_health: float = 0.4
var is_cleared: bool = false
var mesh_instance: MeshInstance3D

func _ready() -> void:
	max_health = health
	add_to_group("dirt_spot")
	
	# Находим меш для визуальной деградации
	mesh_instance = get_node_or_null("MeshInstance3D")
	
	if GameState:
		GameState.register_cleanup_item()

func scrub(delta_time: float) -> void:
	if is_cleared:
		return
		
	health -= delta_time
	
	# Визуальное уменьшение по мере соскабливания
	var ratio = clampf(health / max_health, 0.05, 1.0)
	if mesh_instance:
		mesh_instance.scale = Vector3(ratio, ratio, ratio)
	
	if health <= 0.0:
		clear_spot()

func clear_spot() -> void:
	if is_cleared:
		return
	is_cleared = true
	collision_layer = 0
	collision_mask = 0
	
	EventBus.dirt_cleaned.emit(reward_rubles, global_position)
	
	# Плавное схлопывание
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.1)
	tween.tween_callback(queue_free)
