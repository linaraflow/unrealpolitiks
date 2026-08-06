extends Control

@export var settings: GameSettings

@onready var caption = $Panel/DivisionsLabel
@onready var armies_list = $Panel/LandDivisionsPanel/ScrollContainer/ArmiesList
@onready var recruit_btn = get_node("/root/Game/CanvasLayer/ProvinceMenu/Panel/RecruitButton")

func _ready() -> void:
    SelectionManager.DivisionMenu = self
    caption.text = "🪖 " + tr("DIVISIONS")
    hide()
    
func update_info(data: Dictionary) -> void:
    show()
    
    for child in armies_list.get_children():
        child.queue_free()
        
    var province_id = int(settings.last_clicked_province_id)
    var country_soldiers = {} # считаем реальных людей
    var country_armies = {}

    if DivisionManager.armies.has(province_id):
        var armies_in_province = DivisionManager.armies[province_id]
        for circle in armies_in_province:
            var owner = circle.division_owner
            var s_count = circle.soldiers # Берем точное количество

            if country_soldiers.has(owner):
                country_soldiers[owner] += s_count
            else:
                country_soldiers[owner] = s_count
                country_armies[owner] = [] 
                
            country_armies[owner].append(circle)

    if country_soldiers.is_empty():
        var no_divisions_label = Label.new()
        no_divisions_label.text = tr("NO_DIVISIONS")
        no_divisions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        armies_list.add_child(no_divisions_label)
        return

    for country in country_soldiers.keys():
        var country_vbox = VBoxContainer.new()
        var main_margin = MarginContainer.new()
        main_margin.add_theme_constant_override("margin_left", 12) 
        
        var row = HBoxContainer.new()
        row.add_theme_constant_override("separation", 10) 
        
        var flag_icon = TextureRect.new()
        flag_icon.custom_minimum_size = Vector2(24, 16)
        flag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        flag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        flag_icon.texture = load("res://assets/flags/" + str(country) + ".png")
        row.add_child(flag_icon)
        
        var info_label = Label.new()
        var people_count = country_soldiers[country] 
        info_label.text = str(country) + "  (" + str(people_count) + " pers.)"
        row.add_child(info_label)
        
        main_margin.add_child(row)
        country_vbox.add_child(main_margin)
        
        for army in country_armies[country]:
            var army_margin = MarginContainer.new()
            army_margin.add_theme_constant_override("margin_left", 36) 
            
            var army_label = Label.new()
            army_label.text = army.army_name + " - " + str(army.soldiers) + " pers."
            army_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8)) 
            
            army_margin.add_child(army_label)
            country_vbox.add_child(army_margin)
            
        armies_list.add_child(country_vbox)


func _on_scroll_container_mouse_entered() -> void:
    settings.is_mouse_over_ui = true


func _on_scroll_container_mouse_exited() -> void:
    settings.is_mouse_over_ui = false
