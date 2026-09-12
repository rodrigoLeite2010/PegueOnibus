extends SceneTree

var _instances: Array[Node3D] = []
var _fps_samples: Array[float] = []
var _frame_count: int = 0
var _count: int = 10
var _root3d: Node3D
var _cam: Camera3D

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--count="):
			_count = int(a.substr(8))

	_root3d = Node3D.new()
	root.add_child(_root3d)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_energy = 1.1
	_root3d.add_child(light)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.6
	env_node.environment = env
	_root3d.add_child(env_node)

	var packed: PackedScene = load("res://scenes/passengers/Passenger3D.tscn")
	var cols: int = int(ceil(sqrt(float(_count))))
	for i in range(_count):
		var inst: Node3D = packed.instantiate() as Node3D
		var col: int = i % cols
		var row: int = i / cols
		inst.position = Vector3(float(col) * 0.6, 0.0, -float(row) * 0.6)
		_root3d.add_child(inst)
		_instances.append(inst)

	_cam = Camera3D.new()
	_root3d.add_child(_cam)
	var extent: float = float(cols) * 0.6
	_cam.look_at_from_position(Vector3(extent * 0.5, extent * 0.8 + 1.0, extent * 1.1 + 1.0), Vector3(extent * 0.5, 0.5, -extent * 0.5), Vector3.UP)

	# Camera dedicada bem de frente a UM personagem, pra screenshot de validacao
	# visual de escala/orientacao/pose (Passo 4/5/10) -- so tirada quando
	# _count == 1 (chamada separada do benchmark de performance).
	if _count == 1:
		_cam.look_at_from_position(Vector3(0.0, 0.55, 1.35), Vector3(0.0, 0.5, 0.0), Vector3.UP)

	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frame_count += 1
	if _frame_count > 5:
		_fps_samples.append(Engine.get_frames_per_second())
	if _frame_count == 40:
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png("res://tests/etapa10a/shot_count_%d.png" % _count)
		var avg_fps: float = 0.0
		for f in _fps_samples:
			avg_fps += f
		if _fps_samples.size() > 0:
			avg_fps /= _fps_samples.size()
		print("RESULT count=%d avg_fps=%.2f min_fps=%.2f max_fps=%.2f" % [_count, avg_fps, _fps_samples.min(), _fps_samples.max()])
		quit()
