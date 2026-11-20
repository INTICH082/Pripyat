class_name WeaponData
extends Resource

## Описание параметров оружия в соответствии с Game Design Document

@export var id: String = "01_fists"
@export var display_name: String = "Кулаки"
@export_enum("Ближний бой", "Пистолет", "Автомат", "Винтовка", "Пулемет", "Огнемёт", "Гранатомет") var category: String = "Ближний бой"

@export var damage: float = 12.0
@export var fire_rate: float = 85.0 ## Темп огня / ударов (в минуту)
@export var mag_capacity: int = 0 ## Емкость магазина (0 для ближнего боя)
@export var reload_time: float = 0.0 ## Время перезарядки (в секундах)
@export var effective_range: float = 1.2 ## Эффективная дальность (в метрах)
@export var price_karbovantsi: int = 0
@export var ammo_type: String = "none" ## "none", "9x18", "7.62x25", "5.45x39", ".22LR", "7.62x54R", "7.62x39", "fuel", "vog25"

@export var is_melee: bool = true
@export var is_burst: bool = false
@export var burst_count: int = 2
@export var is_flamethrower: bool = false
@export var is_explosive: bool = false
@export var splash_radius: float = 0.0

@export_file("*.glb") var model_path: String = "res://assets/models/weapons/01_fists.glb"
@export_multiline var description: String = ""

# Двойное назначение (инструментальные свойства):
@export var can_break_wood: bool = false
@export var can_dig: bool = false
@export var can_open_locks: bool = false
@export var can_burn_weeds: bool = false
