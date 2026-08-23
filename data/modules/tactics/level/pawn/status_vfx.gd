class_name StatusVFX
extends Node3D
## Les auras d'affliction d'un pion — poison, brûlure, paralysie, gel.
##
## Un empoisonné se lisait au journal et à sa fiche, jamais sur le plateau : deux
## brigands côte à côte, l'un mourant à petit feu et l'autre intact, avaient
## rigoureusement la même tête. Ce nœud donne un corps aux afflictions que
## [StatusEffects] résout déjà, [b]sans rien décider[/b] : il ne pose ni ne lève
## aucun statut, il montre ceux qui sont là.
##
## [b]Attaché au pion, contrairement à [BattleVFX].[/b] Les gerbes de coup sont
## brèves et doivent survivre à leur victime — elles vivent donc sous un nœud
## unique de la scène. Une aura, elle, dure des tours entiers et doit suivre son
## porteur d'une case à l'autre : elle est enfant du [TacticsPawn], en repère
## local (`local_coords`), et disparaît avec lui quand il tombe. Aucun ménage à
## faire à la mort, aucun risque d'aura orpheline au milieu du plateau.
##
## Un [CPUParticles3D] par statut, créé à la première pose et [b]réutilisé
## ensuite[/b] : à l'expiration on éteint l'émission, on ne détruit pas le nœud —
## un poison reposé trois tours plus tard rallume le sien sans rien reconstruire,
## et un pion ne portera jamais plus de nœuds qu'il n'y a de statuts au catalogue.
##
## Ce qui est montré (couleur, mouvement, quantité) est décidé par [StatusAura],
## une table pure et vérifiable en `--headless` — ici il n'y a que du réglage de
## particules. Et, comme [BattleVFX], [b]rien ne tourne sans écran[/b] :
## [method refresh] rend la main tout de suite en `--headless`.

const AURA = preload("res://data/models/view/pawn/status_aura.gd")

## Nom du nœud sous le pion — sert aussi à le retrouver d'un appel à l'autre.
const NODE_NAME: StringName = &"StatusVFX"


#region Point d'accroche
## Met les auras de [param pawn] en accord avec [param entries].
##
## Le seul point d'entrée : posez une affliction, faites-en expirer une, soignez
## tout — appelez ceci ensuite et l'écran suit. L'appel est idempotent, donc le
## rappeler pour rien ne coûte que la comparaison de deux listes courtes.
##
## [param entries] la liste d'afflictions telle que [Stats] la porte
## ([{status, turns}]) ; une liste vide éteint tout.
static func refresh(pawn: Node3D, entries: Array) -> void:
	if not pawn or not is_instance_valid(pawn) or not pawn.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return

	var node: StatusVFX = pawn.get_node_or_null(NodePath(NODE_NAME)) as StatusVFX
	var plan: Array = AURA.plan(entries)
	if not node:
		# Rien à montrer et rien de monté : le cas de l'immense majorité des
		# pions, qui ne doivent donc rien porter du tout.
		if plan.is_empty():
			return
		node = StatusVFX.new()
		node.name = NODE_NAME
		pawn.add_child(node)

	node.apply(plan)
#endregion


#region Auras
## Allume les auras du plan, éteint toutes les autres.
##
## [param plan] ce que rend [method StatusAura.plan].
func apply(plan: Array) -> void:
	var wanted: Dictionary = {}
	for raw: Variant in plan:
		var spec: Dictionary = raw
		wanted[str(spec["status"])] = spec

	# Ce qui n'est plus subi s'éteint, mais reste monté pour la prochaine fois.
	for child: Node in get_children():
		if child is CPUParticles3D and not wanted.has(String(child.name)):
			(child as CPUParticles3D).emitting = false

	for key: Variant in wanted:
		_light(str(key), wanted[key] as Dictionary)


## Éteint toutes les auras — ce que fait un antidote, ou une chute.
func clear() -> void:
	apply([])


## Allume (ou monte, la première fois) l'aura d'un statut.
func _light(key: String, spec: Dictionary) -> void:
	var node: CPUParticles3D = get_node_or_null(NodePath(key)) as CPUParticles3D
	if not node:
		node = _build(key, spec)
		if not node:
			return
	node.emitting = true


## Le nœud de particules d'une aura, réglé d'après [StatusAura].
##
## Rend `null` si l'image d'effet manque — le pion se passe alors d'aura plutôt
## que de porter un nœud qui ne dessine rien.
func _build(key: String, spec: Dictionary) -> CPUParticles3D:
	var mesh: Mesh = BattleVFX.particle_mesh(spec["texture"] as StringName,
		float(spec["size"]), bool(spec["additive"]))
	if not mesh:
		return null

	var speed: Vector2 = spec["speed"] as Vector2
	var node := CPUParticles3D.new()
	node.name = key
	node.mesh = mesh
	node.amount = int(spec["amount"])
	node.lifetime = float(spec["lifetime"])
	# **Une boucle, pas une bouffée.** L'affliction dure tant qu'elle dure :
	# `one_shot` reste faux et `explosiveness` à zéro, si bien que les grains
	# naissent en flux continu au lieu de partir tous ensemble.
	node.one_shot = false
	node.explosiveness = 0.0
	# **Repère local.** Le pion marche pendant que son aura tourne : en repère
	# monde, les grains resteraient semés sur la case de départ et le poison
	# ferait une traînée derrière l'unité au lieu de l'envelopper.
	node.local_coords = true
	node.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	node.emission_sphere_radius = float(spec["radius"])
	node.direction = Vector3.UP
	node.spread = float(spec["spread"])
	node.initial_velocity_min = speed.x
	node.initial_velocity_max = speed.y
	node.gravity = spec["gravity"] as Vector3
	node.damping_min = 0.2
	node.damping_max = 0.8
	node.scale_amount_min = 0.7
	node.scale_amount_max = 1.15
	node.color = spec["color"] as Color
	node.position = Vector3.UP * float(spec["height"])
	# Éteint avant d'entrer dans l'arbre, allumé par [method _light] : un
	# [CPUParticles3D] naît `emitting = true` et tirerait sa première salve avant
	# même que sa position ne soit posée.
	node.emitting = false
	add_child(node)
	return node
#endregion
