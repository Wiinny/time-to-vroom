# Conversion -> texte "m:ss.mmm", partagée par ui/hud.gd, ui/finish_menu.gd et
# ui/track_select.gd. Le tick est la seule horloge de la simulation (cf.
# CLAUDE.md) : pas de Time.get_ticks_msec() ici. format_ms() est la fonction
# principale — sim/race_state.gd fournit désormais un chrono déjà interpolé
# au sous-tick, en millisecondes (voir RaceState.finish_ms). format_ticks()
# reste une enveloppe pour l'affichage en direct (HUD), où le sous-tick n'a
# pas de sens.
class_name TimeFormat

static func format_ms(total_ms: int) -> String:
	var minutes: int = total_ms / 60000
	var seconds: int = (total_ms / 1000) % 60
	var millis: int = total_ms % 1000
	return "%d:%02d.%03d" % [minutes, seconds, millis]

static func format_ticks(tick_number: int) -> String:
	return format_ms(tick_number * Horloge.MS_PAR_TICK)
