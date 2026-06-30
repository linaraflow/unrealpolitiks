extends Label

@export var settings: Resource

func _ready() -> void:
    get_parent().get_parent().hide() # скрыть BalanceMenu

# Логику из _process убираем полностью, так как теперь её считает AIManager

func balance_update():
    if ProvinceRegistry.countries_data.has(settings.active_country):
        text = str(int(ProvinceRegistry.countries_data[settings.active_country]['balance'])) + ' 💵'
