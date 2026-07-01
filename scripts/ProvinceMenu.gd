extends Control

@export var settings: Resource

@onready var owner_label = $Panel/VBoxContainer/OwnerLabel
@onready var name_label  = $Panel/VBoxContainer/NameLabel
@onready var population_label = $Panel/VBoxContainer/PopulationLabel
@onready var factories_label = $Panel/VBoxContainer/FactoriesLabel
@onready var recruit_btn = $Panel/RecruitButton
@onready var build_factory_btn = $Panel/BuildFactoryButton

func _ready():
	$Panel.add_to_group("ProvincePanel")
	GameClock.on_day_passed.connect(_on_day_passed)
	hide()

var current_province_id: int = -1

func _on_day_passed(_date: Dictionary) -> void:
	if visible and settings.last_clicked_province_id != -1:
		var data = ProvinceRegistry.province_data.get(str(settings.last_clicked_province_id), {})
		update_info(data)

func update_info(data: Dictionary):
	if data.has("id"):
		current_province_id = int(data["id"])
	var owner_name = data.get("owner", "unknown")
	owner_label.text = "Owner" + ": " + owner_name
	name_label.text  = "Province" + ": " + data.get("name", "unknown")
	population_label.text = "Population" + " 👥: " + _format_population(int(data.get("population", 0)))
	factories_label.text = "Factories" + " 🏭: " + str(data.get("factories", 0))
	var flag_path = "res://assets/flags/" + owner_name + ".png"
	recruit_btn.visible = owner_name == settings.active_country and data.get("against_occupation", "") == ""
	build_factory_btn.visible = owner_name == settings.active_country and data.get("against_occupation", "") == ""
	var style = StyleBoxTexture.new()
	style.texture = load(flag_path)

func _format_population(n: int) -> String:
	var s = str(n)
	var result = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		result = s[i] + result
		count += 1
		if count % 3 == 0 and i != 0:
			result = " " + result
	return result


func _on_build_factory_button_pressed() -> void:
	var p_id = settings.last_clicked_province_id
	var p_data = ProvinceRegistry.province_data.get(str(p_id), {})

	# Проверяем, не оккупирована ли провинция
	if p_data.get("against_occupation", "") != "":
		print("Нельзя строить в оккупированной провинции!")
		return

	# Запускаем строительство
	var success = ProvinceRegistry.start_factory_construction(p_id, settings.active_country)
	if success:
		print("Строительство завода началось!")
	else:
		print("Недостаточно денег (нужно 1 000 000 💵)!")
