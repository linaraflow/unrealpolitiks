extends CanvasLayer

@onready var panel = $BannerPanel
@onready var aggressor_name = $BannerPanel/AggressorName
@onready var defender_name = $BannerPanel/DefenderName
@onready var casus_label = $BannerPanel/CasusBelliLabel
@onready var flag_a = $BannerPanel/FlagA
@onready var flag_b = $BannerPanel/FlagB

var tween: Tween

func _ready() -> void:
    hide()
    
func load_flag(texture_rect: TextureRect, country_name: String) -> void:
    var flag_path = "res://assets/flags/" + country_name + ".png"
    if ResourceLoader.exists(flag_path):
        texture_rect.texture = load(flag_path)
    else:
        texture_rect.texture = load("res://assets/flags/unknown.png")

func show_declaration(attacker: String, defender: String) -> void:
    Global.play("res://audio/sfx/declare_war.ogg", "SFX")
    
    aggressor_name.text = attacker
    defender_name.text = defender
    casus_label.text = GameClock.get_date_string()
    
    load_flag(flag_a, attacker)
    load_flag(flag_b, defender)

    show()
    panel.position.y = -panel.size.y - 10

    if tween:
        tween.kill()
    tween = create_tween()

    # Въезд
    tween.tween_property(panel, "position:y", 112.0, 0.35) \
         .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

    # Тряска
    tween.tween_interval(0.1)
    var base_x = panel.position.x
    for i in 4:
        tween.tween_property(panel, "position:x",
            base_x + (4.0 if i % 2 == 0 else -4.0), 0.06)
    tween.tween_property(panel, "position:x", base_x, 0.06)

    # Пауза — игрок читает
    tween.tween_interval(2.5)

    # Выезд вверх
    tween.tween_property(panel, "position:y", -panel.size.y - 10, 0.3) \
         .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

    tween.tween_callback(hide)
