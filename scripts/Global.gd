extends Node2D

## MUSIC AND CURSOR (very useful singleton:))))

@onready var player = AudioStreamPlayer.new()

# Плейлист фоновой музыки — играет по кругу
var playlist = [
    "res://audio/music/Amazing-Grace-2011.ogg",
    "res://audio/music/String-Impromptu-Number-1.ogg",
    "res://audio/music/Virtutes-Vocis.ogg"
]
var playlist_index = 0

func _ready() -> void:
    var cursor = load("res://assets/cursor.png")
    Input.set_custom_mouse_cursor(cursor)

    add_child(player)
    player.bus = "Music"
    player.finished.connect(_on_music_finished)
    playlist.shuffle()
    _play_current_track()

    # Автоматически вешаем звук клика на ВСЕ кнопки в игре, даже те что появятся позже
    get_tree().node_added.connect(_on_node_added)
    _connect_existing_buttons(get_tree().root)

func _play_current_track() -> void:
    player.stream = load(playlist[playlist_index])
    player.play()

func _on_music_finished() -> void:
    playlist_index = (playlist_index + 1) % playlist.size()
    _play_current_track()

# Вызывается автоматически, когда в дерево сцены добавляется ЛЮБОЙ новый узел
func _on_node_added(node: Node) -> void:
    if node is BaseButton:
        _connect_button(node)

# Рекурсивно проходит по уже существующим узлам (на случай если кнопки
# были в сцене ДО того, как node_added начал слушать)
func _connect_existing_buttons(node: Node) -> void:
    if node is BaseButton:
        _connect_button(node)
    for child in node.get_children():
        _connect_existing_buttons(child)

func _connect_button(button: BaseButton) -> void:
    if not button.pressed.is_connected(_on_any_button_pressed):
        button.pressed.connect(_on_any_button_pressed)

func _on_any_button_pressed() -> void:
    play("res://audio/sfx/ui_click_reserve.ogg", "UI")

# Универсальная функция для одноразовых звуков (клики, взрыв, война и т.д.)
# Использование: Global.play("res://audio/sfx/ui_click.ogg")
func play(path: String, bus: String = "SFX") -> void:
    var sfx_player = AudioStreamPlayer.new()
    add_child(sfx_player)
    sfx_player.bus = bus
    sfx_player.stream = load(path)
    sfx_player.play()
    sfx_player.finished.connect(sfx_player.queue_free)
