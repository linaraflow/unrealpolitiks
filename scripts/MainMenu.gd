extends Control

const SETTINGS_SCENE := preload("res://SettingsMenu.tscn")
# Путь поправь под фактическое расположение файла SaveMenu.tscn в проекте.
const SAVE_MENU_SCENE := preload("res://SaveMenu.tscn")

func _ready() -> void:
    if not SaveManager.load_failed.is_connected(_on_load_failed):
        SaveManager.load_failed.connect(_on_load_failed)
    if not SaveManager.load_completed.is_connected(_on_load_completed):
        SaveManager.load_completed.connect(_on_load_completed)
        
    # ==== DISCORD ====
    DiscordRPC.state = tr("BTN_MAIN_MENU")
    DiscordRPC.start_timestamp = int(Time.get_unix_time_from_system())
    DiscordRPC.refresh()  # обязательно вызывать после каждого изменения полей

func _on_load_failed(slot: String, reason: String) -> void:
    push_error("[MainMenu] Загрузка слота '%s' провалилась: %s" % [slot, reason])

func _on_load_completed(slot: String) -> void:
    print("[MainMenu] Слот '%s' успешно загружен" % slot)

func _on_settings_pressed() -> void:
    var instance := SETTINGS_SCENE.instantiate()
    add_child(instance)

func _on_new_game_pressed() -> void:
    # ==== DISCORD ====
    DiscordRPC.state = tr("TAKING_OVER_THE_WORLD")
    DiscordRPC.start_timestamp = int(Time.get_unix_time_from_system())
    DiscordRPC.refresh()  # обязательно вызывать после каждого изменения полей
    
    Global._on_music_finished()
    SaveManager.reset_session()  # новая партия — автосейв не должен писать в слот предыдущей
    get_tree().change_scene_to_file("res://game.tscn")

func _on_continue_pressed() -> void:
    var slot := _find_latest_save_slot()
    if slot != "":
        _load_slot(slot)
        Global._on_music_finished()
    else:
        print("[MainMenu] Сохранения не найдены!")

## Находит слот с наибольшим saved_at_unix (самое свежее сохранение).
func _find_latest_save_slot() -> String:
    var latest_slot := ""
    var latest_time := -1
    for slot in SaveManager.list_saves():
        var info := SaveManager.get_save_info(slot)
        if info.is_empty():
            continue
        var t: int = int(info.get("saved_at_unix", 0))
        if t > latest_time:
            latest_time = t
            latest_slot = slot
    return latest_slot

func _on_load_game_pressed() -> void:
    var menu := SAVE_MENU_SCENE.instantiate()
    add_child(menu)
    menu.closed.connect(menu.queue_free)
    menu.open_for_load()

func _load_slot(slot: String) -> void:
    print("[MainMenu] _load_slot вызван для '%s'" % slot)
    SaveManager.request_load(slot)

func _on_multiplayer_pressed() -> void:
    pass

func _on_exit_pressed() -> void:
    get_tree().quit()
