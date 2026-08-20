# HUD de course : vitesse, chrono et état des zones de validation invisibles.
class_name Hud
extends CanvasLayer

var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_font_size_override("font_size", 24)
	add_child(_label)

func update(state: CarState, race_state: RaceState) -> void:
	var speed_kmh: float = Fixed.to_float(FixedMath.length_2d(state.vit_x, state.vit_z)) * float(Horloge.TICKS_PAR_SECONDE) * 3.6
	var validation: String = "Zones : %d/%d" % [race_state.validated_zone_count, race_state.validation_zone_count]
	if not race_state.run_valid:
		validation = "TOUR INVALIDE — R pour recommencer"
	_label.text = "Vitesse : %d km/h\n%s\n%s" % [int(round(speed_kmh)), TimeFormat.format_ticks(race_state.current_elapsed), validation]
