extends Resource
class_name GameSettings
@export var province_centers: Dictionary = {}


var active_country: String = ""
var last_clicked_province_id: int = 0
var last_clicked_province_color: Color
var province_data: Dictionary
var can_draw: bool = false
var local_mouse: Vector2
#var province_centers: Dictionary
var is_mouse_over_ui: bool = false
var province_adjacency: Dictionary
var can_select: bool = false
var negotiation_mode: bool = false
var COST_PER_SOLDIER: float = 2000
var product_cost: int = 500000
var factory_cost: int = 50000000
var UAV_COMPANY_COST: int = 10000000
var uav_cost: int = 10   # ПРОДУКТЫ
var UAV_SPEED: float = 40.0
var KILLS_PER_DRONE: int = 100
var missile_cost: int = 100   # ПРОДУКТЫ
var MISSILE_COMPANY_COST: int = 100_000_000
var MISSILE_KILL_RATIO: float = 0.9
