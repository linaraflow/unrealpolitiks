extends Control # Или CanvasLayer, смотря какой тип у корня

@export var settings: Resource

func _ready():
    # Скрываем меню при запуске игры
    hide()
    # РАЗРЕШАЕМ этому узлу работать, когда игра на паузе
    process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event):
    if Input.is_action_just_pressed("ui_cancel"):
        if get_node("/root/Game/CanvasLayer/BLUE"):
            get_node("/root/Game/CanvasLayer/BLUE").hide()
        toggle_pause()

func toggle_pause():
    get_tree().paused = true
    visible = true
    
    # СТОП! Больше никто не должен реагировать на этот Esc в этом кадре
    get_viewport().set_input_as_handled()
    
    print("Пауза сейчас: ", get_tree().paused)


func _on_continue_button_pressed() -> void:
    if settings.can_draw == false:
        get_node("/root/Game/CanvasLayer/BLUE").show()
    get_tree().paused = false
    hide()


func _on_exit_button_pressed() -> void:
    get_tree().quit()
