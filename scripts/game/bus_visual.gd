extends Node3D

# bus.glb (diferente de car_test.glb/medium_car.glb) tem UMA UNICA
# MeshInstance3D pra carroceria inteira ("Cube.002_ToeiBus_0", material
# "ToeiBus") -- nao existe uma malha separada so pra pintura, so pra
# vidro/rodas/interior como nos carros. Por isso este script nao filtra
# por nome (tipo "car_paint" em medium_car_visual.gd): ele recolore TODA
# MeshInstance3D que encontrar. Na pratica isso funciona porque so ha uma
# mesh mesmo, mas e uma limitacao real do asset: se um dia trocarem o GLB
# do onibus por um com vidro/rodas em meshes separadas, este script vai
# precisar de um filtro por nome igual ao do carro medio (ver
# medium_car_visual.gd) pra nao pintar o vidro junto com a carroceria.
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

				var duplicated_material: Material = source_material.duplicate()
				if duplicated_material is BaseMaterial3D:
					var paint_material: BaseMaterial3D = duplicated_material as BaseMaterial3D
					paint_material.albedo_color = new_color
					mesh_instance.set_surface_override_material(surface_index, paint_material)

	for child: Node in node.get_children():
		_apply_color_recursive(child, new_color)
