extends Node
# Autoload singleton. Добавь в Project Settings -> Autoload как "GameplayInputController".
# Требует SettingsManager (см. SettingsManager.gd), т.к. именно он создаёт
# экшены в InputMap на основе настроенных биндов (SettingsManager.sync_input_map()).
#
# Здесь проверяются нажатия по этим экшенам и дёргается твоя игровая логика.
# Замени тела функций-заглушек ниже на реальные вызовы (например, к твоему
# ProvinceManager/ArmyManager/UIManager и т.д.).

func _unhandled_input(event: InputEvent) -> void:
    if Input.is_action_just_pressed("build_factory"):
        _on_build_factory()

    if Input.is_action_just_pressed("summon_troops"):
        _on_summon_troops()

    if Input.is_action_just_pressed("summon_max_troops_province"):
        _on_summon_max_troops_province()

    if Input.is_action_just_pressed("hide_ui"):
        _on_toggle_ui()

    if Input.is_action_just_pressed("pause"):
        _on_toggle_pause()

    if Input.is_action_just_pressed("zoom_in"):
        _on_zoom_in()

    if Input.is_action_just_pressed("zoom_out"):
        _on_zoom_out()

# ---------------------------------------------------------------
# Заглушки — замени на реальную логику своей игры.
# ---------------------------------------------------------------

func _on_build_factory() -> void:
    print(">>> [GameplayInputController] build_factory нажат")
    # TODO: например
    # var province := ProvinceSelection.get_selected_province()
    # if province:
    #     FactoryManager.build_in(province)

func _on_summon_troops() -> void:
    print(">>> [GameplayInputController] summon_troops нажат")
    # TODO: ArmyManager.summon_troops(selected_province)

func _on_summon_max_troops_province() -> void:
    print(">>> [GameplayInputController] summon_max_troops_province нажат")
    # TODO: ArmyManager.summon_max_troops(selected_province)

var _ui_hidden: bool = false
func _on_toggle_ui() -> void:
    _ui_hidden = not _ui_hidden
    print(">>> [GameplayInputController] hide_ui -> ", _ui_hidden)
    # TODO: например
    # get_tree().get_first_node_in_group("hud").visible = not _ui_hidden

func _on_toggle_pause() -> void:
    print(">>> [GameplayInputController] pause нажат")
    # TODO: get_tree().paused = not get_tree().paused

func _on_zoom_in() -> void:
    pass # TODO: camera zoom logic

func _on_zoom_out() -> void:
    pass # TODO: camera zoom logic
