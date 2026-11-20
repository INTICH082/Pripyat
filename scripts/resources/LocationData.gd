class_name LocationData
extends Resource

## Ресурс описания района города Припять и прилегающих секторов Зоны.
## Соответствует Разделу 5 Генерального документа игрового дизайна (GDD).

@export var id: String = "microdistrict_1"
@export var index: int = 2
@export var display_name: String = "1-й Микрорайон Припяти"
@export var subtitle: String = "Городской сектор"
@export var radiation_level: String = "Низкий / Средний" ## "Низкий", "Средний", "Высокий", "Смертельный (>100 Р/ч)"
@export_multiline var landscape: String = "Дворы-колодцы, пятиэтажные хрущевки, детские площадки, подъезды."

@export var tasks: Array[String] = [
	"Уборка бытового мусора",
	"Соскабливание мха с асфальта",
	"Остекление первых этажей"
]

@export var threats: Array[String] = [
	"Слепые псы",
	"Радиоактивные крысы",
	"Чернобыльские вороны"
]

@export var available_hubs: Array[String] = [
	"Штаб Ликвидации",
	"Магазин «Хозтовары»"
]

@export_file("*.tscn") var scene_path: String = "res://scenes/world/SosnovkaVillage.tscn"
@export var is_unlocked: bool = true
