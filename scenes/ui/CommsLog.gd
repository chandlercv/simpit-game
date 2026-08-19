extends Control
## Comms/mission log for the Chart display. Appends GameState comms entries
## as they're posted (e.g. sensor mode changes from the Tactical window —
## cross-display state flow through the one shared GameState).

@export var accent: Color = Color(0.45, 0.7, 1.0)

const SOURCE_COLORS := {
	"SYSTEM": Color(0.6, 0.65, 0.7),
	"SENSORS": Color(1.0, 0.72, 0.2),
	"HARBOR": Color(0.45, 0.7, 1.0),
	"SALVAGE": Color(1.0, 0.55, 0.3),
	"OPS": Color(0.3, 0.9, 0.78),
	"MARKET": Color(0.5, 1.0, 0.7),
}

@onready var _title: Label = %Title
@onready var _log: RichTextLabel = %Log


func _ready() -> void:
	_title.text = "COMMS LOG"
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", accent)
	_log.add_theme_font_size_override("normal_font_size", 15)
	_log.add_theme_font_size_override("bold_font_size", 15)
	for entry: Dictionary in GameState.comms:
		_append(entry)
	GameState.comms_posted.connect(_append)


func _append(entry: Dictionary) -> void:
	var seconds: float = entry["tick"] / GameState.TICK_RATE_HZ
	var source_color: Color = SOURCE_COLORS.get(entry["source"], Color(accent, 0.8))
	_log.append_text("[color=#%s][T+%07.1f][/color] [color=#%s][b]%s[/b][/color] — %s\n" % [
		Color(accent, 0.45).to_html(), seconds,
		source_color.to_html(), entry["source"], entry["text"]])
