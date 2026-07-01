extends Control

var settings = preload("res://new_resource.tres")

@onready var flag_button: Button = $TopPanel/Flag

func _ready() -> void:
	hide()


func update(country):
	var texture = load("res://assets/flags/" + str(country) + ".png")
	
	# Создаем новый текстурный стиль
	var new_style = StyleBoxTexture.new()
	new_style.texture = texture
	
	# Режим растягивания: игнорировать пропорции и заполнить всё пространство
	new_style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	new_style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	
	# Применяем этот стиль для разных состояний
	flag_button.add_theme_stylebox_override("normal", new_style)
	flag_button.add_theme_stylebox_override("hover", new_style)
	flag_button.add_theme_stylebox_override("pressed", new_style)

func _on_flag_mouse_entered() -> void:
	flag_button.modulate = Color(0.7, 0.7, 0.7)  # темнее


func _on_flag_mouse_exited() -> void:
	flag_button.modulate = Color(1, 1, 1)  # обратно нормальный
