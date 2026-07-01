extends RichTextLabel

@export var settings: Resource
@onready var sell_menu = $%SellMenu
@onready var sell_input = $%SellMenu/SellInput

func _ready() -> void:
	sell_menu.hide()

func _process(_delta: float) -> void:
	var c_data = ProvinceRegistry.countries_data.get(settings.active_country, {})
	var products = c_data.get("products", 0.0)
	
	var monthly_prod = 0
	for key in ProvinceRegistry.province_data:
		var p = ProvinceRegistry.province_data[key]
		if p.get("owner", "") == settings.active_country and p.get("against_occupation", "") == "":
			monthly_prod += p.get("factories", 0)
			
	# Большой текст продукта и серый мелкий текст производства
	text = "📦 %d [color=#888888][font_size=12]+%d/m[/font_size][/color]" % [int(products), monthly_prod]

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		sell_menu.visible = !sell_menu.visible

# Сигнал от кнопки "Продать"
func _on_sell_button_pressed() -> void:
	_execute_sale(float(sell_input.value))

# Сигнал от кнопки "Продать всё"
func _on_sell_all_button_pressed() -> void:
	var c_data = ProvinceRegistry.countries_data.get(settings.active_country, {})
	_execute_sale(c_data.get("products", 0.0))

func _execute_sale(amount: float) -> void:
	var c_data = ProvinceRegistry.countries_data.get(settings.active_country, {})
	var current_stock = c_data.get("products", 0.0)
	
	amount = clamp(amount, 0.0, current_stock)
	
	if amount > 0:
		c_data["products"] -= amount
		c_data["balance"] = c_data.get("balance", 0.0) + (amount * settings.product_cost)
		
	sell_input.value = 0
	sell_menu.hide()
