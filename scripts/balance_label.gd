extends Label

@export var settings: Resource

func balance_update():
    if ProvinceRegistry.countries_data.has(settings.active_country):
        var balance_val = ProvinceRegistry.countries_data[settings.active_country]['balance']
        text = ProvinceRegistry._format_number(balance_val, ".") + ' 💵'
