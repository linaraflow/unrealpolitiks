extends Panel

@export var settings: Resource

@onready var CountryLabel = $CountryLabel
@onready var ProvincesLabel = $VBoxContainer1/ProvincesLabel
@onready var PopulationLabel = $VBoxContainer1/PopulationLabel
@onready var FactoriesLabel = $VBoxContainer1/FactoriesLabel

@onready var InfluenceLabel = $VBoxContainer2/InfluenceLabel
@onready var StabilityLabel = $VBoxContainer2/StabilityLabel

@onready var NegotiationBtn = $Negotiation
@onready var NegotiationMenu  = get_node("/root/Game/CanvasLayer/NegotiationMenu")

var owner_name

func _ready() -> void:
	NegotiationBtn.hide()
	hide()
	add_to_group("CountryMenuPanel")
	GameClock.on_day_passed.connect(_on_day_passed)

func _on_day_passed(_date: Dictionary) -> void:
	if visible:
		update_info()


func update_info():
	owner_name = ProvinceRegistry.province_data[str(settings.last_clicked_province_id)].get("owner", "unknown")
	var data = ProvinceRegistry.countries_data[owner_name]
	
	CountryLabel.text = owner_name
	ProvincesLabel.text = "Provinces: " + str(ProvinceRegistry.owner_province_count[owner_name])
	
	# Население с пробелами
	PopulationLabel.text = "Population 👥: " + ProvinceRegistry._format_number(ProvinceRegistry.get_country_population(owner_name), " ")
	
	# Считаем ВВП (теперь можно не оборачивать в int() вручную, функция сделает это сама)
	var GDP = (ProvinceRegistry.countries_data[owner_name].get("factories", 0) * settings.product_cost + data.get("monthly_income", 0)) * 12
	
	# ВВП с точками
	FactoriesLabel.text = "GDP: " + ProvinceRegistry._format_number(GDP, ".") + "$"
	
	InfluenceLabel.text = 'Influence 🌐: ' + str(ProvinceRegistry.countries_data[owner_name]['influence']) + '%'
	StabilityLabel.text = 'Stability 🛡️: ' + str(ProvinceRegistry.countries_data[owner_name]['stability']) + '%'
	
	if ProvinceRegistry.is_at_war(settings.active_country, owner_name):
		NegotiationBtn.show()
	else:
		NegotiationBtn.hide()

func _on_negotiation_pressed() -> void:
	NegotiationMenu.open_negotiation(owner_name)
