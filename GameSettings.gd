extends Resource
class_name GameSettings
@export var province_centers: Dictionary = {}

## Уровни сложности. EASY — скидка 25%, HARD — наценка 25%, HARDCORE — наценка
## 50% и запрет сохранений; STANDARD — обычные цены.
enum Difficulty { EASY, STANDARD, HARD, HARDCORE }
var difficulty: Difficulty = Difficulty.STANDARD

## Множитель стоимости построек/призыва войск для игрока в зависимости
## от сложности: EASY — дешевле на 25%, HARD — дороже на 25%.
func get_cost_multiplier() -> float:
    match difficulty:
        Difficulty.EASY:
            return 0.75
        Difficulty.HARD:
            return 1.25
        Difficulty.HARDCORE:
            return 1.5
        _:
            return 1.0

## Стоимость призыва одного солдата с учётом сложности (используется только
## для игрока — соответствующий UI доступен исключительно ему).
func get_recruit_cost_per_soldier() -> float:
    return COST_PER_SOLDIER * get_cost_multiplier()

## На лёгкой сложности мировые санкции (__WORLD__) не накладываются на игрока.
func is_world_sanctions_disabled() -> bool:
    return difficulty == Difficulty.EASY

## На хардкоре сохранение игры недоступно (ни ручное, ни авто-).
func is_saving_disabled() -> bool:
    return difficulty == Difficulty.HARDCORE


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
var FORTIFICATION_COST: int = 50_000_000
var TIME_FORTIFICATION: int = 10
var HAPPINESS_DRAIN_PER_1K_RECRUITS: float = 0.01
## Прирост населения провинции после постройки фабрики (доля от текущего населения провинции, 0.05 = +5%).
var FACTORY_POPULATION_BONUS: float = 0.05
