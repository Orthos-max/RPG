class_name TacticsUIService
extends RefCounted
## Service class for managing UI-related functionalities in the Tactics game.

## Reference to the TacticsControlsResource.
var controls: TacticsControlsResource


## Initializes the TacticsUIService with the necessary controls resource.
func _init(_controls: TacticsControlsResource) -> void:
	controls = _controls


## Updates the controller hints based on the current input device.
func update_controller_hints(ctrl: TacticsControls) -> void:
	if controls.is_joystick:
		ctrl.get_node("%ControllerHints").texture = ctrl.layout_xbox # Set Xbox layout if using joystick
	else:
		ctrl.get_node("%ControllerHints").texture = ctrl.layout_pc # Set PC layout otherwise


## Sets the visibility of the actions menu and updates action button states.
func set_actions_menu_visibility(v: bool, p_raw: Variant, ctrl: TacticsControls) -> void:
	var p: TacticsPawn = p_raw as TacticsPawn if is_instance_valid(p_raw) else null
	if not ctrl.get_node("HBox/Actions").visible:
		ctrl.get_node("HBox/Actions/Move").grab_focus() # Focus on Move action if menu wasn't visible
	
	ctrl.get_node("HBox/Actions").visible = v and p and is_instance_valid(p) and p.can_act() # Show menu if pawn can act
	
	if not p or not is_instance_valid(p):
		return # Exit if no pawn is provided or pawn was freed
	
	# Update action button states based on pawn's capabilities
	ctrl.get_node("HBox/Actions/Move").disabled = not p.res.can_move
	
	# For staff users: show "Heal" instead of "Attack"
	const WT = preload("res://data/models/world/stats/weapon_type.gd")
	var attack_btn: Button = ctrl.get_node("HBox/Actions/Attack")
	if WT.is_magical(p.stats.weapon_type) and not WT.is_physical(p.stats.weapon_type):
		attack_btn.text = "Heal"
		# Can heal if there's a wounded ally within range
		attack_btn.disabled = not _has_wounded_ally_nearby(p)
	else:
		attack_btn.text = "Attack"
		attack_btn.disabled = not p.res.can_attack


## Check if there's a wounded ally within heal range of this pawn
func _has_wounded_ally_nearby(p: TacticsPawn) -> bool:
	var parent_node: Node3D = p.get_parent() as Node3D
	if not parent_node:
		return false
	var p_pos: Vector3 = p.global_position
	var heal_dist: float = float(p.stats.attack_range) + 1.0
	for ally: TacticsPawn in parent_node.get_children():
		if ally == p or not ally.is_alive():
			continue
		if not ally.stats:
			continue
		if ally.stats.hp < ally.stats.max_hp:
			var dist: float = p_pos.distance_to(ally.global_position)
			if dist <= heal_dist:
				return true
	return false
