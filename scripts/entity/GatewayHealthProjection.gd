extends RefCounted

## A bounded, schema-pinned *observation* of the KiloCore Colony Gateway.
## The gateway /health endpoint answers {"status":"ok"} (15 bytes). Only the
## status string crosses into the scene tree — no discovery payload, no
## OAuth metadata, no resource URIs, no secrets or tokens.

const MAX_BODY_CHARS := 4096
const MAX_STATUS_LENGTH := 64

static func parse_health(json_text: String) -> Dictionary:
	if json_text.length() > MAX_BODY_CHARS:
		return _invalid("gateway_response_too_large")
	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		return _invalid("malformed_json")
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _invalid("malformed_json")
	var body: Dictionary = parsed
	var status: Variant = body.get("status", null)
	if typeof(status) != TYPE_STRING or status.is_empty() or status.length() > MAX_STATUS_LENGTH:
		return _invalid("invalid_gateway_status")
	var live: bool = status == "ok"
	return {
		"ok": true,
		"observation": {
			"state": "live" if live else "unavailable",
			"source": "KiloCore-Gateway/GET-health",
			"gateway_status": status,
			"observed_at_ms": 0,
			"error": "" if live else "gateway_not_ok"
		}
	}

static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
