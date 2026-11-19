class_name TrashBin
extends StaticBody3D

## Советский мусорный контейнер.
## Принимает выброшенный мусор, утилизирует его и начисляет советские рубли.

@onready var deposit_area: Area3D = $DepositArea

func _ready() -> void:
	add_to_group("trash_bin")
	if deposit_area:
		deposit_area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body is CarryableTrash:
		var trash = body as CarryableTrash
		if not trash.is_carried:
			trash.deposit_into_bin()
			_play_deposit_effect()

func deposit_direct(trash: CarryableTrash) -> void:
	if trash:
		trash.deposit_into_bin()
		_play_deposit_effect()

func _play_deposit_effect() -> void:
	# Легкая анимация покачивания контейнера при попадании мусора
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(1.05, 0.95, 1.05), 0.1)
	tween.tween_property(self, "scale", Vector3.ONE, 0.15)
