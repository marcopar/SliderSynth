extends PanelContainer

# Live patch designer. Edit harmonics, ADSR, filter, detune, vibrato; load
# and save SynthPatch resources. The editor mutates the active patch in
# place so currently-sustaining voices reflect changes immediately.
# Loading or selecting a preset swaps the reference and emits patch_changed.
#
# Wiring: assign `synth`, add to scene tree, then call set_patch() with the
# starting patch. See music_test.gd for an example.

signal patch_changed(patch: SynthPatch)

const HARMONIC_SLOTS := 10

var synth: SynthEngine
var patch: SynthPatch
var current_path: String = ""

var _name_edit: LineEdit
var _waveform_option: OptionButton
var _path_label: Label
var _harm_sliders: Array[VSlider] = []
var _ratio_spins: Array[SpinBox] = []
var _param_sliders: Dictionary = {}   # prop -> {"slider": HSlider, "label": Label}
var _param_spins: Dictionary = {}     # prop -> SpinBox
var _param_options: Dictionary = {}   # prop -> OptionButton
var _save_dialog: FileDialog
var _load_dialog: FileDialog
var _suppress: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(640, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	if patch != null:
		_refresh_from_patch()

func set_patch(p: SynthPatch) -> void:
	patch = p
	if synth:
		synth.set_patch(0, p)
		synth.all_notes_off()
	if is_inside_tree():
		_refresh_from_patch()
	patch_changed.emit(p)

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	_build_top_bar(root)
	_build_waveform_row(root)
	_build_preset_row(root)
	_build_harmonics(root)
	_build_params(root)
	_build_test_row(root)
	_build_dialogs()

func _build_top_bar(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	row.add_child(_label("Name:"))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(160, 0)
	_name_edit.text_changed.connect(_on_name_changed)
	row.add_child(_name_edit)

	var new_btn := Button.new()
	new_btn.text = "New"
	new_btn.pressed.connect(_on_new)
	row.add_child(new_btn)

	var load_btn := Button.new()
	load_btn.text = "Load..."
	load_btn.pressed.connect(_on_load_pressed)
	row.add_child(load_btn)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_on_save)
	row.add_child(save_btn)

	var save_as_btn := Button.new()
	save_as_btn.text = "Save As..."
	save_as_btn.pressed.connect(_on_save_as)
	row.add_child(save_as_btn)

	_path_label = Label.new()
	_path_label.text = "(unsaved)"
	_path_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(_path_label)

func _build_waveform_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(_label("Waveform:"))
	_waveform_option = OptionButton.new()
	_waveform_option.add_item("Additive", SynthPatch.Waveform.ADDITIVE)
	_waveform_option.add_item("Sine", SynthPatch.Waveform.SINE)
	_waveform_option.add_item("Square", SynthPatch.Waveform.SQUARE)
	_waveform_option.add_item("Saw", SynthPatch.Waveform.SAW)
	_waveform_option.add_item("Triangle", SynthPatch.Waveform.TRIANGLE)
	_waveform_option.item_selected.connect(_on_waveform_selected)
	row.add_child(_waveform_option)

func _build_preset_row(parent: VBoxContainer) -> void:
	var row1 := HBoxContainer.new()
	parent.add_child(row1)
	row1.add_child(_label("Preset:"))
	_add_preset(row1, "Organ", func(): return SynthPatch.make_organ())
	_add_preset(row1, "Clarinet", func(): return SynthPatch.make_clarinet())
	_add_preset(row1, "Bell", func(): return SynthPatch.make_bell())
	_add_preset(row1, "Pad", func(): return SynthPatch.make_pad())
	_add_preset(row1, "Bass", func(): return SynthPatch.make_bass())
	row1.add_child(VSeparator.new())
	_add_preset(row1, "Kick", func(): return SynthPatch.make_kick())
	_add_preset(row1, "Snare", func(): return SynthPatch.make_snare())
	_add_preset(row1, "Hi-Hat", func(): return SynthPatch.make_hihat())

	var row2 := HBoxContainer.new()
	parent.add_child(row2)
	row2.add_child(_label("     "))
	_add_preset(row2, "FM Bell", func(): return SynthPatch.make_fm_bell())
	_add_preset(row2, "FM EPiano", func(): return SynthPatch.make_fm_epiano())
	_add_preset(row2, "FM Clang", func(): return SynthPatch.make_fm_clang())
	row2.add_child(VSeparator.new())
	_add_preset(row2, "Acid", func(): return SynthPatch.make_acid_bass())
	_add_preset(row2, "Pluck", func(): return SynthPatch.make_filter_pluck())
	_add_preset(row2, "Sweep", func(): return SynthPatch.make_sweep_sfx())
	row2.add_child(VSeparator.new())
	_add_preset(row2, "Snare+", func(): return SynthPatch.make_snare_snappy())
	_add_preset(row2, "Hat Open", func(): return SynthPatch.make_hihat_open())
	_add_preset(row2, "Crash", func(): return SynthPatch.make_cymbal_crash())

func _add_preset(parent: Control, label: String, maker: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.pressed.connect(func(): set_patch(maker.call()))
	parent.add_child(b)

func _build_harmonics(parent: VBoxContainer) -> void:
	parent.add_child(_label("Harmonics  (top: amplitude 0..1   bottom: ratio, 0 = integer multiple)"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	for i in HARMONIC_SLOTS:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.custom_minimum_size = Vector2(56, 0)

		var idx_label := Label.new()
		idx_label.text = str(i + 1)
		idx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(idx_label)

		var sl := VSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.01
		sl.custom_minimum_size = Vector2(30, 130)
		sl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		sl.value_changed.connect(_on_harmonic_changed.bind(i))
		col.add_child(sl)
		_harm_sliders.append(sl)

		var sp := SpinBox.new()
		sp.min_value = 0.0
		sp.max_value = 32.0
		sp.step = 0.01
		sp.custom_minimum_size = Vector2(56, 0)
		sp.value_changed.connect(_on_ratio_changed.bind(i))
		col.add_child(sp)
		_ratio_spins.append(sp)

		row.add_child(col)

func _build_params(parent: VBoxContainer) -> void:
	parent.add_child(_label("Parameters"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)

	# Envelope
	_add_slider_row(grid, "attack", "Attack (s)", 0.0, 3.0, 0.001)
	_add_slider_row(grid, "decay", "Decay (s)", 0.0, 3.0, 0.001)
	_add_slider_row(grid, "sustain", "Sustain", 0.0, 1.0, 0.01)
	_add_slider_row(grid, "release", "Release (s)", 0.0, 3.0, 0.001)
	# Gain / legacy LP
	_add_slider_row(grid, "lowpass", "Lowpass (legacy)", 0.0, 1.0, 0.01)
	_add_slider_row(grid, "gain", "Gain", 0.0, 1.0, 0.01)
	# Unison
	_add_int_spin_row(grid, "detune_voices", "Detune voices", 1, 4)
	_add_slider_row(grid, "detune_cents", "Detune cents", 0.0, 50.0, 0.1)
	# Vibrato
	_add_slider_row(grid, "vibrato_rate", "Vibrato rate (Hz)", 0.0, 15.0, 0.1)
	_add_slider_row(grid, "vibrato_depth_cents", "Vibrato depth (cents)", 0.0, 50.0, 0.1)
	# FM
	_add_slider_row(grid, "fm_ratio", "FM ratio", 0.0, 16.0, 0.01)
	_add_slider_row(grid, "fm_index", "FM index", 0.0, 8.0, 0.01)
	# Resonant filter
	_add_option_row(grid, "filter_type", "Filter type", [
		["Off", SynthPatch.FilterType.OFF],
		["Lowpass", SynthPatch.FilterType.LOWPASS],
		["Highpass", SynthPatch.FilterType.HIGHPASS],
		["Bandpass", SynthPatch.FilterType.BANDPASS],
	])
	_add_slider_row(grid, "filter_cutoff", "Filter cutoff", 0.0, 1.0, 0.01)
	_add_slider_row(grid, "filter_resonance", "Filter resonance", 0.0, 1.0, 0.01)
	_add_slider_row(grid, "filter_env_amount", "Filter env amount", -1.0, 1.0, 0.01)
	_add_slider_row(grid, "filter_attack", "Filter attack (s)", 0.0, 3.0, 0.001)
	_add_slider_row(grid, "filter_decay", "Filter decay (s)", 0.0, 3.0, 0.001)
	_add_slider_row(grid, "filter_sustain", "Filter sustain", 0.0, 1.0, 0.01)
	_add_slider_row(grid, "filter_release", "Filter release (s)", 0.0, 3.0, 0.001)
	# Drum / noise
	_add_slider_row(grid, "noise_mix", "Noise mix", 0.0, 1.0, 0.01)
	_add_slider_row(grid, "noise_decay", "Noise decay (s)", 0.0, 3.0, 0.001)
	_add_slider_row(grid, "noise_lowpass", "Noise lowpass", 0.0, 1.0, 0.01)
	_add_slider_row(grid, "noise_highpass", "Noise highpass", 0.0, 1.0, 0.01)
	_add_slider_row(grid, "pitch_decay_semitones", "Pitch decay (semi)", 0.0, 96.0, 0.5)
	_add_slider_row(grid, "pitch_decay_time", "Pitch decay time (s)", 0.0, 1.0, 0.001)
	# Humanization
	_add_slider_row(grid, "pitch_randomize_cents", "Pitch randomize (cents)", 0.0, 100.0, 0.5)
	_add_slider_row(grid, "velocity_randomize", "Velocity randomize", 0.0, 1.0, 0.01)

func _add_slider_row(grid: GridContainer, prop: String, label: String, mn: float, mx: float, step: float) -> void:
	grid.add_child(_label(label))
	var row := HBoxContainer.new()
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.custom_minimum_size = Vector2(280, 0)
	sl.value_changed.connect(_on_param_slider.bind(prop))
	row.add_child(sl)
	var val_label := Label.new()
	val_label.text = "0.000"
	val_label.custom_minimum_size = Vector2(56, 0)
	row.add_child(val_label)
	grid.add_child(row)
	_param_sliders[prop] = {"slider": sl, "label": val_label}

func _add_int_spin_row(grid: GridContainer, prop: String, label: String, mn: int, mx: int) -> void:
	grid.add_child(_label(label))
	var sp := SpinBox.new()
	sp.min_value = mn
	sp.max_value = mx
	sp.step = 1
	sp.value_changed.connect(_on_param_spin.bind(prop))
	grid.add_child(sp)
	_param_spins[prop] = sp

func _add_option_row(grid: GridContainer, prop: String, label: String, items: Array) -> void:
	grid.add_child(_label(label))
	var opt := OptionButton.new()
	for item in items:
		opt.add_item(item[0], item[1])
	opt.item_selected.connect(_on_param_option.bind(prop, opt))
	grid.add_child(opt)
	_param_options[prop] = opt

func _build_test_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var test_btn := Button.new()
	test_btn.text = "Test note (C4)"
	test_btn.pressed.connect(_test_note)
	row.add_child(test_btn)
	var hint := Label.new()
	hint.text = "  Keys A..; piano  •  Z/X octave  •  Space MIDI  •  F1 hide editor"
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(hint)

func _build_dialogs() -> void:
	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_RESOURCES
	_save_dialog.filters = PackedStringArray(["*.tres ; Patch Resource"])
	_save_dialog.size = Vector2i(720, 520)
	_save_dialog.file_selected.connect(_on_save_path_chosen)
	add_child(_save_dialog)

	_load_dialog = FileDialog.new()
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.access = FileDialog.ACCESS_RESOURCES
	_load_dialog.filters = PackedStringArray(["*.tres ; Patch Resource"])
	_load_dialog.size = Vector2i(720, 520)
	_load_dialog.file_selected.connect(_on_load_path_chosen)
	add_child(_load_dialog)

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

# ---------------------------------------------------------------------------
# Sync UI from patch
# ---------------------------------------------------------------------------

func _refresh_from_patch() -> void:
	if patch == null or _name_edit == null:
		return
	_suppress = true
	_name_edit.text = patch.patch_name
	# Select the OptionButton item whose id matches the waveform enum value.
	for idx in _waveform_option.item_count:
		if _waveform_option.get_item_id(idx) == patch.waveform:
			_waveform_option.select(idx)
			break
	for i in HARMONIC_SLOTS:
		var amp: float = 0.0
		if i < patch.harmonics.size():
			amp = patch.harmonics[i]
		_harm_sliders[i].value = amp
		var ratio: float = 0.0
		if i < patch.harmonic_ratios.size():
			ratio = patch.harmonic_ratios[i]
		_ratio_spins[i].value = ratio
	for prop in _param_sliders.keys():
		var entry: Dictionary = _param_sliders[prop]
		var sl: HSlider = entry["slider"]
		var lb: Label = entry["label"]
		var v: float = float(patch.get(prop))
		sl.value = v
		lb.text = "%.3f" % v
	for prop in _param_spins.keys():
		var sp: SpinBox = _param_spins[prop]
		sp.value = float(patch.get(prop))
	for prop in _param_options.keys():
		var opt: OptionButton = _param_options[prop]
		var target_id: int = int(patch.get(prop))
		for idx in opt.item_count:
			if opt.get_item_id(idx) == target_id:
				opt.select(idx)
				break
	_path_label.text = current_path if current_path != "" else "(unsaved)"
	_suppress = false

# ---------------------------------------------------------------------------
# Edit handlers
# ---------------------------------------------------------------------------

func _on_waveform_selected(index: int) -> void:
	if _suppress or patch == null:
		return
	patch.waveform = _waveform_option.get_item_id(index)

func _on_name_changed(text: String) -> void:
	if _suppress or patch == null:
		return
	patch.patch_name = text

func _on_harmonic_changed(value: float, index: int) -> void:
	if _suppress or patch == null:
		return
	var arr: PackedFloat32Array = patch.harmonics
	while arr.size() <= index:
		arr.append(0.0)
	arr[index] = value
	while arr.size() > 0 and arr[arr.size() - 1] == 0.0:
		arr.remove_at(arr.size() - 1)
	patch.harmonics = arr  # setter triggers wavetable rebuild

func _on_ratio_changed(value: float, index: int) -> void:
	if _suppress or patch == null:
		return
	var arr: PackedFloat32Array = patch.harmonic_ratios
	while arr.size() <= index:
		arr.append(0.0)
	arr[index] = value
	while arr.size() > 0 and arr[arr.size() - 1] == 0.0:
		arr.remove_at(arr.size() - 1)
	patch.harmonic_ratios = arr  # setter triggers wavetable rebuild

func _on_param_slider(value: float, prop: String) -> void:
	if _suppress or patch == null:
		return
	patch.set(prop, value)
	var entry: Dictionary = _param_sliders[prop]
	var lb: Label = entry["label"]
	lb.text = "%.3f" % value

func _on_param_spin(value: float, prop: String) -> void:
	if _suppress or patch == null:
		return
	patch.set(prop, int(value))

func _on_param_option(idx: int, prop: String, opt: OptionButton) -> void:
	if _suppress or patch == null:
		return
	patch.set(prop, opt.get_item_id(idx))

# ---------------------------------------------------------------------------
# New / Load / Save
# ---------------------------------------------------------------------------

func _on_new() -> void:
	var p := SynthPatch.new()
	p.patch_name = "New Patch"
	current_path = ""
	set_patch(p)

func _on_load_pressed() -> void:
	_load_dialog.popup_centered()

func _on_save() -> void:
	if current_path == "":
		_on_save_as()
		return
	_save_to_path(current_path)

func _on_save_as() -> void:
	if patch != null and patch.patch_name != "":
		_save_dialog.current_file = patch.patch_name.to_snake_case() + ".tres"
	else:
		_save_dialog.current_file = "patch.tres"
	_save_dialog.popup_centered()

func _on_save_path_chosen(path: String) -> void:
	if not path.ends_with(".tres"):
		path += ".tres"
	_save_to_path(path)
	current_path = path
	_path_label.text = path

func _save_to_path(path: String) -> void:
	if patch == null:
		return
	var err := ResourceSaver.save(patch, path)
	if err == OK:
		print("[PatchEditor] Saved: ", path)
	else:
		push_error("[PatchEditor] Save failed: %s (err=%d)" % [path, err])

func _on_load_path_chosen(path: String) -> void:
	var res := load(path)
	if res is SynthPatch:
		current_path = path
		set_patch(res)
	else:
		push_warning("[PatchEditor] Not a SynthPatch: " + path)

func _test_note() -> void:
	if synth == null:
		return
	synth.note_on(0, 60, 0.85)
	await get_tree().create_timer(1.0).timeout
	synth.note_off(0, 60)
