class_name CielTheme
extends RefCounted
## Le thème d'interface de Ciel Emblem, bâti depuis la [Palette].
##
## Le jeu n'avait aucun thème : chaque `Control` tombait donc sur celui de Godot.
## Les boutons étaient repeints écran par écran, mais tout le reste — champs de
## saisie, listes déroulantes, compteurs, cases à cocher, barres de défilement —
## gardait le gris d'usine, ses flèches et ses bordures, au milieu du bleu de
## nuit. C'est ce mélange qui donnait au jeu son air de projet Godot, plus encore
## que les couleurs.
##
## Tout est construit en code, comme le décor du plateau ([TacticsScenery]) :
## aucune image à produire, aucune ressource à ouvrir dans l'éditeur, et un seul
## fichier à relire pour savoir de quoi l'interface est faite. Les rares icônes
## (flèches d'un compteur, case à cocher) sont dessinées ici même, pixel par
## pixel, plutôt qu'empruntées au thème d'usine — ce sont elles qui trahissaient
## l'origine le plus vite.
##
## S'applique en deux gestes, tous deux dans `Main._ready` : sur la fenêtre
## racine ([method apply_to_tree]), et sur chaque interface que la propagation
## n'atteint pas ([method adopt]).
##
## [b]Variations disponibles[/b] (`theme_type_variation`) :
## [codeblock]
## TitreEmbleme    — le nom du jeu, le titre d'un chapitre (Cinzel, or)
## TitreSection    — un en-tête à l'intérieur d'un écran
## TexteDiscret    — légende, unité, rappel
## BoutonPrincipal — l'action que l'écran attend (or)
## BoutonDanger    — l'action qui ne se défait pas (pourpre)
## [/codeblock]

## Le thème n'est bâti qu'une fois : il est identique pour tout le monde, et
## reconstruire ses quarante StyleBox à chaque écran ne servirait à rien.
static var _cached: Theme = null


## Le thème du jeu.
static func build() -> Theme:
	if _cached:
		return _cached

	var theme := Theme.new()
	theme.default_font = _figures(Palette.FONT_BODY)
	theme.default_font_size = Palette.SIZE_BODY

	_style_button(theme)
	_style_labels(theme)
	_style_panels(theme)
	_style_fields(theme)
	_style_popup(theme)
	_style_scrollbars(theme)
	_style_separators(theme)
	_style_variations(theme)

	_cached = theme
	return theme


## Pose le thème sur la fenêtre racine.
##
## Attention : cela ne suffit pas à couvrir le jeu. Un `Theme` posé sur une
## fenêtre descend à ses `Control`, mais la propagation s'arrête net sur un
## `CanvasLayer`, qui n'est ni l'un ni l'autre — et tous les écrans du jeu sont
## des `Control` posés dans un `CanvasLayer` par `Main._mount_ui`. Le raccord
## est fait dans `Main` : voir [method adopt].
static func apply_to_tree(tree: SceneTree) -> void:
	if tree and tree.root:
		tree.root.theme = build()


## Pose la charte sur une interface qu'un `CanvasLayer` isole de la racine.
##
## Sans appelant, cette fonction ne sert à rien ; c'est `Main` qui la branche
## sur `SceneTree.node_added`, une fois, pour que la question ne se repose pas
## à chaque écran ajouté.
static func adopt(node: Node) -> void:
	if node is Control and node.get_parent() is CanvasLayer:
		(node as Control).theme = build()


#region Boutons
static func _style_button(theme: Theme) -> void:
	theme.set_font("font", "Button", _figures(Palette.FONT_BODY_BOLD))
	theme.set_font_size("font_size", "Button", Palette.SIZE_BODY)

	theme.set_stylebox("normal", "Button", _box(Palette.RELIEF, Palette.EDGE))
	theme.set_stylebox("hover", "Button", _box(Palette.RELIEF_HI, Palette.GOLD_DIM))
	# Un bouton s'enfonce : la version pressée est plus sombre, jamais plus
	# claire — l'inverse donne l'impression que le clic n'a pas pris.
	theme.set_stylebox("pressed", "Button", _box(Palette.RELIEF_LO, Palette.GOLD))
	theme.set_stylebox("disabled", "Button", _box(Palette.RELIEF_OFF, Palette.EDGE_OFF))
	theme.set_stylebox("focus", "Button", _focus_box())

	theme.set_color("font_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_color", "Button", Palette.TEXT_BRIGHT)
	theme.set_color("font_pressed_color", "Button", Palette.GOLD)
	theme.set_color("font_focus_color", "Button", Palette.TEXT_BRIGHT)
	theme.set_color("font_disabled_color", "Button", Palette.TEXT_OFF)

	# La liste déroulante est un bouton qui s'ouvre : elle doit lui ressembler.
	# Sans ces lignes, elle retombe sur le thème d'usine — c'était le cas le
	# plus voyant de l'éditeur de personnages.
	#
	# Une exception : sa hauteur. Une liste déroulante se retrouve presque
	# toujours dans une colonne de formulaire, alignée sur des champs de saisie
	# et des compteurs ; avec la marge d'un bouton (9 px) elle dépasse d'eux de
	# quatre pixels et toute la colonne se met à onduler. Elle prend donc la
	# marge d'un champ (7 px), pas celle d'un bouton.
	var drop_normal := _box(Palette.RELIEF, Palette.EDGE, Palette.RADIUS, 16, 7)
	var drop_hover := _box(Palette.RELIEF_HI, Palette.GOLD_DIM, Palette.RADIUS, 16, 7)
	var drop_pressed := _box(Palette.RELIEF_LO, Palette.GOLD, Palette.RADIUS, 16, 7)
	var drop_off := _box(Palette.RELIEF_OFF, Palette.EDGE_OFF, Palette.RADIUS, 16, 7)
	theme.set_stylebox("normal", "OptionButton", drop_normal)
	theme.set_stylebox("hover", "OptionButton", drop_hover)
	theme.set_stylebox("pressed", "OptionButton", drop_pressed)
	theme.set_stylebox("disabled", "OptionButton", drop_off)
	theme.set_stylebox("focus", "OptionButton", _focus_box())
	for item in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		theme.set_color(item, "OptionButton", theme.get_color(item, "Button"))
	theme.set_font("font", "OptionButton", _figures(Palette.FONT_BODY_BOLD))
	theme.set_font_size("font_size", "OptionButton", Palette.SIZE_BODY)
	theme.set_icon("arrow", "OptionButton", _chevron_icon())
	# De la place à droite pour le chevron, sinon il chevauche le texte.
	theme.set_constant("arrow_margin", "OptionButton", 8)

	theme.set_font("font", "CheckBox", _figures(Palette.FONT_BODY))
	theme.set_color("font_color", "CheckBox", Palette.TEXT)
	theme.set_color("font_hover_color", "CheckBox", Palette.TEXT_BRIGHT)
	theme.set_color("font_disabled_color", "CheckBox", Palette.TEXT_OFF)
	theme.set_icon("checked", "CheckBox", _checkbox_icon(true))
	theme.set_icon("unchecked", "CheckBox", _checkbox_icon(false))
	theme.set_icon("checked_disabled", "CheckBox", _checkbox_icon(true, true))
	theme.set_icon("unchecked_disabled", "CheckBox", _checkbox_icon(false, true))
	theme.set_stylebox("focus", "CheckBox", _focus_box())
#endregion


#region Étiquettes
static func _style_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", Palette.TEXT)
	theme.set_font_size("font_size", "Label", Palette.SIZE_BODY)
	theme.set_color("default_color", "RichTextLabel", Palette.TEXT)
	theme.set_stylebox("normal", "RichTextLabel", _empty_box())
#endregion


#region Panneaux
static func _style_panels(theme: Theme) -> void:
	var panel := _box(Palette.PANEL, Palette.EDGE_SOFT, Palette.RADIUS_PANEL, 14, 12)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)
	# Le conteneur défilant ne doit pas peindre de fond : il en hérite un du
	# thème d'usine, qui se voit dès qu'on le pose sur un panneau déjà teinté.
	theme.set_stylebox("panel", "ScrollContainer", _empty_box())
#endregion


#region Champs de saisie
static func _style_fields(theme: Theme) -> void:
	var field := _box(Palette.FIELD, Palette.EDGE_SOFT, Palette.RADIUS, 10, 7)
	var field_focus := _box(Palette.FIELD, Palette.GOLD, Palette.RADIUS, 10, 7)
	field_focus.set_border_width_all(Palette.BORDER_FOCUS)

	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_stylebox("read_only", "LineEdit", _box(Palette.RELIEF_OFF, Palette.EDGE_OFF,
		Palette.RADIUS, 10, 7))
	theme.set_color("font_color", "LineEdit", Palette.TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Palette.TEXT_OFF)
	theme.set_color("font_uneditable_color", "LineEdit", Palette.TEXT_OFF)
	theme.set_color("caret_color", "LineEdit", Palette.GOLD)
	theme.set_color("selection_color", "LineEdit", Palette.fade(Palette.RELIEF_HI, 0.8))
	theme.set_font("font", "LineEdit", _figures(Palette.FONT_BODY))

	# Le compteur dessine un champ de saisie plus ses deux flèches. Le champ
	# suit la règle ci-dessus ; les flèches d'usine, elles, sont grises.
	theme.set_icon("updown", "SpinBox", _updown_icon())
#endregion


#region Menus déroulants
static func _style_popup(theme: Theme) -> void:
	theme.set_stylebox("panel", "PopupMenu", _box(Palette.PANEL, Palette.GOLD_DIM,
		Palette.RADIUS_PANEL, 6, 6))
	theme.set_stylebox("hover", "PopupMenu", _box(Palette.RELIEF_HI, Palette.RELIEF_HI,
		Palette.RADIUS, 8, 5))
	theme.set_color("font_color", "PopupMenu", Palette.TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Palette.TEXT_BRIGHT)
	theme.set_color("font_disabled_color", "PopupMenu", Palette.TEXT_OFF)
	theme.set_color("font_separator_color", "PopupMenu", Palette.GOLD_DIM)
	theme.set_font("font", "PopupMenu", _figures(Palette.FONT_BODY))
	theme.set_font_size("font_size", "PopupMenu", Palette.SIZE_BODY)
	theme.set_constant("v_separation", "PopupMenu", 6)
#endregion


#region Barres de défilement
static func _style_scrollbars(theme: Theme) -> void:
	# Une gouttière sombre et un curseur bleu : la barre doit se lire sans
	# attirer l'œil, donc pas d'or ici.
	var gutter := _box(Palette.fade(Palette.INK, 0.5), Palette.fade(Palette.INK, 0.0), 4, 3, 3)
	var grabber := _box(Palette.RELIEF, Palette.fade(Palette.RELIEF, 0.0), 4, 3, 3)
	var grabber_hi := _box(Palette.RELIEF_HI, Palette.fade(Palette.RELIEF_HI, 0.0), 4, 3, 3)

	for axis in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", axis, gutter)
		theme.set_stylebox("scroll_focus", axis, gutter)
		theme.set_stylebox("grabber", axis, grabber)
		theme.set_stylebox("grabber_highlight", axis, grabber_hi)
		theme.set_stylebox("grabber_pressed", axis, grabber_hi)
#endregion


#region Séparateurs
static func _style_separators(theme: Theme) -> void:
	var line := StyleBoxLine.new()
	line.color = Palette.fade(Palette.GOLD_DIM, 0.55)
	line.thickness = 1
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_constant("separation", "HSeparator", 10)

	var vline := StyleBoxLine.new()
	vline.color = Palette.fade(Palette.GOLD_DIM, 0.55)
	vline.thickness = 1
	vline.vertical = true
	theme.set_stylebox("separator", "VSeparator", vline)
	theme.set_constant("separation", "VSeparator", 10)
#endregion


#region Variations
## Les cinq rôles nommés de la charte.
##
## Un écran demande `theme_type_variation = "TitreEmbleme"` au lieu d'empiler
## trois `add_theme_*_override` — et le jour où le titre change d'allure, il
## change partout.
static func _style_variations(theme: Theme) -> void:
	# Cinzel est une police variable : sa graisse se règle entre 400 et 900.
	#
	# Le piège, mesuré : `variation_opentype` n'accepte que le tag *entier* de
	# l'axe. Avec la clé texte `{"wght": 700}` — celle qui marche pour
	# `opentype_features` juste à côté — Godot n'échoue pas, il ignore : la
	# graisse reste à 400 et rien ne le dit. D'où `name_to_tag`.
	var weight_axis: int = TextServerManager.get_primary_interface().name_to_tag("weight")
	var cinzel := FontVariation.new()
	cinzel.base_font = Palette.FONT_TITLE
	cinzel.variation_opentype = {weight_axis: 700}

	theme.set_type_variation("TitreEmbleme", "Label")
	theme.set_font("font", "TitreEmbleme", cinzel)
	theme.set_font_size("font_size", "TitreEmbleme", Palette.SIZE_TITLE)
	theme.set_color("font_color", "TitreEmbleme", Palette.GOLD)
	# Une ombre portée courte : les capitales gravées ont besoin d'une épaisseur,
	# sinon elles flottent sur le fond de nuit.
	theme.set_color("font_shadow_color", "TitreEmbleme", Palette.fade(Color.BLACK, 0.6))
	theme.set_constant("shadow_offset_x", "TitreEmbleme", 2)
	theme.set_constant("shadow_offset_y", "TitreEmbleme", 2)

	theme.set_type_variation("TitreSection", "Label")
	theme.set_font("font", "TitreSection", cinzel)
	theme.set_font_size("font_size", "TitreSection", Palette.SIZE_HEADING)
	theme.set_color("font_color", "TitreSection", Palette.GOLD)

	theme.set_type_variation("TexteDiscret", "Label")
	theme.set_font_size("font_size", "TexteDiscret", Palette.SIZE_SMALL)
	theme.set_color("font_color", "TexteDiscret", Palette.TEXT_DIM)

	# L'action que l'écran attend : de l'or, une seule fois par écran. Le texte
	# y est sombre — de l'or sur du blanc ne se lit pas.
	theme.set_type_variation("BoutonPrincipal", "Button")
	theme.set_stylebox("normal", "BoutonPrincipal", _box(Palette.GOLD, Palette.GOLD))
	theme.set_stylebox("hover", "BoutonPrincipal", _box(
		Palette.shade(Palette.GOLD, 0.15), Palette.TEXT_BRIGHT))
	theme.set_stylebox("pressed", "BoutonPrincipal", _box(
		Palette.shade(Palette.GOLD, -0.2), Palette.GOLD))
	theme.set_color("font_color", "BoutonPrincipal", Palette.INK)
	theme.set_color("font_hover_color", "BoutonPrincipal", Palette.INK)
	theme.set_color("font_pressed_color", "BoutonPrincipal", Palette.INK)

	theme.set_type_variation("BoutonDanger", "Button")
	theme.set_stylebox("normal", "BoutonDanger", _box(Palette.CRIMSON_LO, Palette.CRIMSON))
	theme.set_stylebox("hover", "BoutonDanger", _box(Palette.CRIMSON, Palette.TEXT_BRIGHT))
	theme.set_stylebox("pressed", "BoutonDanger", _box(
		Palette.shade(Palette.CRIMSON_LO, -0.2), Palette.CRIMSON))
	theme.set_color("font_color", "BoutonDanger", Palette.TEXT_BRIGHT)
#endregion


#region Fabrique
## La police, chiffres redressés.
##
## Alegreya Sans compose par défaut des chiffres [i]elzéviriens[/i] : hauteurs
## inégales, certains descendant sous la ligne. C'est fait pour du roman, où ils
## se fondent dans le texte — exactement l'inverse de ce qu'on veut ici, où un
## PV et un taux de critique doivent se lire d'un coup d'œil. `lnum` les remet
## tous à la hauteur des capitales, `tnum` leur donne la même largeur pour que
## deux nombres empilés s'alignent sur leurs colonnes.
static func _figures(base: Font) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = base
	font.opentype_features = {"lnum": 1, "tnum": 1}
	return font


## Un fond plein bordé, aux mesures de la charte.
static func _box(bg: Color, border: Color, radius: int = Palette.RADIUS,
		pad_x: int = 16, pad_y: int = 9) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(Palette.BORDER)
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


## Le cadre de focus : de l'or, rien derrière.
static func _focus_box() -> StyleBoxFlat:
	var box := _box(Palette.fade(Palette.GOLD, 0.0), Palette.GOLD)
	box.set_border_width_all(Palette.BORDER_FOCUS)
	return box


## Un fond qui ne peint rien — pour effacer un fond d'usine.
static func _empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()
#endregion


#region Icônes dessinées
## Les deux flèches d'un compteur, empilées.
##
## Godot en fournit une paire grise que rien ne permet de recolorer : la
## redessiner coûte vingt lignes et retire le dernier gris de l'écran.
static func _updown_icon() -> ImageTexture:
	var image := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_arrow(image, 5, 4, 5, 1, Palette.TEXT_DIM)   # pointe en haut
	_arrow(image, 5, 17, 5, -1, Palette.TEXT_DIM)  # pointe en bas
	return ImageTexture.create_from_image(image)


## Le chevron d'une liste déroulante.
static func _chevron_icon() -> ImageTexture:
	var image := Image.create(14, 10, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_arrow(image, 6, 8, 6, -1, Palette.GOLD)
	return ImageTexture.create_from_image(image)


## Une case à cocher : cadre sombre, pastille d'or quand elle est cochée.
##
## Un carré plein plutôt qu'une coche dessinée — à 20 px, une coche tracée au
## pixel est une bouillie, un carré reste net.
static func _checkbox_icon(checked: bool, off: bool = false) -> ImageTexture:
	const SIDE: int = 20
	var image := Image.create(SIDE, SIDE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var edge: Color = Palette.EDGE_OFF if off else (Palette.GOLD_DIM if checked else Palette.EDGE)
	var mark: Color = Palette.TEXT_OFF if off else Palette.GOLD

	for x in SIDE:
		for y in SIDE:
			var on_edge: bool = x == 0 or y == 0 or x == SIDE - 1 or y == SIDE - 1
			if on_edge:
				image.set_pixel(x, y, edge)
			elif x >= 5 and x < SIDE - 5 and y >= 5 and y < SIDE - 5:
				image.set_pixel(x, y, mark if checked else Palette.FIELD)
			else:
				image.set_pixel(x, y, Palette.FIELD)
	return ImageTexture.create_from_image(image)


## Un triangle plein : pointe en ([param cx], [param tip_y]), s'élargissant
## d'un pixel par rangée dans le sens [param dir] (+1 vers le bas, -1 vers le
## haut) sur [param height] rangées.
static func _arrow(image: Image, cx: int, tip_y: int, height: int, dir: int,
		color: Color) -> void:
	for row in height:
		var y: int = tip_y + row * dir
		if y < 0 or y >= image.get_height():
			continue
		for dx in range(-row, row + 1):
			var x: int = cx + dx
			if x >= 0 and x < image.get_width():
				image.set_pixel(x, y, color)
#endregion
