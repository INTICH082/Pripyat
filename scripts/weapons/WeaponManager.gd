class_name WeaponManager
extends Node3D

## Менеджер арсенала ликвидатора (13 видов оружия).
## Управляет FPS-ригом (cleaner_fps.glb), боезапасом, стрельбой,
## отдачей, процедурными и ключевыми анимациями первого лица.

@export var camera: Camera3D
@export var fps_viewmodel: Node3D

var weapons: Array[WeaponData] = []
var current_index: int = 0
var last_weapon_index: int = 1
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
var is_attacking: bool = false

# FPS-компоненты
var fps_anim_player: AnimationPlayer = null
var fps_skeleton: Skeleton3D = null
var weapon_mesh_nodes: Dictionary = {}
var magazine_nodes: Dictionary = {}
var muzzle_fx_node: Node3D = null

# Анимации ударов кулаками
var fist_strike_index: int = 0
const FIST_ANIMS: Array[String] = ["01_fists_Jab", "01_fists_Cross", "01_fists_Strike"]

func _ready() -> void:
	_init_fps_viewmodel()
	_load_weapon_resources()
	if weapons.size() > 0:
		_equip_weapon(0)

func _init_fps_viewmodel() -> void:
	if not fps_viewmodel:
		return
		
	# Отключаем тени у FPS-рук, чтобы тень отбрасывало только тело CleanerModel
	_set_shadows_off(fps_viewmodel)
	
	fps_anim_player = _find_node_of_type(fps_viewmodel, "AnimationPlayer") as AnimationPlayer
	if fps_anim_player:
		fps_anim_player.animation_finished.connect(_on_animation_finished)
		
	fps_skeleton = _find_node_of_type(fps_viewmodel, "Skeleton3D") as Skeleton3D
		
	# Кэшируем узлы мешей оружия
	var weapon_ids = [
		"02_crowbar", "03_spade", "04_fire_axe",
		"05_pistol_pl", "06_pistol_pt", "07_rifle_al", "08_rifle_at",
		"09_rifle_vl", "10_rifle_vt", "11_rpk", "12_flamya_1", "13_launcher_gm"
	]
	for wid in weapon_ids:
		var node = fps_viewmodel.find_child(wid, true, false)
		if node and node is Node3D:
			weapon_mesh_nodes[wid] = node
			
	var mag5 = fps_viewmodel.find_child("Magazine_5", true, false)
	if mag5 and mag5 is Node3D: magazine_nodes["05_pistol_pl"] = mag5
	
	var mag6 = fps_viewmodel.find_child("Magazine_6", true, false)
	if mag6 and mag6 is Node3D: magazine_nodes["06_pistol_pt"] = mag6
	
	muzzle_fx_node = fps_viewmodel.find_child("Muzzle_FX", true, false) as Node3D
	if muzzle_fx_node:
		muzzle_fx_node.visible = false

func _find_node_of_type(root: Node, type_name: String) -> Node:
	if not root:
		return null
	if root.is_class(type_name):
		return root
	for child in root.get_children():
		var found = _find_node_of_type(child, type_name)
		if found:
			return found
	return null

func _set_shadows_off(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_set_shadows_off(child)

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
	if current_index > 0:
		last_weapon_index = current_index
		
	is_reloading = false
	is_attacking = false
	can_fire = true
	
	_update_weapon_mesh_visibility()
	_update_fps_skeleton_bones()
	_play_fps_anim(current_weapon.id + "_Idle-loop", 0.0, true)
	_notify_hud()

func equip_fists() -> void:
	if weapons.size() > 0:
		_equip_weapon(0)

func restore_current_weapon() -> void:
	if current_index == 0:
		var target_idx = last_weapon_index if last_weapon_index < weapons.size() else 1
		_equip_weapon(target_idx)
	else:
		_equip_weapon(current_index)

func set_tool_mode_hands(is_free_hands: bool) -> void:
	set_viewmodel_visible(is_free_hands)
	if is_free_hands:
		equip_fists()

func set_tool_mode_brush() -> void:
	set_viewmodel_visible(false)

func set_tool_mode_weapon() -> void:
	set_viewmodel_visible(true)
	restore_current_weapon()

func set_viewmodel_visible(is_vis: bool) -> void:
	if fps_viewmodel:
		fps_viewmodel.visible = is_vis

func _update_weapon_mesh_visibility() -> void:
	if not current_weapon:
		return
	var active_id = current_weapon.id
	
	# Показываем только меш выбранного оружия
	for wid in weapon_mesh_nodes:
		var m_node: Node3D = weapon_mesh_nodes[wid]
		m_node.visible = (wid == active_id)
		
	if magazine_nodes.has("05_pistol_pl"):
		magazine_nodes["05_pistol_pl"].visible = (active_id == "05_pistol_pl")
	if magazine_nodes.has("06_pistol_pt"):
		magazine_nodes["06_pistol_pt"].visible = (active_id == "06_pistol_pt")

func _update_fps_skeleton_bones() -> void:
	if not fps_skeleton or not current_weapon:
		return
	var active_bone = ""
	if current_weapon.id != "01_fists":
		active_bone = "W" + current_weapon.id.substr(0, 2)
		
	for i in range(2, 14):
		var b_name = "W%02d" % i
		var b_idx = fps_skeleton.find_bone(b_name)
		if b_idx != -1:
			if b_name == active_bone:
				fps_skeleton.set_bone_pose_scale(b_idx, Vector3(1.0, 1.0, 1.0))
			else:
				fps_skeleton.set_bone_pose_scale(b_idx, Vector3(0.001, 0.001, 0.001))

func _resolve_fps_anim_name(suffix: String) -> String:
	if not fps_anim_player:
		return ""
	if fps_anim_player.has_animation(suffix):
		return suffix
	for a in fps_anim_player.get_animation_list():
		if a == suffix or a.ends_with("/" + suffix) or a.ends_with(":" + suffix):
			return a
	return ""

func _play_fps_anim(anim_name: String, blend_time: float = 0.15, restart: bool = false) -> void:
	if not fps_anim_player:
		return
	var full_name = _resolve_fps_anim_name(anim_name)
	if full_name != "":
		if restart:
			fps_anim_player.stop()
			fps_anim_player.play(full_name, 0.0)
		elif fps_anim_player.current_animation != full_name:
			fps_anim_player.play(full_name, blend_time)

func update_movement_animation(flat_speed: float, is_sprinting: bool, is_crouching: bool = false, is_in_air: bool = false) -> void:
	if is_attacking or is_reloading or not current_weapon or not fps_anim_player:
		return
		
	var wid = current_weapon.id
	if is_in_air:
		fps_anim_player.speed_scale = 1.0
		_play_fps_anim(wid + "_Idle-loop", 0.3)
	elif is_sprinting and flat_speed > 4.0:
		fps_anim_player.speed_scale = 1.0
		_play_fps_anim(wid + "_Run-loop", 0.2)
	elif flat_speed > 0.2:
		fps_anim_player.speed_scale = 0.6 if is_crouching else 1.0
		_play_fps_anim(wid + "_Walk-loop", 0.2)
	else:
		fps_anim_player.speed_scale = 1.0
		_play_fps_anim(wid + "_Idle-loop", 0.2)

func _return_to_movement_anim() -> void:
	if not current_weapon:
		return
	var wid = current_weapon.id
	_play_fps_anim(wid + "_Idle-loop", 0.15)

func _on_animation_finished(anim_name: String) -> void:
	if is_reloading and anim_name.ends_with("_Reload"):
		_finish_reload()
		is_reloading = false
		can_fire = true
		_return_to_movement_anim()
	elif is_attacking:
		is_attacking = false
		_return_to_movement_anim()

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
	# Переключаемся только между боевым оружием (1..12), 0 оставляем для кулаков
	var next_idx = current_index + 1
	if next_idx >= weapons.size():
		next_idx = 1
	_equip_weapon(next_idx)

func prev_weapon() -> void:
	if weapons.size() <= 1:
		return
	var prev_idx = current_index - 1
	if prev_idx < 1:
		prev_idx = weapons.size() - 1
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
	is_attacking = true
	var wid = current_weapon.id
	var delay = 60.0 / max(1.0, current_weapon.fire_rate)
	
	var strike_anim = wid + "_Strike"
	if wid == "01_fists":
		strike_anim = FIST_ANIMS[fist_strike_index % FIST_ANIMS.size()]
		fist_strike_index += 1
		
	if fps_anim_player:
		fps_anim_player.speed_scale = 1.0
	_play_fps_anim(strike_anim, 0.0, true)
	
	# Raycast удара
	var result = _raycast_attack(current_weapon.effective_range)
	if result:
		_apply_hit(result, current_weapon.damage)
		
	await get_tree().create_timer(delay).timeout
	can_fire = true
	is_attacking = false
	_return_to_movement_anim()

func _perform_firearm_attack() -> void:
	var cur_ammo = current_mags.get(current_weapon.id, 0)
	if cur_ammo <= 0:
		reload()
		return
		
	can_fire = false
	is_attacking = true
	var wid = current_weapon.id
	var delay = 60.0 / max(1.0, current_weapon.fire_rate)
	if fps_anim_player:
		fps_anim_player.speed_scale = 1.0
	
	if current_weapon.is_burst:
		# Режим Абакана (отсечка по 2 патрона с темпом 1800 выстр/мин)
		for b in range(current_weapon.burst_count):
			if current_mags[wid] > 0:
				current_mags[wid] -= 1
				_play_fps_anim(wid + "_Fire", 0.0, true)
				_fire_single_shot()
				_notify_hud()
			await get_tree().create_timer(0.033).timeout
	else:
		current_mags[wid] -= 1
		_play_fps_anim(wid + "_Fire", 0.0, true)
		_fire_single_shot()
		_notify_hud()
		
	await get_tree().create_timer(delay).timeout
	can_fire = true
	is_attacking = false
	_return_to_movement_anim()

func _fire_single_shot() -> void:
	_flash_muzzle()
	_apply_camera_recoil()
	
	var result = _raycast_attack(current_weapon.effective_range)
	if result:
		_apply_hit(result, current_weapon.damage)

func _perform_flame_attack() -> void:
	var cur_fuel = current_mags.get(current_weapon.id, 0)
	if cur_fuel <= 0:
		reload()
		return
		
	can_fire = false
	is_attacking = true
	var wid = current_weapon.id
	if fps_anim_player:
		fps_anim_player.speed_scale = 1.0
	
	current_mags[wid] -= 1
	_notify_hud()
	
	_play_fps_anim(wid + "_Fire", 0.05, false)
	_apply_camera_recoil(0.2)
	
	# Огненная струя
	var result = _raycast_attack(current_weapon.effective_range)
	if result:
		_apply_hit(result, current_weapon.damage * 0.2)
		if result.collider is DirtSpot:
			(result.collider as DirtSpot).scrub(0.5)
			
	await get_tree().create_timer(0.08).timeout
	can_fire = true
	is_attacking = false

func _perform_explosive_attack() -> void:
	var cur_ammo = current_mags.get(current_weapon.id, 0)
	if cur_ammo <= 0:
		reload()
		return
		
	can_fire = false
	is_attacking = true
	var wid = current_weapon.id
	if fps_anim_player:
		fps_anim_player.speed_scale = 1.0
	
	current_mags[wid] -= 1
	_notify_hud()
	
	_play_fps_anim(wid + "_Fire", 0.0, true)
	_flash_muzzle()
	_apply_camera_recoil(1.5)
	
	var delay = 60.0 / max(1.0, current_weapon.fire_rate)
	var result = _raycast_attack(current_weapon.effective_range)
	if result:
		_create_explosion(result.position)
		
	await get_tree().create_timer(delay).timeout
	can_fire = true
	is_attacking = false
	_return_to_movement_anim()

func _create_explosion(hit_center: Vector3) -> void:
	var radius = current_weapon.splash_radius
	var dmg = current_weapon.damage
	
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
	
	# Исключаем тело самого игрока, чтобы можно было без ограничений стрелять вертикально вниз (в пол/под ноги)
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node:
		var rids: Array[RID] = []
		if player_node is CollisionObject3D:
			rids.append((player_node as CollisionObject3D).get_rid())
		for child in player_node.find_children("*", "CollisionObject3D", true, false):
			rids.append((child as CollisionObject3D).get_rid())
		query.exclude = rids
	
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
	if is_reloading or not current_weapon or current_weapon.is_melee:
		return
		
	var wid = current_weapon.id
	var needed = current_weapon.mag_capacity - current_mags.get(wid, 0)
	var reserve = ammo_reserves.get(current_weapon.ammo_type, 0)
	
	if needed <= 0 or reserve <= 0:
		return
		
	is_reloading = true
	can_fire = false
	
	var reload_anim = wid + "_Reload"
	var resolved_reload = _resolve_fps_anim_name(reload_anim)
	if resolved_reload != "":
		_play_fps_anim(reload_anim, 0.1)
	else:
		await get_tree().create_timer(current_weapon.reload_time).timeout
		_finish_reload()
		is_reloading = false
		can_fire = true
		_return_to_movement_anim()

func _finish_reload() -> void:
	if not current_weapon:
		return
	var wid = current_weapon.id
	var needed = current_weapon.mag_capacity - current_mags.get(wid, 0)
	var reserve = ammo_reserves.get(current_weapon.ammo_type, 0)
	
	var to_load = mini(needed, reserve)
	current_mags[wid] += to_load
	ammo_reserves[current_weapon.ammo_type] -= to_load
	_notify_hud()

func _flash_muzzle() -> void:
	if muzzle_fx_node:
		muzzle_fx_node.visible = true
		var t = create_tween()
		t.tween_interval(0.04)
		t.tween_callback(func(): if muzzle_fx_node: muzzle_fx_node.visible = false)

func _apply_camera_recoil(mult: float = 1.0) -> void:
	if not camera or not current_weapon:
		return
	var r = current_weapon.recoil if ("recoil" in current_weapon and current_weapon.recoil != null) else 1.0
	var kick = deg_to_rad(r * 0.2 * mult)
	camera.rotation.x = clamp(camera.rotation.x + kick, deg_to_rad(-85.0), deg_to_rad(85.0))
