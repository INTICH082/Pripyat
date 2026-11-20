class_name WeaponManager
extends Node3D

## Менеджер арсенала ликвидатора (13 видов оружия).
## Управляет переключением, боезапасом, стрельбой, ударами ближнего боя,
## огнемётом и взрывными эффектами гранатомета.

@export var camera: Camera3D
@export var weapon_mount: Node3D

var weapons: Array[WeaponData] = []
var current_index: int = 0
var current_weapon: WeaponData = null

# Боезапас
var current_mags: Dictionary = {}
var ammo_reserves: Dictionary = {
	"9x18": 48,
	"7.62x25": 32,
	"5.45x39": 120,
	".22LR": 25,
	"7.62x54R": 15,
	"7.62x39": 120,
	"fuel": 200,
	"vog25": 12
}

var can_fire: bool = true
var is_reloading: bool = false
var current_model_instance: Node3D = null

func _ready() -> void:
	_load_weapon_resources()
	if weapons.size() > 0:
		_equip_weapon(0)

func _load_weapon_resources() -> void:
	var files = [
		"01_fists.tres", "02_crowbar.tres", "03_spade.tres", "04_fire_axe.tres",
		"05_pistol_pl.tres", "06_pistol_pt.tres", "07_rifle_al.tres", "08_rifle_at.tres",
		"09_rifle_vl.tres", "10_rifle_vt.tres", "11_rpk.tres", "12_flamya_1.tres",
		"13_launcher_gm.tres"
	]
	
	for f in files:
		var path = "res://resources/weapons/" + f
		if ResourceLoader.exists(path):
			var w = ResourceLoader.load(path) as WeaponData
			if w:
				weapons.append(w)
				current_mags[w.id] = w.mag_capacity

func _equip_weapon(index: int) -> void:
	if index < 0 or index >= weapons.size():
		return
		
	current_index = index
	current_weapon = weapons[current_index]
	is_reloading = false
	can_fire = true
	
	_spawn_weapon_model()
	_notify_hud()

func _spawn_weapon_model() -> void:
	if current_model_instance:
		current_model_instance.queue_free()
		current_model_instance = null
		
	if not current_weapon or not weapon_mount:
		return
		
	if ResourceLoader.exists(current_weapon.model_path):
		var scene = ResourceLoader.load(current_weapon.model_path)
		if scene is PackedScene:
			current_model_instance = scene.instantiate() as Node3D
			weapon_mount.add_child(current_model_instance)
			
			# Начальное смещение модели оружия для правильного вида от 1-го лица
			current_model_instance.position = Vector3(0.24, -0.25, -0.45)
			current_model_instance.rotation_degrees = Vector3(0, 180, 0)
			
			# Анимация доставания (смещение снизу вверх)
			var start_y = current_model_instance.position.y - 0.2
			current_model_instance.position.y = start_y
			var tween = create_tween()
			tween.tween_property(current_model_instance, "position:y", -0.25, 0.15)

func _notify_hud() -> void:
	if not current_weapon:
		return
	var mag = current_mags.get(current_weapon.id, 0)
	var res = ammo_reserves.get(current_weapon.ammo_type, 0) if not current_weapon.is_melee else 0
	EventBus.weapon_switched.emit(current_weapon, mag, res)
	EventBus.weapon_ammo_changed.emit(mag, res)

func next_weapon() -> void:
	if weapons.size() <= 1:
		return
	var next_idx = (current_index + 1) % weapons.size()
	_equip_weapon(next_idx)

func prev_weapon() -> void:
	if weapons.size() <= 1:
		return
	var prev_idx = (current_index - 1 + weapons.size()) % weapons.size()
	_equip_weapon(prev_idx)

func primary_attack() -> void:
	if not current_weapon or not can_fire or is_reloading:
		return
		
	if current_weapon.is_melee:
		_perform_melee_attack()
	elif current_weapon.is_flamethrower:
		_perform_flame_attack()
	elif current_weapon.is_explosive:
		_perform_explosive_attack()
	else:
		_perform_firearm_attack()

func _perform_melee_attack() -> void:
	can_fire = false
	var delay = 60.0 / max(1.0, current_weapon.fire_rate)
	
	_animate_attack_kick(Vector3(0.05, 0.05, -0.1), Vector3(-15, 10, -5), delay * 0.4)
	
	# Raycast удара
	var result = _raycast_attack(current_weapon.effective_range)
	if result:
		_apply_hit(result, current_weapon.damage)
		
	await get_tree().create_timer(delay).timeout
	can_fire = true

func _perform_firearm_attack() -> void:
	var cur_ammo = current_mags.get(current_weapon.id, 0)
	if cur_ammo <= 0:
		reload()
		return
		
	can_fire = false
	var delay = 60.0 / max(1.0, current_weapon.fire_rate)
	
	if current_weapon.is_burst:
		# Режим Абакана (отсечка по 2 патрона)
		for b in range(current_weapon.burst_count):
			if current_mags[current_weapon.id] > 0:
				current_mags[current_weapon.id] -= 1
				_fire_single_shot()
				_notify_hud()
			await get_tree().create_timer(0.04).timeout
	else:
		current_mags[current_weapon.id] -= 1
		_fire_single_shot()
		_notify_hud()
		
	await get_tree().create_timer(delay).timeout
	can_fire = true

func _fire_single_shot() -> void:
	_animate_attack_kick(Vector3(0, 0.02, 0.08), Vector3(-8, 0, 0), 0.08)
	var result = _raycast_attack(current_weapon.effective_range)
	if result:
		_apply_hit(result, current_weapon.damage)

func _perform_flame_attack() -> void:
	var cur_fuel = current_mags.get(current_weapon.id, 0)
	if cur_fuel <= 0:
		reload()
		return
		
	can_fire = false
	current_mags[current_weapon.id] -= 1
	_notify_hud()
	
	_animate_attack_kick(Vector3(0, 0.005, 0.01), Vector3(-2, 0, 0), 0.06)
	
	# Огненный конус
	var result = _raycast_attack(current_weapon.effective_range)
	if result:
		_apply_hit(result, current_weapon.damage * 0.2)
		
		# Огнемёт моментально выжигает сорняки и грязь!
		if result.collider is DirtSpot:
			var spot = result.collider as DirtSpot
			spot.scrub(0.5)
			
	await get_tree().create_timer(0.08).timeout
	can_fire = true

func _perform_explosive_attack() -> void:
	var cur_ammo = current_mags.get(current_weapon.id, 0)
	if cur_ammo <= 0:
		reload()
		return
		
	can_fire = false
	current_mags[current_weapon.id] -= 1
	_notify_hud()
	
	var delay = 60.0 / max(1.0, current_weapon.fire_rate)
	_animate_attack_kick(Vector3(0, 0.06, 0.18), Vector3(-20, 0, 0), 0.15)
	
	var result = _raycast_attack(current_weapon.effective_range)
	if result:
		_create_explosion(result.position)
		
	await get_tree().create_timer(delay).timeout
	can_fire = true

func _create_explosion(hit_center: Vector3) -> void:
	var radius = current_weapon.splash_radius
	var dmg = current_weapon.damage
	
	# Поиск тел в радиусе взрыва
	var space_state = get_world_3d().direct_space_state
	var shape = SphereShape3D.new()
	shape.radius = radius
	
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = hit_center
	query.collision_mask = 1 | 2
	
	var hits = space_state.intersect_shape(query, 32)
	for hit in hits:
		var col = hit.collider
		if col and col is Node3D:
			var dist = hit_center.distance_to(col.global_position)
			var falloff = clampf(1.0 - (dist / radius), 0.1, 1.0)
			
			if col.has_method("take_damage"):
				col.take_damage(dmg * falloff, current_weapon)
			elif col is RigidBody3D:
				var dir = (col.global_position - hit_center).normalized()
				col.apply_central_impulse(dir * (dmg * 0.4 * falloff))

func _raycast_attack(range_dist: float) -> Dictionary:
	if not camera:
		return {}
	var space_state = get_world_3d().direct_space_state
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * range_dist)
	
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = 1 | 2
	
	return space_state.intersect_ray(query)

func _apply_hit(ray_result: Dictionary, damage_amount: float) -> void:
	var col = ray_result.collider
	var pos = ray_result.position
	
	if col.has_method("take_damage"):
		col.take_damage(damage_amount, current_weapon)
		EventBus.enemy_hit.emit(col, damage_amount, pos)
	elif col is RigidBody3D:
		var impulse_dir = -camera.global_transform.basis.z
		col.apply_central_impulse(impulse_dir * (damage_amount * 0.15))
	elif col is DirtSpot and (current_weapon.can_dig or current_weapon.can_burn_weeds):
		(col as DirtSpot).scrub(0.3)

func reload() -> void:
	if is_reloading or current_weapon.is_melee:
		return
		
	var needed = current_weapon.mag_capacity - current_mags.get(current_weapon.id, 0)
	var reserve = ammo_reserves.get(current_weapon.ammo_type, 0)
	
	if needed <= 0 or reserve <= 0:
		return
		
	is_reloading = true
	can_fire = false
	
	# Анимация ухода оружия вниз во время перезарядки
	if current_model_instance:
		var tween = create_tween()
		tween.tween_property(current_model_instance, "position:y", -0.5, current_weapon.reload_time * 0.4)
		tween.tween_property(current_model_instance, "position:y", -0.25, current_weapon.reload_time * 0.6)
		
	await get_tree().create_timer(current_weapon.reload_time).timeout
	
	var to_load = mini(needed, reserve)
	current_mags[current_weapon.id] += to_load
	ammo_reserves[current_weapon.ammo_type] -= to_load
	
	is_reloading = false
	can_fire = true
	_notify_hud()

func _animate_attack_kick(recoil_pos: Vector3, recoil_rot: Vector3, return_time: float) -> void:
	if not current_model_instance:
		return
	var base_pos = Vector3(0.24, -0.25, -0.45)
	var base_rot = Vector3(0, 180, 0)
	
	var tween = create_tween()
	tween.tween_property(current_model_instance, "position", base_pos + recoil_pos, 0.04)
	tween.parallel().tween_property(current_model_instance, "rotation_degrees", base_rot + recoil_rot, 0.04)
	tween.tween_property(current_model_instance, "position", base_pos, return_time)
	tween.parallel().tween_property(current_model_instance, "rotation_degrees", base_rot, return_time)
