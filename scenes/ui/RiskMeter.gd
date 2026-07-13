extends Control
## Structural-risk meter for the Tactical display. Reads the placeholder
## GameState.structural_risk until Phase 4, where SalvageSystem's structural
## graph drives it (risk spikes on load-bearing cuts, not a cut counter).

@export var accent: Color = Color(1.0, 0.72, 0.2)

const DANGER := Color(1.0, 0.3, 0.12)


func _ready() -> void:
	custom_minimum_size = Vector2(0, 64)
	GameState.structural_risk_changed.connect(func(_risk: float) -> void: queue_redraw())


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var risk: float = GameState.structural_risk
	var color := accent.lerp(DANGER, clampf((risk - 0.4) / 0.5, 0.0, 1.0))
	draw_string(font, Vector2(0, 16), "STRUCTURAL RISK",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, accent)
	draw_string(font, Vector2(0, 16), "%d%%" % roundi(risk * 100.0),
			HORIZONTAL_ALIGNMENT_RIGHT, size.x, 14, color)
	var bar := Rect2(0, 28, size.x, 20)
	draw_rect(bar, Color(accent, 0.5), false, 1.0)
	draw_rect(Rect2(bar.position + Vector2(2, 2),
			Vector2(maxf(bar.size.x - 4.0, 0.0) * risk, bar.size.y - 4.0)),
			Color(color, 0.8))
	for i in range(1, 10):
		var x := bar.position.x + bar.size.x * float(i) / 10.0
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.position.y + 4), Color(accent, 0.5), 1.0)
	draw_string(font, Vector2(0, 62),
			"RESIDUAL FRAME STRESS — SCAN BEFORE CUTTING",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(accent, 0.5))
