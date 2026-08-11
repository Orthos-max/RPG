class_name TitleBackdrop
extends Control
## Fond animé de l'écran-titre — « Velmar : nuit et or ».
##
## Trois couches, de la plus lente à la plus vive : un halo radial qui respire,
## une poussière d'étoiles qui dérive, des braises qui montent. Rien d'autre
## qu'un dégradé et deux [CPUParticles2D] : pas de shader à compiler, pas de
## texture à charger, et un coût négligeable devant le reste du menu.
##
## **Sans écran, seul le dégradé reste** ([method animates]) : les particules et
## la respiration ne serviraient à personne en headless, où le fond n'est jamais
## dessiné. Le nœud reste montable dans les deux cas — les suites de tests
## montent l'écran-titre entier.
##
## Ce fond ne touche pas au son : la musique du titre est lancée par [Main].

## Cœur du halo, au-dessus du titre.
const C_GLOW := Color("#2d2050")
## Bord du halo : la nuit du menu, pour que la jointure ne se voie pas.
const C_NIGHT := Color("#141026")
## Braises : l'or de la charte.
const C_EMBER := Color("#f5c842")
## Poussière d'étoiles, à peine bleutée.
const C_STAR := Color("#cfd8ff")

## Durée d'une respiration complète du halo (aller-retour), en secondes.
const PULSE_TIME: float = 4.0
## Opacité du halo au creux de sa respiration.
const PULSE_LOW: float = 0.55

const EMBER_COUNT: int = 26
const STAR_COUNT: int = 20

var _glow: TextureRect = null
var _embers: CPUParticles2D = null
var _stars: CPUParticles2D = null


## Y a-t-il un écran à animer ?
static func animates() -> bool:
	return DisplayServer.get_name() != "headless"


func _ready() -> void:
	# Un décor ne prend pas les clics : les boutons du menu sont par-dessus.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_glow()
	if not animates():
		return

	_build_particles()
	resized.connect(_fit_particles)
	_fit_particles()

	var pulse: Tween = create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(_glow, "self_modulate:a", PULSE_LOW, PULSE_TIME * 0.5)
	pulse.tween_property(_glow, "self_modulate:a", 1.0, PULSE_TIME * 0.5)


## Le halo : un dégradé radial étiré sur tout l'écran.
func _build_glow() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, C_GLOW)
	gradient.set_color(1, C_NIGHT)

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	# Centré un peu haut : sous le titre, pas au milieu des boutons.
	texture.fill_from = Vector2(0.5, 0.33)
	texture.fill_to = Vector2(1.05, 1.0)
	texture.width = 256
	texture.height = 256

	_glow = TextureRect.new()
	_glow.name = "Glow"
	_glow.texture = texture
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_glow)


func _build_particles() -> void:
	_embers = _make_particles("Embers", EMBER_COUNT, C_EMBER, 7.0, -22.0, 0.55)
	_stars = _make_particles("Stars", STAR_COUNT, C_STAR, 11.0, -4.0, 0.35)
	# Les étoiles scintillent, les braises non : c'est ce qui les distingue.
	_stars.color_ramp = _twinkle_ramp(C_STAR)


## Une nappe de particules montantes, émise depuis le bas de l'écran.
##
## [param grain] est un facteur d'échelle du point lumineux ([method _dot]),
## pas une taille en pixels : c'est ce qu'attend `scale_amount`.
func _make_particles(node_name: String, amount: int, tint: Color, life: float,
		rise: float, grain: float) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.name = node_name
	particles.texture = _dot()
	particles.amount = amount
	particles.lifetime = life
	particles.preprocess = life  # l'écran s'ouvre déjà peuplé
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.gravity = Vector2(0, rise)
	particles.direction = Vector2(0, -1)
	particles.spread = 25.0
	particles.initial_velocity_min = 4.0
	particles.initial_velocity_max = 16.0
	# Un souffle latéral : sans lui les braises montent en colonnes rectilignes.
	particles.tangential_accel_min = -6.0
	particles.tangential_accel_max = 6.0
	particles.scale_amount_min = grain * 0.4
	particles.scale_amount_max = grain
	particles.color = Color(tint, 0.6)
	add_child(particles)
	return particles


## Le point lumineux d'une particule : un halo rond qui s'éteint sur ses bords.
##
## Sans texture, [CPUParticles2D] dessine un carré plein — des braises carrées.
## Seize pixels suffisent, le flou fait le reste.
static func _dot() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 16
	texture.height = 16
	return texture


## Apparition puis extinction : une étoile qui clignote plutôt qu'un point fixe.
func _twinkle_ramp(tint: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	ramp.colors = PackedColorArray([
		Color(tint, 0.0), Color(tint, 0.75), Color(tint, 0.0),
	])
	return ramp


## Recale l'émission sur la taille courante de l'écran.
##
## Les particules naissent sur toute la largeur, un peu sous le bord bas :
## elles entrent dans le cadre au lieu d'y apparaître.
func _fit_particles() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	for particles: CPUParticles2D in [_embers, _stars]:
		if not is_instance_valid(particles):
			continue
		particles.position = Vector2(size.x * 0.5, size.y + 16.0)
		particles.emission_rect_extents = Vector2(size.x * 0.5, 8.0)
