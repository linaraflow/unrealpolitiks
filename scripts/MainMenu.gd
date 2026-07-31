extends Control

const SETTINGS_SCENE := preload("res://SettingsMenu.tscn")

func _on_settings_pressed() -> void:
    var instance := SETTINGS_SCENE.instantiate()
    add_child(instance)

func _on_new_game_pressed() -> void:
    get_tree().change_scene_to_file("res://game.tscn")

func _on_continue_pressed() -> void:
    pass

func _on_load_game_pressed() -> void:
    pass

func _on_multiplayer_pressed() -> void:
    pass

func _on_exit_pressed() -> void:
    get_tree().quit()
