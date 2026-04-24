@tool
extends RefCounted
class_name GameifyApi

# Thin wrapper around HTTPRequest. One instance per call — instantiate, connect,
# kick off, await the signal, free.
#
# Why not one long-lived client? HTTPRequest's `request_completed` signal fires
# for every request on the node, so reusing one instance across concurrent calls
# risks crossing streams. Cheaper to spin up a fresh one per call.

const DEFAULT_BASE_URL := "https://api.gameify.online/apiv2"


static func base_url() -> String:
	var settings := EditorInterface.get_editor_settings()
	var override: String = settings.get_setting("gameify/api_base_url") if settings.has_setting("gameify/api_base_url") else ""
	return override if not override.is_empty() else DEFAULT_BASE_URL


static func api_key() -> String:
	var settings := EditorInterface.get_editor_settings()
	return settings.get_setting("gameify/api_key") if settings.has_setting("gameify/api_key") else ""


## Submit a game — 3-hop orchestration so large exports bypass Lambda's
## sync-payload cap:
##
##   1. POST /games/submit-init  → mints a presigned S3 PUT URL and a
##      game_id + upload_key pair scoped to the authed user.
##   2. PUT  <upload_url>         → streams the zip straight into the
##      staging bucket. No auth header; the URL itself is the credential.
##   3. POST /games/submit-finalize → metadata + game_id + upload_key;
##      server unpacks the zip into the games bucket, writes the DDB
##      row, emails the reviewer.
##
## Returns `{ok: bool, body: Variant, code: int}` carrying the finalize
## response (slug, review_eta_hours, runner_path, …).
static func submit_game(host: Node, zip_path: String, metadata: Dictionary) -> Dictionary:
	var zip_bytes := FileAccess.get_file_as_bytes(zip_path)
	if zip_bytes.is_empty():
		return {"ok": false, "body": "Export zip was empty or unreadable", "code": 0}

	# Step 1 — presign.
	var init := await _post_json(host, "/games/submit-init", {})
	if not init.ok:
		return init
	var init_body: Dictionary = init.body
	var upload_url: String = init_body.get("upload_url", "")
	var upload_key: String = init_body.get("upload_key", "")
	var game_id: String = init_body.get("game_id", "")
	if upload_url.is_empty() or upload_key.is_empty() or game_id.is_empty():
		return {"ok": false, "body": "submit-init missing fields", "code": 0}

	# Step 2 — presigned PUT. No API key header needed; URL is the
	# credential. HTTPRequest doesn't let us skip the Host header, but
	# Godot adds it correctly for the target URL.
	var put_req := HTTPRequest.new()
	put_req.timeout = 300.0
	host.add_child(put_req)
	var put_err := put_req.request_raw(
		upload_url,
		["Content-Type: application/zip"],
		HTTPClient.METHOD_PUT,
		zip_bytes,
	)
	if put_err != OK:
		put_req.queue_free()
		return {"ok": false, "body": "S3 PUT failed to start (err %d)" % put_err, "code": 0}
	var put_result: Array = await put_req.request_completed
	put_req.queue_free()
	if put_result[1] < 200 or put_result[1] >= 300:
		return {
			"ok": false,
			"body": "S3 PUT returned HTTP %d" % put_result[1],
			"code": put_result[1],
		}

	# Step 3 — finalize. Merge server-returned ids with metadata.
	var finalize_body := metadata.duplicate()
	finalize_body["game_id"] = game_id
	finalize_body["upload_key"] = upload_key
	return await _post_json(host, "/games/submit-finalize", finalize_body)


## Internal: POST JSON with Bearer auth, parse response. Used by both
## submit steps + future authed calls.
static func _post_json(host: Node, path: String, body: Dictionary) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 60.0
	host.add_child(req)
	var err := req.request(
		base_url() + path,
		[
			"Authorization: Bearer " + api_key(),
			"Content-Type: application/json",
			"X-Client: godot-plugin/0.2.0",
		],
		HTTPClient.METHOD_POST,
		JSON.stringify(body),
	)
	if err != OK:
		req.queue_free()
		return {"ok": false, "body": "HTTPRequest failed to start (err %d)" % err, "code": 0}
	var result: Array = await req.request_completed
	req.queue_free()
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
