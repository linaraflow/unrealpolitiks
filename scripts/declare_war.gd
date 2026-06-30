extends Button

@export var settings: GameSettings

@onready var WarBanner = get_node("/root/Game/WarBanner")

@onready var CountryMenu  = get_node("/root/Game/CanvasLayer/CountryMenu/Panel")

func _ready():
    add_to_group("declare_war_btn")

func _input(_event: InputEvent):
    if settings.last_clicked_province_id == 0:
        hide()
        return
    var owner = ProvinceRegistry.province_data.get(str(settings.last_clicked_province_id), {}).get("owner", "")
    var at_war = ProvinceRegistry.is_at_war(settings.active_country, owner)
    if settings.can_draw == true:
        visible = owner != "" and owner != settings.active_country and not at_war

func _on_pressed() -> void:
    var target_owner = ProvinceRegistry.province_data.get(str(settings.last_clicked_province_id), {}).get("owner", "")
    if target_owner != "" and target_owner != settings.active_country:
        ProvinceRegistry.declare_war(settings.active_country, target_owner)
        CountryMenu.update_info()
        WarBanner.show_declaration(settings.active_country, target_owner)
