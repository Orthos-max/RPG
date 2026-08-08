class_name Palette
extends RefCounted
## La charte graphique de Ciel Emblem — « Velmar : nuit et or ».
##
## Une seule source pour toutes les couleurs de l'interface. Avant ce fichier,
## soixante codes hexadécimaux étaient écrits en dur dans douze scripts : chaque
## écran avait été teinté séparément, donc rien ne garantissait que deux écrans
## parlent la même langue. Changer d'ambiance demandait de les retrouver tous.
##
## Le registre est celui du royaume : la nuit domine, l'or ponctue, le pourpre
## ne sert qu'à ce qui blesse ou ce qui est irréversible. Les trois bleus de fond
## sont accordés au ciel du plateau ([TacticsScenery] : #3a4a72 → #24213a), pour
## que passer d'un menu à une bataille ne change pas de monde.
##
## Règle d'emploi : [b]l'or est un accent, pas une couleur de fond[/b]. Dès qu'il
## remplit une surface, il cesse de désigner ce qui compte.

#region Fonds
## Le fond le plus profond — derrière tout le reste
const INK := Color("#141026")
## Fond alterné : une ligne sur deux dans une liste, un champ au repos
const INK_SOFT := Color("#1b1733")
## Panneau posé sur le fond
const PANEL := Color("#16213e")
## Panneau survolé, ou ligne de liste sélectionnée
const PANEL_HI := Color("#1d2b4f")
## Champ de saisie : plus sombre que le panneau qui le porte, jamais plus clair.
## C'est ce qui dit « on écrit ici » sans avoir à l'écrire.
const FIELD := Color("#101a33")
#endregion

#region Reliefs (boutons)
## Bouton au repos
const RELIEF := Color("#0f3460")
## Bouton survolé
const RELIEF_HI := Color("#1a4a85")
## Bouton enfoncé — plus sombre, pas plus clair : un bouton s'enfonce
const RELIEF_LO := Color("#0a2444")
## Bouton hors service
const RELIEF_OFF := Color("#191a2c")
#endregion

#region Bordures
## Bordure ordinaire d'un bouton
const EDGE := Color("#2c4a7a")
## Bordure d'un panneau ou d'un champ — plus discrète
const EDGE_SOFT := Color("#243357")
## Bordure d'un élément hors service
const EDGE_OFF := Color("#2a2b3d")
#endregion

#region Accents
## L'or : ce qui compte, ce qu'on a choisi, ce qui a le focus
const GOLD := Color("#f5c842")
## Or éteint — bordure de survol, séparateurs, or qui ne crie pas
const GOLD_DIM := Color("#8a7028")
## Le pourpre : ce qui blesse, ce qui tue, ce qui ne se défait pas
const CRIMSON := Color("#e94560")
## Pourpre enfoncé
const CRIMSON_LO := Color("#b02a44")
## Le vert ne sert qu'à une chose : ce qui soigne ou ce qui réussit
const VERDANT := Color("#2d6a4f")
#endregion

#region Texte
## Texte courant
const TEXT := Color("#e8e6f0")
## Texte appuyé — un titre de section, une valeur qu'on lit avant les autres
const TEXT_BRIGHT := Color("#ffffff")
## Texte secondaire : une légende, une unité, un rappel
const TEXT_DIM := Color("#9a97ad")
## Texte hors service
const TEXT_OFF := Color("#5a5670")
#endregion

#region Polices
## Titres : capitales romaines gravées. Réservé aux en-têtes — illisible en
## corps de texte, et c'est très bien : ça empêche d'en abuser.
const FONT_TITLE := preload("res://assets/fonts/Cinzel.ttf")
## Corps et interface : des chiffres lisibles à 14 px comptent plus que le
## caractère dans un jeu couvert de statistiques.
const FONT_BODY := preload("res://assets/fonts/AlegreyaSans-Regular.ttf")
## Corps appuyé — boutons, en-têtes de colonne
const FONT_BODY_BOLD := preload("res://assets/fonts/AlegreyaSans-Bold.ttf")

## Échelle typographique. Cinq tailles, pas douze : au-delà, l'écart entre deux
## niveaux cesse de se voir et la hiérarchie ne dit plus rien.
const SIZE_TITLE: int = 40
const SIZE_HEADING: int = 24
const SIZE_BODY: int = 17
const SIZE_SMALL: int = 15
const SIZE_TINY: int = 13
#endregion

#region Géométrie
## Rayon des coins : assez pour adoucir, trop peu pour faire « application web »
const RADIUS: int = 3
## Rayon d'un panneau — un cran au-dessus des boutons qu'il contient
const RADIUS_PANEL: int = 5
## Épaisseur d'une bordure ordinaire
const BORDER: int = 1
## Épaisseur d'une bordure de focus — le focus doit se voir sans loupe
const BORDER_FOCUS: int = 2
#endregion


## Une couleur de la charte, éclaircie ou assombrie.
##
## Sert aux cas que la charte n'a pas prévus (une jauge, un état passager) sans
## rouvrir la porte aux codes hexadécimaux écrits en dur.
static func shade(base: Color, amount: float) -> Color:
	return base.lightened(amount) if amount > 0.0 else base.darkened(-amount)


## Une couleur de la charte, rendue transparente.
static func fade(base: Color, alpha: float) -> Color:
	var out := base
	out.a = alpha
	return out
