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

const RESOURCE_BY_TYPE_AND_COLOR := {
	"car:red": "res://resources/vehicle_types/red.tres",
}

static func get_for_vehicle(type_id: String, color_id: String) -> VehicleVisualResource:
	var typed_key: String = "%s:%s" % [type_id, color_id]
	var typed_path: String = RESOURCE_BY_TYPE_AND_COLOR.get(typed_key, "")
	if typed_path != "" and ResourceLoader.exists(typed_path):
		return load(typed_path) as VehicleVisualResource
	return get_for_color(color_id)

static func get_for_color(color_id: String) -> VehicleVisualResource:
	var path: String = RESOURCE_BY_COLOR.get(color_id, "")
	if path != "" and ResourceLoader.exists(path):
		return load(path) as VehicleVisualResource
	return null

