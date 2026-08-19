# HUD minimal pour régler la conduite : vitesse et chrono.
class_name Hud
extends CanvasLayer

var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_font_size_override("font_size", 24)
	add_child(_label)

func update(state: CarState, tick_number: int) -> void:
	var speed_kmh: float = Fixed.to_float(FixedMath.length_2d(state.vit_x, state.vit_z)) * float(Horloge.TICKS_PAR_SECONDE) * 3.6
	_label.text = "Vitesse : %d km/h\n%s" % [int(round(speed_kmh)), TimeFormat.format_ticks(tick_number)]
