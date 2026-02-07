extends Node

@export var heatGeneration : int
@export var powerConsumption : int
@export var inputs : int
@export var outputs : int
@export var buildCost : int

@export var recipes : Array

@export var basicMats : bool
@export var imtermediateMats : bool
@export var CrystalMats : bool
var dragging := false

@export var PrimaryFootprint : ImageTexture
@Export var AlternateFootprint : ImageTexture

var offset := Vector2.ONE

func _on_button_button_down() -> void:
	print("dragging is now active")
	dragging = true
	offset = get_global_mouse_position() - global_position


func _on_button_button_up() -> void:
	print("dragging is now inactive")
	dragging = false
