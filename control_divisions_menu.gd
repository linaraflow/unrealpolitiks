extends Control

var settings = preload("res://new_resource.tres")


@onready var QuanLabel: Label = $VBoxContainer/QuanPanel/MarginContainer/HBoxContainer/Label

@onready var DistributeButton: Button = $VBoxContainer/MainPanel/MarginContainer/HBoxContainer/DistributeButton
@onready var MergeButton: Button = $VBoxContainer/MainPanel/MarginContainer/HBoxContainer/MergeButton
@onready var SplitButton: Button = $VBoxContainer/QuanPanel/MarginContainer/HBoxContainer/SplitButton

@onready var DistributePanel: PanelContainer = $VBoxContainer/DistributePanel
@onready var NumTroops: Label = $VBoxContainer/DistributePanel/MarginContainer/VBoxContainer/HBoxContainer/NumTroops

func _ready() -> void:
    DistributePanel.hide()
    hide()
