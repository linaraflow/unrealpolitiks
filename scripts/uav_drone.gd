extends Sprite2D

var settings = preload("res://new_resource.tres")

var target_pos: Vector2
var target_p_id: int
var amount: int = 1 # Системное количество дронов в этой текстуре
var attacker_country: String = "" # Страна, запустившая удар (для начисления продукта за уничтоженные фабрики)
var base_speed: float = settings.UAV_SPEED

func _ready() -> void:
    texture = preload("res://assets/icons_uav_menu/uav_main.png")
    var tex_size = texture.get_size()
    scale = Vector2(20.0 / tex_size.x, 20.0 / tex_size.y)
    
    var dir = (target_pos - position).normalized()
    rotation = dir.angle() + (PI / 2.0)

func _process(delta: float) -> void:
    if GameClock.paused or GameClock.speed_index == 0:
        return
        
    var current_speed = base_speed * GameClock.SPEEDS[GameClock.speed_index]
    var move_dist = current_speed * delta
    
    if position.distance_to(target_pos) <= move_dist:
        _arrive()
    else:
        position = position.move_toward(target_pos, move_dist)

func _arrive() -> void:
    # Передаем системное количество урона в провинцию + страну-атакующего для награды продуктом
    ProvinceRegistry.destroy_factory(target_p_id, amount, attacker_country)
    queue_free()
