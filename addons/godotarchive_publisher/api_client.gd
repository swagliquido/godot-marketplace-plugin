@tool
extends RefCounted
class_name GodotArchiveApi

# Thin wrapper around HTTPRequest. One instance per call — instantiate, connect,
# kick off, await the signal, free.
#
# Why not one long-lived client? HTTPRequest's `request_completed` signal fires
# for every request on the node, so reusing one instance across concurrent calls
# risks crossing streams. Cheaper to spin up a fresh one per call.

const DEFAULT_BASE_URL := "https://api.godotarchive.com/apiv2"


static func base_url() -> String:
	var settings := EditorInterface.get_editor_settings()
	var override: String = settings.get_setting("godotarchive/api_base_url") if settings.has_setting("godotarchive/api_base_url") else ""
	return override if not override.is_empty() else DEFAULT_BASE_URL


static func api_key() -> String:
	var settings := EditorInterface.get_editor_settings()
	return settings.get_setting("godotarchive/api_key") if settings.has_setting("godotarchive/api_key") else ""


## Submit a game or game update. `metadata` is a Dictionary with keys:
##   title, description, tags (Array[String]), genre, price_cents (int, 0 = free),
##   update_of_game_id (optional — non-empty means this is an update to an
##   existing game rather than a new submission).
##
## `zip_path` must be a pre-built HTML5 export archive (see publisher_dock's
## `_zip_export_dir`). Returns a Dictionary: `{ok: bool, body: Variant, code: int}`.
static func submit_game(host: Node, zip_path: String, metadata: Dictionary) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 120.0
	host.add_child(req)

	var zip_bytes := FileAccess.get_file_as_bytes(zip_path)
	if zip_bytes.is_empty():
		req.queue_free()
		return {"ok": false, "body": "Export zip was empty or unreadable", "code": 0}

	# Multipart body. Keeping this hand-rolled because Godot ships no helper
	# and reaching for a 3rd-party crate for one HTTP call feels excessive.
	var boundary := "GdArchBoundary-" + str(Time.get_unix_time_from_system()).md5_text()
	var body := PackedByteArray()
	body.append_array(_field(boundary, "metadata", JSON.stringify(metadata)))
	body.append_array(_file_field(boundary, "export_zip", zip_path.get_file(), zip_bytes))
	body.append_array(("--" + boundary + "--\r\n").to_utf8_buffer())

	var headers := [
		"Authorization: Bearer " + api_key(),
		"Content-Type: multipart/form-data; boundary=" + boundary,
		"X-Client: godot-plugin/0.1.0",
	]
	var err := req.request_raw(base_url() + "/games/submit", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "body": "HTTPRequest failed to start (err %d)" % err, "code": 0}

	var result: Array = await req.request_completed
	req.queue_free()
	# result: [result_code, response_code, headers, body]
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]
	var parsed: Variant = null
	if response_body.size() > 0:
		parsed = JSON.parse_string(response_body.get_string_from_utf8())
		if parsed == null:
			parsed = response_body.get_string_from_utf8()
	return {
		"ok": response_code >= 200 and response_code < 300,
		"body": parsed,
		"code": response_code,
	}


## GET /games/mine — list games submitted by this user, each with review status.
## Used to populate the dock's "Your submissions" panel so the user can see
## whether prior uploads are pending / approved / rejected without leaving Godot.
static func list_my_games(host: Node) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 30.0
	host.add_child(req)
	var headers := [
		"Authorization: Bearer " + api_key(),
		"X-Client: godot-plugin/0.1.0",
	]
	var err := req.request(base_url() + "/games/mine", headers, HTTPClient.METHOD_GET)
	if err != OK:
		req.queue_free()
		return {"ok": false, "body": "HTTPRequest failed to start (err %d)" % err, "code": 0}
	var result: Array = await req.request_completed
	req.queue_free()
	var response_code: int = result[1]
	var parsed: Variant = null
	if result[3].size() > 0:
		parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	return {
		"ok": response_code >= 200 and response_code < 300,
		"body": parsed,
		"code": response_code,
	}


# ─── multipart helpers ──────────────────────────────────────────────────────

static func _field(boundary: String, name: String, value: String) -> PackedByteArray:
	var s := "--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, name, value]
	return s.to_utf8_buffer()


static func _file_field(boundary: String, name: String, filename: String, bytes: PackedByteArray) -> PackedByteArray:
	var header := "--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: application/zip\r\n\r\n" % [boundary, name, filename]
	var out := header.to_utf8_buffer()
	out.append_array(bytes)
	out.append_array("\r\n".to_utf8_buffer())
	return out
