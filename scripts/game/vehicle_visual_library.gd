class_name VehicleVisualLibrary
extends RefCounted

const RESOURCE_BY_COLOR := {
	"red": "res://resources/vehicle_types/red.tres",
	"blue": "res://resources/vehicle_types/blue.tres",
	"green": "res://resources/vehicle_types/green.tres",
	"yellow": "res://resources/vehicle_types/yellow.tres",
	"purple": "res://resources/vehicle_types/purple.tres",
	"pink": "res://resources/vehicle_types/pink.tres",
	"orange": "res://resources/vehicle_types/orange.tres",
}

static func get_for_color(color_id: String) -> VehicleVisualResource:
	var path: String = RESOURCE_BY_COLOR.get(color_id, "")
	if path != "" and ResourceLoader.exists(path):
		return load(path) as VehicleVisualResource
	return null

