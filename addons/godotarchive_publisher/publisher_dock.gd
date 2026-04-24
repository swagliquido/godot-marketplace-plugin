@tool
extends VBoxContainer

# Editor dock for publishing the current project to GodotArchive.
#
# Layout:
#   ┌──────────────────────────────────┐
#   │ GodotArchive Publisher           │
#   ├──────────────────────────────────┤
#   │ API key: […………………] (Edit)       │  ← tap Edit to open EditorSettings
#   │ Status:  (connected / not set)   │
#   ├──────────────────────────────────┤
#   │ Title:       [ My Game         ] │
#   │ Description: [────────────────┐  │
#   │              │                │  │
#   │              └────────────────┘  │
#   │ Tags:        [ platformer, 2d  ] │
#   │ Genre:       [ Platformer     ▾] │
#   │ Price:       ( ) Free           │
#   │              ( ) Pay-what-you-want│
#   │              (o) Fixed: [ 500 ¢] │
#   ├──────────────────────────────────┤
#   │ HTML5 export: [ res://export  …] │  ← folder picker
#   │ [ Upload to GodotArchive ]       │
#   │ [ Show my submissions ]          │
#   ├──────────────────────────────────┤
#   │ Log: …                           │
#   └──────────────────────────────────┘

const GodotArchiveApi := preload("res://addons/godotarchive_publisher/api_client.gd")

const GENRES := ["Platformer", "Puzzle", "Action", "Adventure", "RPG", "Shooter",
	"Strategy", "Simulation", "Racing", "Sports", "Rhythm", "Visual Novel", "Other"]

const PRICE_FREE := 0
const PRICE_PWYW := -1  # Sentinel — API reads this as "user-named price, min 0".

@onready var _title_edit: LineEdit = $"Form/Title/Value"
@onready var _desc_edit: TextEdit = $"Form/Desc/Value"
@onready var _tags_edit: LineEdit = $"Form/Tags/Value"
@onready var _genre_opt: OptionButton = $"Form/Genre/Value"
@onready var _price_group: HBoxContainer = $"Form/Price/Options"
@onready var _price_fixed_value: SpinBox = $"Form/Price/Options/Fixed/Amount"
@onready var _export_dir_edit: LineEdit = $"Export/DirRow/Value"
@onready var _status_label: Label = $"Status/Value"
@onready var _log: RichTextLabel = $"Log"
@onready var _submit_btn: Button = $"Actions/Submit"

var _price_free_btn: CheckBox
var _price_pwyw_btn: CheckBox
var _price_fixed_btn: CheckBox
var _folder_dialog: FileDialog


func _init() -> void:
	# Programmatic build — simpler than maintaining a .tscn alongside this.
	# Keeps the addon as a single importable folder (no scene path pitfalls).
	name = "GodotArchive"
	set_v_size_flags(SIZE_EXPAND_FILL)
	add_theme_constant_override("separation", 8)
	_build_ui()


func _ready() -> void:
	_refresh_status()


func _build_ui() -> void:
	add_child(_section_header("GodotArchive Publisher"))

	# ── Status row ──
	var status := HBoxContainer.new()
	status.name = "Status"
	status.add_child(_label("Status:"))
	var s := Label.new()
	s.name = "Value"
	s.text = "…"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.size_flags_horizontal = SIZE_EXPAND_FILL
	status.add_child(s)
	var edit_btn := Button.new()
	edit_btn.text = "Edit API key"
	edit_btn.pressed.connect(_on_edit_api_key_pressed)
	status.add_child(edit_btn)
	add_child(status)

	add_child(HSeparator.new())

	# ── Form ──
	var form := VBoxContainer.new()
	form.name = "Form"
	form.add_theme_constant_override("separation", 6)
	add_child(form)

	form.add_child(_labeled_row("Title", _new_line_edit("My awesome game")))
	form.add_child(_labeled_row("Desc", _new_text_edit()))
	form.add_child(_labeled_row("Tags", _new_line_edit("platformer, 2d, retro")))
	form.add_child(_labeled_row("Genre", _new_option_button(GENRES)))
	form.add_child(_build_price_row())

	# ── Export picker ──
	var export_section := VBoxContainer.new()
	export_section.name = "Export"
	export_section.add_theme_constant_override("separation", 4)
	add_child(export_section)

	var dir_row := HBoxContainer.new()
	dir_row.name = "DirRow"
	dir_row.add_child(_label("HTML5 export dir:"))
	var dir_val := LineEdit.new()
	dir_val.name = "Value"
	dir_val.placeholder_text = "res://export/web"
	dir_val.size_flags_horizontal = SIZE_EXPAND_FILL
	dir_row.add_child(dir_val)
	var pick_btn := Button.new()
	pick_btn.text = "…"
	pick_btn.pressed.connect(_on_pick_dir_pressed)
	dir_row.add_child(pick_btn)
	export_section.add_child(dir_row)

	# ── Actions ──
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	var submit := Button.new()
	submit.name = "Submit"
	submit.text = "Upload to GodotArchive"
	submit.pressed.connect(_on_submit_pressed)
	actions.add_child(submit)
	var my_games := Button.new()
	my_games.text = "My submissions"
	my_games.pressed.connect(_on_my_submissions_pressed)
	actions.add_child(my_games)
	add_child(actions)

	# ── Log ──
	var log := RichTextLabel.new()
	log.name = "Log"
	log.bbcode_enabled = true
	log.fit_content = true
	log.size_flags_vertical = SIZE_EXPAND_FILL
	log.custom_minimum_size = Vector2(0, 100)
	log.append_text("[i]Ready. Configure your API key to get started.[/i]")
	add_child(log)


func _section_header(title: String) -> Control:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 16)
	return l


func _label(text: String) -> Control:
	var l := Label.new()
	l.text = text
	return l


func _labeled_row(name_: String, child: Control) -> Control:
	var row := HBoxContainer.new()
	row.name = name_
	var label := _label(name_ + ":")
	label.custom_minimum_size = Vector2(80, 0)
	row.add_child(label)
	child.name = "Value"
	child.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(child)
	return row


func _new_line_edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	return e


func _new_text_edit() -> TextEdit:
	var e := TextEdit.new()
	e.placeholder_text = "What is this game about? Who should play it?"
	e.custom_minimum_size = Vector2(0, 80)
	return e


func _new_option_button(options: Array) -> OptionButton:
	var o := OptionButton.new()
	for g: String in options:
		o.add_item(g)
	return o


func _build_price_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "Price"
	row.add_child(_label("Price:"))
	var opts := HBoxContainer.new()
	opts.name = "Options"
	opts.add_theme_constant_override("separation", 10)

	_price_free_btn = CheckBox.new()
	_price_free_btn.text = "Free"
	_price_free_btn.button_pressed = true
	opts.add_child(_price_free_btn)

	_price_pwyw_btn = CheckBox.new()
	_price_pwyw_btn.text = "Pay-what-you-want"
	opts.add_child(_price_pwyw_btn)

	var fixed_box := HBoxContainer.new()
	fixed_box.name = "Fixed"
	_price_fixed_btn = CheckBox.new()
	_price_fixed_btn.text = "Fixed (¢):"
	fixed_box.add_child(_price_fixed_btn)
	var amount := SpinBox.new()
	amount.name = "Amount"
	amount.min_value = 50
	amount.max_value = 1_000_00
	amount.step = 50
	amount.value = 500
	fixed_box.add_child(amount)
	opts.add_child(fixed_box)

	_price_free_btn.pressed.connect(_make_price_setter(_price_free_btn))
	_price_pwyw_btn.pressed.connect(_make_price_setter(_price_pwyw_btn))
	_price_fixed_btn.pressed.connect(_make_price_setter(_price_fixed_btn))

	row.add_child(opts)
	return row


func _make_price_setter(active: CheckBox) -> Callable:
	return func() -> void:
		for btn: CheckBox in [_price_free_btn, _price_pwyw_btn, _price_fixed_btn]:
			if btn != active:
				btn.button_pressed = false
		if not active.button_pressed:
			active.button_pressed = true


func _refresh_status() -> void:
	var key := GodotArchiveApi.api_key()
	if key.is_empty():
		_status_label.text = "No API key set"
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
		_submit_btn.disabled = true
	else:
		_status_label.text = "Connected"
		_status_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))
		_submit_btn.disabled = false


func _on_edit_api_key_pressed() -> void:
	# Open EditorSettings at the relevant section. Users paste the key
	# there rather than typing it into a plugin text field that might end
	# up in version control / screenshots.
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting("godotarchive/api_key"):
		settings.set_setting("godotarchive/api_key", "")
		settings.set_initial_value("godotarchive/api_key", "", false)
	if not settings.has_setting("godotarchive/api_base_url"):
		settings.set_setting("godotarchive/api_base_url", GodotArchiveApi.DEFAULT_BASE_URL)
		settings.set_initial_value("godotarchive/api_base_url", GodotArchiveApi.DEFAULT_BASE_URL, false)
	EditorInterface.get_base_control().get_viewport().gui_release_focus()
	_log.append_text("\n[color=gray]Open Editor → Editor Settings → godotarchive section.[/color]")
	_refresh_status()


func _on_pick_dir_pressed() -> void:
	if _folder_dialog == null:
		_folder_dialog = FileDialog.new()
		_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_folder_dialog.dir_selected.connect(func(path: String) -> void:
			_export_dir_edit.text = path
		)
		add_child(_folder_dialog)
	_folder_dialog.popup_centered(Vector2i(720, 420))


func _on_submit_pressed() -> void:
	var dir: String = _export_dir_edit.text.strip_edges()
	if dir.is_empty():
		_log.append_text("\n[color=red]Pick your HTML5 export directory first.[/color]")
		return
	if not DirAccess.dir_exists_absolute(dir):
		_log.append_text("\n[color=red]Directory does not exist: %s[/color]" % dir)
		return

	_submit_btn.disabled = true
	_log.append_text("\n[b]Zipping…[/b] %s" % dir)
	var tmp_zip := "user://godotarchive_upload_%d.zip" % Time.get_unix_time_from_system()
	var zipped := _zip_export_dir(dir, ProjectSettings.globalize_path(tmp_zip))
	if not zipped:
		_log.append_text("\n[color=red]Failed to build zip. See output log.[/color]")
		_submit_btn.disabled = false
		return

	_log.append_text("\n[b]Uploading…[/b]")
	var metadata := {
		"title": _title_edit.text.strip_edges(),
		"description": _desc_edit.text.strip_edges(),
		"tags": _parse_tags(_tags_edit.text),
		"genre": GENRES[_genre_opt.selected] if _genre_opt.selected >= 0 else "Other",
		"price_cents": _selected_price_cents(),
	}
	var result: Dictionary = await GodotArchiveApi.submit_game(self, ProjectSettings.globalize_path(tmp_zip), metadata)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_zip))

	if result.ok:
		var body: Variant = result.body
		var slug: String = ""
		if body is Dictionary and body.has("slug"):
			slug = body["slug"]
		_log.append_text("\n[color=green]Submitted for review.[/color] %s" % (
			"[url]https://godotarchive.com/games/%s[/url]" % slug if not slug.is_empty() else ""
		))
	else:
		var msg := "HTTP %d" % result.code
		if result.body is Dictionary and result.body.has("error"):
			msg += ": " + String(result.body["error"])
		_log.append_text("\n[color=red]Upload failed:[/color] %s" % msg)
	_submit_btn.disabled = false


func _on_my_submissions_pressed() -> void:
	_log.append_text("\n[b]Fetching your submissions…[/b]")
	var result: Dictionary = await GodotArchiveApi.list_my_games(self)
	if not result.ok:
		_log.append_text("\n[color=red]Fetch failed (HTTP %d)[/color]" % result.code)
		return
	var games: Variant = result.body
	if games is Dictionary and games.has("games"):
		games = games["games"]
	if games is not Array or (games as Array).is_empty():
		_log.append_text("\n[i]No submissions yet.[/i]")
		return
	for game: Dictionary in games:
		var status_color := {"approved": "green", "pending": "yellow", "rejected": "red"}.get(game.get("status", ""), "gray")
		_log.append_text("\n• %s — [color=%s]%s[/color]" % [
			game.get("title", "Untitled"),
			status_color,
			game.get("status", "unknown"),
		])


# ─── helpers ────────────────────────────────────────────────────────────────

func _parse_tags(raw: String) -> Array:
	var out: Array[String] = []
	for t: String in raw.split(",", false):
		var s := t.strip_edges()
		if not s.is_empty():
			out.append(s.to_lower())
	return out


func _selected_price_cents() -> int:
	if _price_free_btn.button_pressed:
		return PRICE_FREE
	if _price_pwyw_btn.button_pressed:
		return PRICE_PWYW
	return int(_price_fixed_value.value)


## Walk `dir` recursively and write every file into `out_zip` using Godot's
## ZIPPacker. Relative paths inside the archive are what the web runner
## expects (`index.html` at the root). Returns true on success.
func _zip_export_dir(dir: String, out_zip: String) -> bool:
	var packer := ZIPPacker.new()
	var err := packer.open(out_zip)
	if err != OK:
		push_error("ZIPPacker.open failed: %d" % err)
		return false

	var root_globalized: String = ProjectSettings.globalize_path(dir) if dir.begins_with("res://") else dir
	var ok := _zip_walk(packer, root_globalized, "")
	packer.close()
	return ok


func _zip_walk(packer: ZIPPacker, abs_root: String, rel: String) -> bool:
	var dir := DirAccess.open(abs_root + ("/" + rel if rel != "" else ""))
	if dir == null:
		return false
	dir.list_dir_begin()
	var name_ := dir.get_next()
	while name_ != "":
		if name_ == "." or name_ == "..":
			name_ = dir.get_next()
			continue
		var rel_child := (rel + "/" + name_) if rel != "" else name_
		var abs_child := abs_root + "/" + rel_child
		if dir.current_is_dir():
			if not _zip_walk(packer, abs_root, rel_child):
				return false
		else:
			var bytes := FileAccess.get_file_as_bytes(abs_child)
			if bytes.is_empty() and FileAccess.get_open_error() != OK:
				push_warning("Skipping unreadable file: " + abs_child)
			else:
				packer.start_file(rel_child)
				packer.write_file(bytes)
				packer.close_file()
		name_ = dir.get_next()
	dir.list_dir_end()
	return true
