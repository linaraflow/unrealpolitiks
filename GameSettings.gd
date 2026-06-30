extends Resource
class_name GameSettings



var active_country: String = ""
var last_clicked_province_id: int = 0
var last_clicked_province_color: Color
var province_data: Dictionary
var can_draw: bool = false
var local_mouse: Vector2
var province_centers: Dictionary
var is_mouse_over_ui: bool = false
var province_adjacency: Dictionary
var can_select: bool = false
var negotiation_mode: bool = false
var COST_PER_SOLDIER: float = 2
