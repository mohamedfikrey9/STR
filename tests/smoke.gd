extends SceneTree

func _initialize() -> void:
    call_deferred("_run_tests")

func _run_tests() -> void:
    var scene: PackedScene = load("res://main.tscn")
    if scene == null:
        _fail("Main scene cannot load")
        return
    var game: Node2D = scene.instantiate()
    root.add_child(game)
    await process_frame
    game._practice()
    if game.mode != "play" or game.players.size() != 1:
        _fail("Solo practice did not start")
        return
    var id: int = game.multiplayer.get_unique_id()
    if not game.players.has(id):
        _fail("Local player missing")
        return
    var before: Vector2 = game.players[id]["pos"]
    game.held_direction = Vector2.RIGHT
    game._simulate(0.25)
    var after: Vector2 = game.players[id]["pos"]
    if after.x <= before.x + 10.0:
        _fail("Player did not move right")
        return
    game.held_direction = Vector2.ZERO
    game._touch_down(game.stick_pos + Vector2(50, 0), 0)
    if game.stick_pointer != 0 or game.held_direction.x < 0.5:
        _fail("Touch joystick did not respond")
        return
    var drag := InputEventScreenDrag.new()
    drag.index = 0
    drag.position = game.stick_pos + Vector2(0, -65)
    game._input(drag)
    if game.held_direction.y > -0.5:
        _fail("Joystick drag did not update")
        return
    var release := InputEventScreenTouch.new()
    release.index = 0
    release.pressed = false
    release.position = game.stick_pos
    game._input(release)
    if game.held_direction.length() > 0.01:
        _fail("Joystick release did not stop movement")
        return
    print("PASS: scene loads, solo starts, player moves, joystick touch/drag/release work")
    quit(0)

func _fail(message: String) -> void:
    push_error("SMOKE TEST FAILED: " + message)
    quit(1)
