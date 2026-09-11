extends Node3D

# (Sem _ready() forcando cor fixa aqui de proposito -- a cor de cada
# instancia vem de VehicleController.color_id, aplicada logo apos
# instanciar o modelo via set_vehicle_color(). Um _ready() sobrescrevendo
# a cor entraria em corrida com essa chamada e faria todo veiculo aparecer
# com a mesma cor de teste.)

func set_vehicle_color(new_color: Color) -> void:
	_apply_color_recursive(self, new_color)


func _apply_color_recursive(node: Node, new_color: Color) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh

		if mesh != null:
			for surface_index: int in range(mesh.get_surface_count()):
				var source_material: Material = mesh_instance.get_active_material(surface_index)

				if source_material == null:
					continue

				var node_name: String = mesh_instance.name.to_lower()
				var material_name: String = source_material.resource_name.to_lower()

				# Esse GLB identifica as partes da pintura principalmente
				# pelo nome Car_Paint_0 dos MeshInstance3D.
				var is_car_paint: bool = (
					"car_paint" in node_name
					or "car_paint" in material_name
				)

				if not is_car_paint:
					continue

				var duplicated_material: Material = source_material.duplicate()

				if duplicated_material is BaseMaterial3D:
					var paint_material: BaseMaterial3D = duplicated_material as BaseMaterial3D
					paint_material.albedo_color = new_color

					mesh_instance.set_surface_override_material(
						surface_index,
						paint_material
					)

	for child: Node in node.get_children():
		_apply_color_recursive(child, new_color)
