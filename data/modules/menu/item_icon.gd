class_name ItemIcon
extends RefCounted
## La vignette d'un objet ou d'une arme, prête à poser dans une ligne de menu.
##
## Les catalogues ([ItemDB], [WeaponDB]) ne connaissent qu'un chemin — ils sont
## de la logique pure et ne montent aucun nœud. C'est ici que le chemin devient
## un [TextureRect], au même format pour l'intendance, l'armurerie, les fiches
## et l'éditeur : trois écrans qui listent les mêmes objets doivent les montrer
## de la même taille.

## Côté de la vignette, en pixels. Les découpes du pack font 32×32 : les
## afficher à leur taille native évite d'avoir à choisir entre un filtrage qui
## bave et un « au plus proche voisin » qui mange des pixels.
const SIZE: int = 32


## Une vignette pour [param icon_path].
##
## Rend un nœud **même quand le chemin est vide ou introuvable** : sans lui la
## colonne des noms se décalerait d'une ligne à l'autre selon que l'objet a une
## image ou non.
static func rect(icon_path: String, size: int = SIZE) -> TextureRect:
	var view := TextureRect.new()
	view.custom_minimum_size = Vector2(size, size)
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		view.texture = load(icon_path) as Texture2D
	return view


## La vignette d'un objet consommable, par son nom de catalogue.
static func of_item(item_name: String, size: int = SIZE) -> TextureRect:
	return rect(ItemDB.icon_path(item_name), size)


## La vignette d'une arme, par son identifiant.
static func of_weapon(weapon_id: String, size: int = SIZE) -> TextureRect:
	return rect(WeaponDB.icon_path(weapon_id), size)
