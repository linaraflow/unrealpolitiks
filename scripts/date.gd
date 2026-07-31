extends Panel

@export var settings: GameSettings

func _ready() -> void:
    GameClock.on_day_passed.connect(_on_clock_day_passed)
    GameClock.on_pause_changed.connect(_on_clock_pause_changed)
    GameClock.on_speed_changed.connect(_update_speed_label)
    
    _on_clock_day_passed(GameClock.get_date())
    _update_speed_label()
    
    for button in [$HBoxContainer/PlusSpeedButton, $HBoxContainer/MinusSpeedButton, $HBoxContainer/PauseButton]:
        button.mouse_entered.connect(func(): button.modulate = Color(0.7, 0.7, 0.7))
        button.mouse_exited.connect(func(): button.modulate = Color(1, 1, 1))

func _on_clock_day_passed(_date: Dictionary) -> void:
    $HBoxContainer/DateLabel.text = GameClock.get_date_string()

func _modify_speed_index(modifier: int) -> void:
    var next_index = clampi(GameClock.speed_index + modifier, 1, GameClock.SPEEDS.size() - 1)
    GameClock.set_speed(next_index)

func _on_plus_speed_button_pressed() -> void:
    _modify_speed_index(1)

func _on_minus_speed_button_pressed() -> void:
    _modify_speed_index(-1)

func _on_pause_button_pressed() -> void:
    if settings and settings.can_draw:
        GameClock.toggle_pause()

func _on_clock_pause_changed(is_paused: bool) -> void:
    var icon_path = "res://assets/pause_closed.png" if is_paused else "res://assets/pause_opened.png"
    $HBoxContainer/PauseButton.icon = load(icon_path)

func _update_speed_label(_new_speed: int = 0) -> void:
    $HBoxContainer/SpeedPanel/SpeedLabel.text = "x" + str(GameClock.SPEEDS[GameClock.speed_index])
