# Représentation visuelle des éléments de piste posés dans l'éditeur
# (map/track_data.gd::elements), pendant la course elle-même — jusqu'ici
# seul editor/track_editor.gd les affichait (aperçu de placement), rien ne
# les montrait plus une fois "Jouer" lancé. Purement cosmétique : ne décide
# de rien, ne lit jamais l'état de simulation. Un même repère cube coloré
# par type (ElementRoster.color_for_type(), partagé avec l'éditeur) pour
# tous les éléments — pas encore un modèle par type/variante, ça viendra
# avec le comportement de chaque élément (voir CLAUDE.md, section
# « Éléments de piste » : aucun n'a encore d'effet en simulation).
class_name TrackElementsView
extends Node3D

const MARKER_SIZE: Vector3 = Vector3(1.2, 1.2, 1.2)

func build(elements: Array[Dictionary]) -> void:
	for e in elements:
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = MARKER_SIZE
		marker.mesh = box
		marker.position = Vector3(
			Fixed.to_float(e["pos_x"]),
			Fixed.to_float(e["pos_y"]),
			Fixed.to_float(e["pos_z"])
		) + Vector3(0.0, MARKER_SIZE.y * 0.5, 0.0)
		marker.rotation.y = float(e["rotation"]) / 65536.0 * TAU
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ElementRoster.color_for_type(e["type"])
		marker.material_override = mat
		add_child(marker)
