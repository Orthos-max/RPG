class_name ArmySplit
extends RefCounted
## Partage d'une armée entre deux camps (M5 — trois camps dans une même bataille).
##
## Les cartes ne contiennent que deux armées. Pour faire tenir un troisième camp
## sans toucher à une seule scène, on scinde l'armée adverse en deux : une moitié
## reste à son camp d'origine, l'autre passe au nouveau camp.
##
## **Le partage doit être déterministe** : en réseau, l'hôte et l'invité le
## calculent chacun de leur côté et doivent tomber sur la même répartition, sans
## échanger le moindre message. On prend donc un pion sur deux — jamais de hasard.

## Part de l'armée confiée au nouveau camp, par défaut.
const DEFAULT_SHARE: float = 0.5


## Indices des pions à confier au nouveau camp.
##
## @param count: nombre de pions de l'armée à scinder
## @param share: part à céder (0.0 → aucun, 1.0 → tous sauf un)
## @return: indices croissants, jamais vides si `count >= 2`
static func guest_indices(count: int, share: float = DEFAULT_SHARE) -> Array[int]:
	var picked: Array[int] = []
	if count <= 1:
		# Une armée d'un seul pion ne se scinde pas : le camp d'origine
		# se retrouverait sans unité et perdrait la bataille sur-le-champ.
		return picked

	var wanted: int = clampi(int(round(float(count) * clampf(share, 0.0, 1.0))), 0, count - 1)
	if wanted <= 0:
		return picked

	# Un pion sur deux, en partant du second : la répartition reste alternée
	# (donc géographiquement mêlée) et strictement reproductible.
	var i: int = 1
	while i < count and picked.size() < wanted:
		picked.append(i)
		i += 2
	# Si la part demandée dépasse la moitié, on complète avec les indices pairs.
	i = 2
	while i < count and picked.size() < wanted:
		if not picked.has(i):
			picked.append(i)
		i += 2
	picked.sort()
	return picked
