# =============================================================================
# AITrade.gd
# ИИ: продажа накопленных товаров (бывший раздел 7 AIManager.gd).
#
# Класс не хранит состояния — читает/пишет его через синглтон AIManager.
# =============================================================================
class_name AITrade
extends RefCounted

static func process_trade(country: String) -> void:
    var c_data  = ProvinceRegistry.countries_data[country]
    var stock   = c_data.get("products", 0.0)
    if stock <= 0.0:
        return

    var sanctions    = c_data.get("sanctions", 0.0)
    var actual_price = AIManager.settings.product_cost * (1.0 - (sanctions / 100.0))

    c_data["products"] = 0.0
    c_data["balance"]  = c_data.get("balance", 0.0) + stock * actual_price
