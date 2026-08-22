extends SceneTree
## Démo visuelle du LevelUpFx : simule un level up puis une promotion,
## reste affiché quelques secondes pour capture d'écran.

func _init() -> void:
    await process_frame
    var fx := LevelUpFx.new()
    fx.name = "LevelUpFx"
    root.add_child(fx)

    var recorder := root.get_node_or_null("BattleRecorder")
    if recorder:
        # Niveau supérieur (comme le fait le combat après un kill)
        recorder.record(recorder.Kind.LEVEL_UP, {
            "pawn": "Lyra", "level": 5, "exp": 32,
        })
        await create_timer(3.0).timeout
        # Promotion, pour la variante dorée
        recorder.record(recorder.Kind.PROMOTION, {
            "pawn": "Lyra", "class_id": 3,
        })
        await create_timer(3.0).timeout
    quit()
