extends Node

var adjacency: Dictionary = {}
var province_count: int = 0

func _ready() -> void:
    load_from_json("res://scripts/province_adjacency.json")

func load_from_json(path: String) -> void:
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        print("Ошибка: не удалось открыть ", path)
        return
    var json := JSON.new()
    var err := json.parse(file.get_as_text())
    file.close()
    if err != OK:
        print("Ошибка парсинга JSON")
        return
    var data: Dictionary = json.get_data()
    
    for key in data.keys():
        adjacency[int(key)] = data[key]
        
    print(adjacency)
    province_count = adjacency.size()
    print("Провинций загружено: ", province_count)
