class_name BattleVFX
extends Node3D
## Les effets visuels d'un assaut : éclat d'impact, étincelles, sang, soin, secousse.
##
## Le combat se résolvait en silence visuel : les points de vie tombaient dans
## le journal, mais rien ne se passait à l'écran — un coup critique et une
## esquive avaient exactement la même tête. Ce module donne un corps aux
## événements que [TacticsPawnCombatService] produit déjà, **sans toucher à leur
## résolution** : il ne lit ni ne modifie dégâts, précision ou morts, il les
## illustre après coup.
##
## Quatre images blanches suffisent à tout (`assets/textures/effects/`) : elles
## sont teintées à l'exécution, ce qui évite d'en dessiner une par école de
## magie. Le physique frappe en blanc-jaune, la magie en violet, le soin en or,
## la mort en rouge.
##
## **Un seul nœud pour toute la partie.** [method host] le crée à la volée sous
## la scène courante et le retient : les pions n'ont rien à porter, et les
## effets survivent au pion qui les a déclenchés — un mort continue de saigner
## une demi-seconde après avoir quitté la scène.
##
## **Rien ne tourne sans écran.** Les suites de tests jouent des batailles
## entières en `--headless`, où aucune texture n'a de sens : [method host] rend
## alors `null` et chaque point d'accroche devient un appel vide.

## Nature du coup porté — décide de la teinte et des particules.
enum Kind {
	PHYSICAL,  ## Lame, lance, hache, flèche : éclat blanc-jaune et étincelles
	MAGICAL,   ## Grimoire : éclat violet et poussière d'étoiles
	HEAL,      ## Bâton : éclat doré
}

## Dossier des quatre images d'effets (blanches, teintées à l'exécution).
const EFFECTS_DIR: String = "res://assets/textures/effects/"
## Hauteur du buste au-dessus de la case : là où un coup se voit.
const TORSO_HEIGHT: float = 0.9
## Durée de l'éclat d'impact.
const IMPACT_TIME: float = 0.15
## Écart entre deux éclats d'un même échange (attaque redoublée).
const STRIKE_INTERVAL: float = 0.18
## Amplitude de la secousse sur un critique, en unités de décalage de caméra.
const CRIT_SHAKE: float = 0.10

## Teinte de l'éclat, par nature de coup.
const IMPACT_TINTS: Dictionary = {
	Kind.PHYSICAL: Color(1.0, 0.96, 0.72),
	Kind.MAGICAL: Color(0.76, 0.55, 1.0),
	Kind.HEAL: Color(1.0, 0.92, 0.55),
}

## Le nœud d'effets de la partie en cours (voir [method host]).
static var current: BattleVFX = null

## Textures déjà lues, par nom de fichier sans extension.
static var _textures: Dictionary = {}
## Matériaux de particules déjà bâtis, par clé « nom:mode de fondu ».
static var _materials: Dictionary = {}

## La secousse en cours, pour ne pas en superposer deux (voir [method screen_shake]).
var _shake: Tween = null


#region Points d'accroche
## Le nœud d'effets, créé au besoin — ou `null` quand il n'y a pas d'écran.
##
## [param from] sert seulement à retrouver l'arbre de scène : n'importe quel
## nœud en scène fait l'affaire (le pion qui frappe, en pratique).
static func host(from: Node) -> BattleVFX:
	if not from or not is_instance_valid(from):
		return null
	if DisplayServer.get_name() == "headless":
		return null
	if is_instance_valid(current) and current.is_inside_tree():
		return current

	var tree: SceneTree = from.get_tree()
	if not tree:
		return null
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	if not parent:
		return null

	var vfx := BattleVFX.new()
	vfx.name = "BattleVFX"
	parent.add_child(vfx)
	current = vfx
	return vfx


## Illustre un coup porté : éclat, particules, et secousse si c'est un critique.
##
## [param victim] est le pion touché — sa position est relevée tout de suite,
## car une riposte mortelle peut le retirer de la scène avant la fin des effets.
## [param strikes] compte les coups portés (2 sur une attaque redoublée), et
## [param delay] décale l'ensemble : l'échange entier se résout en une image,
## mais la riposte ne doit pas s'afficher en même temps que l'assaut.
static func play_strike(victim: Node3D, magical: bool, crit: bool,
		strikes: int = 1, delay: float = 0.0) -> void:
	var vfx: BattleVFX = host(victim)
	if not vfx or not is_instance_valid(victim):
		return

	var at: Vector3 = victim.global_position + Vector3.UP * TORSO_HEIGHT
	var kind: int = Kind.MAGICAL if magical else Kind.PHYSICAL

	# L'attaque redoublée frappe deux fois : deux éclats, décalés, sinon le
	# second se confond avec le premier et le doublement ne se voit pas.
	for i: int in maxi(strikes, 1):
		# Le critique porte le premier coup : c'est lui qui secoue la vue.
		var moment: float = delay + float(i) * STRIKE_INTERVAL
		if is_zero_approx(moment):
			vfx._strike_at(at, kind, crit)
		else:
			vfx._strike_later(at, kind, crit and i == 0, moment)

	if crit:
		if is_zero_approx(delay):
			vfx.screen_shake(vfx._active_camera(), CRIT_SHAKE)
		else:
			vfx._shake_later(delay)


## Illustre une chute : une gerbe rouge à l'endroit où le pion tombe.
static func play_death(victim: Node3D) -> void:
	var vfx: BattleVFX = host(victim)
	if not vfx:
		return
	vfx.blood(victim.global_position + Vector3.UP * TORSO_HEIGHT)


## Illustre un soin : une remontée de lueurs dorées sur le soigné.
static func play_heal(target: Node3D) -> void:
	var vfx: BattleVFX = host(target)
	if not vfx:
		return
	vfx.impact(target.global_position + Vector3.UP * TORSO_HEIGHT, Kind.HEAL)
	vfx.heal_particles(target.global_position)
#endregion


#region Effets
## Un éclat bref à [param target_pos], teinté selon [param kind] ([enum Kind]).
##
## Le sursaut d'échelle fait tout le travail : un éclat qui grandit en
## s'effaçant se lit même à 0,15 seconde, un éclat fixe passe inaperçu.
func impact(target_pos: Vector3, kind: int = Kind.PHYSICAL) -> void:
	var tex: Texture2D = _texture(&"impact")
	if not tex:
		return

	var flash := Sprite3D.new()
	flash.texture = tex
	flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flash.shaded = false
	# L'éclat doit se voir **par-dessus** la figurine qu'il frappe : sans cela il
	# disparaît derrière elle une fois sur deux, selon l'angle de la caméra.
	flash.no_depth_test = true
	flash.render_priority = 2
	flash.pixel_size = 0.014
	flash.modulate = IMPACT_TINTS.get(kind, IMPACT_TINTS[Kind.PHYSICAL]) as Color
	flash.scale = Vector3.ONE * 0.55
	add_child(flash)
	flash.global_position = target_pos

	var tween: Tween = flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 1.3, IMPACT_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "modulate:a", 0.0, IMPACT_TIME).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(flash.queue_free)


## Gerbe d'étincelles orangées : le choc de deux pièces de métal.
func sparks(target_pos: Vector3) -> void:
	_burst(&"spark", target_pos, Color(1.0, 0.72, 0.28), {
		"amount": 14, "lifetime": 0.45, "speed": Vector2(1.6, 3.4),
		"spread": 60.0, "gravity": Vector3(0, -6.0, 0), "size": 0.10,
		"additive": true,
	})


## Poussière d'étoiles violette et cyan : la marque d'un sort.
func magic_particles(target_pos: Vector3) -> void:
	_burst(&"mote", target_pos, Color(0.72, 0.52, 1.0), {
		"amount": 18, "lifetime": 0.7, "speed": Vector2(0.5, 1.4),
		"spread": 180.0, "gravity": Vector3(0, 0.6, 0), "size": 0.13,
		"additive": true,
	})
	_burst(&"mote", target_pos, Color(0.45, 0.9, 1.0), {
		"amount": 8, "lifetime": 0.8, "speed": Vector2(0.3, 1.0),
		"spread": 180.0, "gravity": Vector3(0, 0.9, 0), "size": 0.09,
		"additive": true,
	})


## Gouttes rouges qui retombent : une unité vient de tomber.
func blood(target_pos: Vector3) -> void:
	_burst(&"droplet", target_pos, Color(0.72, 0.06, 0.09), {
		"amount": 22, "lifetime": 0.9, "speed": Vector2(1.2, 3.0),
		"spread": 75.0, "gravity": Vector3(0, -9.0, 0), "size": 0.11,
		"additive": false,
	})


## Lueurs dorées qui montent le long du soigné.
##
## [param target_pos] est pris **aux pieds** : le soin remonte, il ne retombe
## pas — c'est ce qui le distingue au premier coup d'œil d'un coup encaissé.
func heal_particles(target_pos: Vector3) -> void:
	_burst(&"mote", target_pos + Vector3.UP * 0.1, Color(1.0, 0.88, 0.42), {
		"amount": 20, "lifetime": 1.0, "speed": Vector2(1.0, 1.9),
		"spread": 12.0, "gravity": Vector3(0, 1.2, 0), "size": 0.12,
		"additive": true, "radius": 0.35,
	})
	_burst(&"mote", target_pos + Vector3.UP * 0.1, Color(0.55, 1.0, 0.6), {
		"amount": 10, "lifetime": 1.0, "speed": Vector2(0.8, 1.6),
		"spread": 12.0, "gravity": Vector3(0, 1.0, 0), "size": 0.09,
		"additive": true, "radius": 0.35,
	})


## Secoue brièvement la vue — réservé aux critiques.
##
## Ce sont `h_offset`/`v_offset` de la [Camera3D] qui bougent, jamais sa
## position : la caméra tactique est un [CharacterBody3D] que son propre service
## repositionne à chaque image, et lui disputer sa position ferait sursauter la
## vue sans jamais la remettre d'aplomb. Le décalage d'objectif, lui,
## n'appartient à personne d'autre.
##
## [param camera] accepte la [TacticsCamera] comme sa [Camera3D] interne.
func screen_shake(camera: Node, amount: float = CRIT_SHAKE, duration: float = 0.24) -> void:
	var cam: Camera3D = _camera_node(camera)
	if not cam:
		return

	# Deux critiques coup sur coup : sans cette coupure, les deux secousses se
	# marchent dessus et la caméra reste décalée une fois la seconde finie.
	if is_instance_valid(_shake) and _shake.is_valid():
		_shake.kill()

	const STEPS: int = 4
	var step: float = duration / float(STEPS + 1)
	_shake = cam.create_tween()
	for i: int in STEPS:
		var falloff: float = amount * (1.0 - float(i) / float(STEPS))
		_shake.tween_property(cam, "h_offset", randf_range(-falloff, falloff), step)
		_shake.parallel().tween_property(cam, "v_offset", randf_range(-falloff, falloff), step)
	_shake.tween_property(cam, "h_offset", 0.0, step)
	_shake.parallel().tween_property(cam, "v_offset", 0.0, step)


## Le pas en avant de l'assaillant, puis son retour.
##
## Un pion frappait sans bouger d'un pouce : l'assaut ne se lisait que dans la
## barre de vie de la cible. Le tween porte sur le pion lui-même — sa figurine
## a sa position pilotée par l'[AnimationTree], qui l'écraserait à l'image
## suivante — et il **revient toujours à son point de départ**, si bien que la
## case occupée n'est jamais en jeu.
##
## [param attacker] et [param target] sont des [TacticsPawn] ; sans écran,
## l'appel ne fait rien.
static func lunge(attacker: Node3D, target: Node3D) -> void:
	if not host(attacker) or not is_instance_valid(target):
		return

	var origin: Vector3 = attacker.position
	var toward: Vector3 = target.global_position - attacker.global_position
	toward.y = 0.0
	if toward.length() < 0.01:
		return

	# Assez pour se voir, pas assez pour empiéter sur la case d'en face.
	var reach: Vector3 = toward.normalized() * 0.35
	var tween: Tween = attacker.create_tween()
	tween.tween_property(attacker, "position", origin + reach, 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(attacker, "position", origin, 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
#endregion


#region Internes
## Un éclat, plus les particules qui vont avec sa nature.
func _strike_at(at: Vector3, kind: int, crit: bool) -> void:
	impact(at, kind)
	if kind == Kind.MAGICAL:
		magic_particles(at)
	else:
		sparks(at)
	# Un critique porte deux fois plus loin : une seconde gerbe, plus large.
	if crit:
		if kind == Kind.MAGICAL:
			magic_particles(at + Vector3.UP * 0.25)
		else:
			sparks(at + Vector3.UP * 0.25)


## Le même éclat, mais dans [param delay] secondes.
func _strike_later(at: Vector3, kind: int, crit: bool, delay: float) -> void:
	var tree: SceneTree = get_tree()
	if not tree:
		return
	tree.create_timer(delay).timeout.connect(
		func() -> void:
			if is_instance_valid(self) and is_inside_tree():
				_strike_at(at, kind, crit)
	)


## La secousse d'un critique, mais dans [param delay] secondes.
func _shake_later(delay: float) -> void:
	var tree: SceneTree = get_tree()
	if not tree:
		return
	tree.create_timer(delay).timeout.connect(
		func() -> void:
			if is_instance_valid(self) and is_inside_tree():
				screen_shake(_active_camera(), CRIT_SHAKE)
	)


## Une bouffée de particules à usage unique, qui se retire seule.
##
## [param cfg] : `amount`, `lifetime`, `speed` ([Vector2] min/max), `spread`,
## `gravity`, `size`, `additive`, `radius`.
func _burst(tex_name: StringName, at: Vector3, tint: Color, cfg: Dictionary) -> void:
	var mesh: Mesh = _particle_mesh(tex_name, float(cfg.get("size", 0.1)),
		bool(cfg.get("additive", true)))
	if not mesh:
		return

	var lifetime: float = float(cfg.get("lifetime", 0.6))
	var speed: Vector2 = cfg.get("speed", Vector2(1.0, 2.0)) as Vector2

	var burst := CPUParticles3D.new()
	burst.mesh = mesh
	burst.amount = int(cfg.get("amount", 12))
	burst.lifetime = lifetime
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = float(cfg.get("radius", 0.18))
	burst.direction = Vector3.UP
	burst.spread = float(cfg.get("spread", 45.0))
	burst.initial_velocity_min = speed.x
	burst.initial_velocity_max = speed.y
	burst.gravity = cfg.get("gravity", Vector3(0, -4.0, 0)) as Vector3
	burst.damping_min = 0.5
	burst.damping_max = 1.5
	burst.scale_amount_min = 0.6
	burst.scale_amount_max = 1.2
	burst.color = tint
	add_child(burst)
	burst.global_position = at
	burst.emitting = true

	# `one_shot` cesse d'émettre mais ne se retire pas : sans ce retrait, une
	# bataille finit avec des centaines de nœuds éteints sous le même parent.
	_free_after(burst, lifetime + 0.5)


## Retire [param node] de la scène dans [param seconds].
func _free_after(node: Node, seconds: float) -> void:
	var tree: SceneTree = get_tree()
	if not tree:
		node.queue_free()
		return
	tree.create_timer(seconds).timeout.connect(
		func() -> void:
			if is_instance_valid(node):
				node.queue_free()
	)


## La texture d'un effet, lue une fois pour toutes (ou `null` si elle manque).
static func _texture(tex_name: StringName) -> Texture2D:
	if _textures.has(tex_name):
		return _textures[tex_name] as Texture2D

	var path: String = "%s%s.png" % [EFFECTS_DIR, tex_name]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	else:
		push_warning("[BattleVFX] Image d'effet absente : %s" % path)
	_textures[tex_name] = tex
	return tex


## Le quad texturé que dessinent les particules.
##
## Le matériau est mis en cache : chacun coûte une compilation de shader, et
## une bataille en demanderait un par coup porté.
static func _particle_mesh(tex_name: StringName, size: float, additive: bool) -> Mesh:
	var tex: Texture2D = _texture(tex_name)
	if not tex:
		return null

	var key: String = "%s:%s" % [tex_name, "add" if additive else "mix"]
	var material: StandardMaterial3D = _materials.get(key, null) as StandardMaterial3D
	if not material:
		material = StandardMaterial3D.new()
		material.albedo_texture = tex
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive \
			else BaseMaterial3D.BLEND_MODE_MIX
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.particles_anim_h_frames = 1
		material.particles_anim_v_frames = 1
		# Sans cela, la teinte passée à [CPUParticles3D] serait ignorée et tous
		# les effets sortiraient blancs.
		material.vertex_color_use_as_albedo = true
		material.disable_receive_shadows = true
		_materials[key] = material

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	return quad


## La [Camera3D] à secouer, à partir d'une [TacticsCamera] ou d'elle-même.
func _camera_node(camera: Node) -> Camera3D:
	if camera is Camera3D:
		return camera as Camera3D
	if camera and camera.get("cam_node") is Camera3D:
		return camera.get("cam_node") as Camera3D
	return _active_camera()


## La caméra qui rend la scène, faute de mieux.
func _active_camera() -> Camera3D:
	var viewport: Viewport = get_viewport()
	return viewport.get_camera_3d() if viewport else null
#endregion
