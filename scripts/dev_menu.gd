extends Control

@export var settings: Resource
@onready var map_node = get_node("/root/Game/Map")

@onready var DivisionMenu = get_node("/root/Game/CanvasLayer/DivisionMenu")
@onready var ProvinceMenu = get_node("/root/Game/CanvasLayer/ProvinceMenu")
@onready var left_country: OptionButton = $Panel/VBoxContainer/HBoxContainer/LeftCountry
@onready var right_country: OptionButton = $Panel/VBoxContainer/HBoxContainer/RightCountry
@onready var balance_label = get_node_or_null("/root/Game/CanvasLayer/TopMenu/TopPanel/BalanceLabel")

var countries: Array = []

func _ready():
    for country in ProvinceRegistry.countries_data:
        countries.append(country)

    # Заполняем оба списка странами при старте
    for country in countries:
        left_country.add_item(country)
        right_country.add_item(country)
    
    # По умолчанию выберем разные страны, чтобы не воевать с самим собой
    left_country.selected = 0
    right_country.selected = 1

func _input(event: InputEvent):
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_INSERT:
            visible = not visible
    
    if not event is InputEventMouseButton or event.pressed:
        return

    if get_viewport().gui_get_hovered_control() != null:
        return

var _province_id: int = -1
var _local_pos: Vector2 = Vector2.ZERO

func _on_dev_recruit_button_pressed() -> void:
    _province_id = settings.last_clicked_province_id
    _local_pos = settings.local_mouse
    
    if _province_id == -1:
        return
        
    var p_data = ProvinceRegistry.province_data[str(_province_id)]
    var owner = p_data.get("owner", "")
    
    # Дебаг-логика: добавим денег, чтобы призыв точно сработал
    ProvinceRegistry.countries_data[owner]["balance"] += p_data.get("recruite_cost", 1000)
    
    # Определим количество для призыва (например, берем 1% населения, как и в игре)
    var pop = p_data.get("population", 0)
    var amount = int(pop * 0.01)
    
    # Если населения мало, призываем хотя бы 100 (минимальный порог)
    if amount < 100:
        amount = 100
    
    # Теперь передаем 3 аргумента
    DivisionManager.recruit(_province_id, _local_pos, amount)
    
    update_army_info()
    
func update_army_info():
    if not settings.can_draw:
        return
    var p_data = ProvinceRegistry.province_data.get(str(settings.last_clicked_province_id), {})
    ProvinceMenu.update_info(p_data)
    DivisionMenu.update_info(p_data)


func _on_war_button_pressed() -> void:
    if not settings.can_draw:
        return
    var country_a = left_country.get_item_text(left_country.selected)
    var country_b = right_country.get_item_text(right_country.selected)
    
    if country_a == country_b:
        print("You can't declare war on yourself!")
    else:
        ProvinceRegistry.declare_war(country_a, country_b)


func _on_increase_money_pressed() -> void:
    if not settings.can_draw:
        return
    var country_data = ProvinceRegistry.countries_data[settings.active_country]
    country_data["balance"] = country_data.get("balance", 0.0) + 1000000000
    balance_label.balance_update()


func _on_all_div_selectable_toggled(toggled_on: bool) -> void:
    if toggled_on:
        settings.can_select = true
    else:
        settings.can_select = false
