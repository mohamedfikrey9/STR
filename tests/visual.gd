extends SceneTree

func _initialize() -> void:
    call_deferred("_capture")

func _capture() -> void:
    root.size = Vector2i(1280, 720)
    var packed: PackedScene = load("res://main.tscn")
    if packed == null:
        push_error("Visual test: main scene failed to load")
        quit(1)
        return
    var game: Node2D = packed.instantiate()
    root.add_child(game)
    for i in range(5):
        await process_frame
    DirAccess.make_dir_recursive_absolute("build/screenshots")
    var menu_image := root.get_texture().get_image()
    if menu_image.is_empty() or menu_image.get_width() < 1000:
        push_error("Visual test: menu screenshot empty or incorrect size")
        quit(1)
        return
    menu_image.save_png("build/screenshots/menu.png")
    game._practice()
    for i in range(5):
        await process_frame
    var play_image := root.get_texture().get_image()
    if play_image.is_empty() or play_image.get_width() < 1000:
        push_error("Visual test: arena screenshot empty or incorrect size")
        quit(1)
        return
    play_image.save_png("build/screenshots/arena.png")
    print("VISUAL PASS: captured menu and arena at ", play_image.get_size())
    quit(0)
