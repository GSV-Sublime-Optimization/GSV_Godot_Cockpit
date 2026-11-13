class_name PsShell
extends RefCounted

## Name of the PowerShell host to pass to OS.execute. Prefers PowerShell 7
## (pwsh) when it is on PATH and falls back to Windows PowerShell 5.1
## (powershell.exe), which ships with every Windows install. Cached after the
## first call so the `where` probe runs once per session.

static var _cached := ""

static func exe() -> String:
	if not OS.has_feature("windows"):
		return "pwsh"
	if _cached.is_empty():
		var output: Array = []
		_cached = "pwsh" if OS.execute("where", ["pwsh"], output, true, false) == 0 else "powershell"
	return _cached
