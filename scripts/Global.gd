extends Node2D



func _ready() -> void:
    var cursor = load("res://assets/cursor.png")
    Input.set_custom_mouse_cursor(cursor)
