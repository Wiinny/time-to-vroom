# Outil hors-ligne : génère res://core/fixed_tables.gd.
# Lancé à la main, jamais par le jeu — une table produite à l'exécution avec
# sin() dépendrait de la libm de la machine et casserait le déterminisme.
#
#   "$GODOT" --headless --path . --script res://tools/gen_tables.gd
extends SceneTree

const TABLE_SIZE: int = 1024
const SCALE: int = 65536

func _initialize() -> void:
	var values: PackedStringArray = []
	for i in range(TABLE_SIZE):
		var angle_rad: float = TAU * float(i) / float(TABLE_SIZE)
		var v: int = int(round(sin(angle_rad) * float(SCALE)))
		values.append(str(v))

	var lines: PackedStringArray = []
	lines.append("# Fichier généré par tools/gen_tables.gd — ne pas éditer à la main.")
	lines.append("# Table de sinus sur un tour complet (angle Q16.16 : 65536 = 360°).")
	lines.append("class_name FixedTables")
	lines.append("")
	lines.append("const TABLE_SIZE: int = %d" % TABLE_SIZE)
	lines.append("const SIN: PackedInt32Array = [%s]" % ", ".join(values))
	lines.append("")

	var f := FileAccess.open("res://core/fixed_tables.gd", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()

	print("Tables générées : res://core/fixed_tables.gd (%d entrées)" % TABLE_SIZE)
	quit()
