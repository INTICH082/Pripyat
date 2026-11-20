class_name EnemyData
extends Resource

## Ресурс описания характеристик облучённой фауны и биоугроз Чернобыльской зоны.
## Соответствует Разделу 2 Генерального документа игрового дизайна (GDD).

@export var id: String = "blind_dog"
@export var display_name: String = "Слепой пес"
@export var category: String = "Мутант" ## "Мутант", "Хищник", "Птица", "Насекомое", "Аномальный", "Человек"
@export var health: float = 65.0
@export var damage: float = 18.0
@export var run_speed: float = 6.5 ## в м/с
@export var reward_karbovantsi: int = 15

@export var habitat: String = "Дворы, проспекты, скверы"
@export_multiline var restoration_harm: String = "Нападают стаями по 3-5 особей; сбегаются на рев моторов и мойки."
@export_multiline var description: String = ""

# Особенности поведения
@export var is_flying: bool = false
@export var is_boss: bool = false
@export var is_pack_hunter: bool = true
@export var attracts_to_noise: bool = true
@export var breaks_restored_objects: bool = false
@export var causes_bleeding: bool = false
@export var has_ranged_attack: bool = false
@export var has_psi_aura: bool = false
@export var can_burrow: bool = false
