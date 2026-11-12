extends Node2D
# Steal The Rule: one-scene, asset-free, 2D multiplayer prototype.
# The host is authoritative. Direct IP works on LAN; internet requires reachable UDP port 24567.

const PORT := 24567
const ARENA := Rect2(260, 118, 760, 505)
const SPEED := 215.0
const ROUND_TIME := 180.0
const MAX_PLAYERS := 4
const ENERGY_COUNT := 12
const RULE_NAMES := ["REVERSE", "SLIPPERY", "HOLES", "SWAP", "SLOW", "DOUBLE"]
const COLORS := [Color("38a9ff"), Color("ff5f72"), Color("4be18c"), Color("b48aff")]

var mode := "menu" # menu, lobby, play, end
var online_ip := "127.0.0.1"
var editing_ip := false
var ip_edit: LineEdit
var status := ""
var players: Dictionary = {}
var inputs: Dictionary = {}
var energy: Array = []
var rule_card: Dictionary = {}
var active_rule := -1
var rule_owner := 0
var rule_left := 0.0
var round_left := ROUND_TIME
var energy_clock := 0.0
var sync_clock := 0.0
var pickup_clock := 0.0
var steal_clock: Dictionary = {}
var held_direction := Vector2.ZERO
var stick_pointer := -1
var stick_pos := Vector2(133, 567)
var mouse_stick := false
var last_winner := ""
var random := RandomNumberGenerator.new()

func _ready() -> void:
    random.randomize()
    multiplayer.peer_connected.connect(_peer_joined)
    multiplayer.peer_disconnected.connect(_peer_left)
    multiplayer.connected_to_server.connect(_connected)
    multiplayer.connection_failed.connect(_connection_failed)
    multiplayer.server_disconnected.connect(_server_left)
    # Keep Android landscape and avoid desktop minimum-size constraints.
    if not OS.has_feature("mobile"):
        get_window().min_size = Vector2i(960, 540)
    ip_edit = LineEdit.new()
    ip_edit.position = Vector2(470, 537)
    ip_edit.size = Vector2(340, 42)
    ip_edit.placeholder_text = "Host IP (e.g. 192.168.1.2)"
    ip_edit.text = online_ip
    ip_edit.text_changed.connect(func(value: String): online_ip = value)
    add_child(ip_edit)
    queue_redraw()

func _process(delta: float) -> void:
    if mode == "play":
        if multiplayer.is_server() or multiplayer.multiplayer_peer == null:
            _simulate(delta)
        elif multiplayer.has_multiplayer_peer():
            sync_clock += delta
            if sync_clock >= 0.05:
                sync_clock = 0.0
                send_input.rpc_id(1, held_direction)
    ip_edit.visible = mode == "menu"
    queue_redraw()

func _simulate(delta: float) -> void:
    round_left = maxf(0.0, round_left - delta)
    if round_left <= 0.0:
        _finish_round()
        return
    if active_rule >= 0:
        rule_left -= delta
        if rule_left <= 0.0:
            active_rule = -1
            rule_owner = 0
    energy_clock += delta
    if energy_clock > 1.5:
        energy_clock = 0.0
        while energy.size() < ENERGY_COUNT:
            energy.append(_random_position())
    for id in players.keys():
        var p: Dictionary = players[id]
        var direction: Vector2 = inputs.get(id, Vector2.ZERO)
        if int(id) == multiplayer.get_unique_id():
            direction = held_direction
        if active_rule == 0 and int(id) != rule_owner:
            direction = -direction
        var velocity := SPEED
        if active_rule == 1:
            velocity *= 1.4
        if active_rule == 4 and int(id) != rule_owner:
            velocity *= 0.55
        var target: Vector2 = p["pos"] + direction.limit_length(1.0) * velocity * delta
        target.x = clampf(target.x, ARENA.position.x + 22, ARENA.end.x - 22)
        target.y = clampf(target.y, ARENA.position.y + 22, ARENA.end.y - 22)
        if active_rule == 2 and _is_hole(target):
            p["pos"] = _spawn_position(int(p["slot"]))
        else:
            p["pos"] = target
        players[id] = p
        for e in range(energy.size() - 1, -1, -1):
            if target.distance_to(energy[e]) < 30.0:
                p["score"] = int(p["score"]) + (2 if active_rule == 5 and int(id) == rule_owner else 1)
                players[id] = p
                energy.remove_at(e)
        if not rule_card.is_empty() and target.distance_to(rule_card["pos"]) < 38.0:
            p["held"] = int(rule_card["type"])
            players[id] = p
            rule_card.clear()
    pickup_clock += delta
    if pickup_clock >= 9.0 and rule_card.is_empty():
        pickup_clock = 0.0
        rule_card = {"pos": _random_position(), "type": random.randi_range(0, 5)}
    sync_clock += delta
    if sync_clock >= 0.08:
        sync_clock = 0.0
        if multiplayer.has_multiplayer_peer():
            receive_state.rpc(players, energy, rule_card, active_rule, rule_owner, rule_left, round_left, mode)

func _is_hole(pos: Vector2) -> bool:
    return Rect2(420, 235, 90, 90).has_point(pos) or Rect2(785, 430, 90, 90).has_point(pos)

func _random_position() -> Vector2:
    for attempt in range(100):
        var v := Vector2(random.randf_range(ARENA.position.x + 48, ARENA.end.x - 48), random.randf_range(ARENA.position.y + 48, ARENA.end.y - 48))
        if v.distance_to(ARENA.get_center()) > 95.0 and not _is_hole(v):
            return v
    return Vector2(450, 400)

func _spawn_position(slot: int) -> Vector2:
    var positions := [Vector2(330, 190), Vector2(950, 190), Vector2(330, 555), Vector2(950, 555)]
    return positions[slot % 4]

func _add_player(id: int) -> void:
    if players.has(id) or players.size() >= MAX_PLAYERS:
        return
    var slot := players.size()
    players[id] = {"slot": slot, "pos": _spawn_position(slot), "score": 0, "held": -1}
    inputs[id] = Vector2.ZERO

func _host() -> void:
    _disconnect_peer()
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_server(PORT, MAX_PLAYERS - 1)
    if err != OK:
        status = "Cannot host. UDP port 24567 may be in use."
        return
    multiplayer.multiplayer_peer = peer
    players.clear()
    inputs.clear()
    _add_player(1)
    mode = "lobby"
    status = "HOST: others join your local IP, UDP 24567"

func _join() -> void:
    _disconnect_peer()
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_client(online_ip.strip_edges(), PORT)
    if err != OK:
        status = "Connection failed: check IP address."
        return
    multiplayer.multiplayer_peer = peer
    mode = "lobby"
    status = "Connecting to " + online_ip + "..."

func _disconnect_peer() -> void:
    if multiplayer.has_multiplayer_peer():
        multiplayer.multiplayer_peer.close()
    multiplayer.multiplayer_peer = null

func _practice() -> void:
    _disconnect_peer()
    players.clear()
    inputs.clear()
    _add_player(1)
    _start_round()

func _peer_joined(id: int) -> void:
    if not multiplayer.is_server():
        return
    if mode != "lobby" or players.size() >= MAX_PLAYERS:
        multiplayer.multiplayer_peer.disconnect_peer(id)
        return
    _add_player(id)
    _broadcast_lobby()

func _peer_left(id: int) -> void:
    if multiplayer.is_server():
        players.erase(id)
        inputs.erase(id)
        _broadcast_lobby()

func _connected() -> void:
    status = "Connected. Waiting for host to start."

func _connection_failed() -> void:
    _disconnect_peer()
    mode = "menu"
    status = "Could not connect. Check IP / Wi-Fi / UDP 24567."

func _server_left() -> void:
    _disconnect_peer()
    mode = "menu"
    status = "Host disconnected."

func _broadcast_lobby() -> void:
    if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
        lobby_update.rpc(players)

@rpc("authority", "call_remote", "reliable")
func lobby_update(state: Dictionary) -> void:
    players = state
    mode = "lobby"

func _start_round() -> void:
    if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
        return
    mode = "play"
    round_left = ROUND_TIME
    active_rule = -1
    rule_owner = 0
    rule_left = 0.0
    energy.clear()
    rule_card.clear()
    energy_clock = 0.0
    pickup_clock = 0.0
    for id in players.keys():
        var p: Dictionary = players[id]
        p["score"] = 0
        p["held"] = -1
        p["pos"] = _spawn_position(int(p["slot"]))
        players[id] = p
    for i in range(ENERGY_COUNT):
        energy.append(_random_position())
    rule_card = {"pos": _random_position(), "type": random.randi_range(0, 5)}
    if multiplayer.has_multiplayer_peer():
        receive_state.rpc(players, energy, rule_card, active_rule, rule_owner, rule_left, round_left, mode)

func _finish_round() -> void:
    mode = "end"
    var winner := -1
    var best := -1
    for id in players.keys():
        if int(players[id]["score"]) > best:
            best = int(players[id]["score"])
            winner = int(players[id]["slot"]) + 1
    last_winner = "PLAYER %d WINS - %d POINTS" % [winner, best]
    if multiplayer.has_multiplayer_peer():
        end_round.rpc(last_winner)

@rpc("authority", "call_remote", "reliable")
func end_round(result: String) -> void:
    last_winner = result
    mode = "end"

@rpc("any_peer", "call_remote", "unreliable")
func send_input(direction: Vector2) -> void:
    if not multiplayer.is_server():
        return
    var sender := multiplayer.get_remote_sender_id()
    if players.has(sender):
        inputs[sender] = direction.limit_length(1.0)

@rpc("authority", "call_remote", "unreliable")
func receive_state(state: Dictionary, orbs: Array, card: Dictionary, law: int, owner: int, duration: float, remaining: float, phase: String) -> void:
    players = state
    energy = orbs
    rule_card = card
    active_rule = law
    rule_owner = owner
    rule_left = duration
    round_left = remaining
    mode = phase

func _activate_law(id: int) -> void:
    if not players.has(id) or mode != "play":
        return
    var p: Dictionary = players[id]
    var held: int = p["held"]
    if held < 0:
        return
    active_rule = held
    rule_owner = id
    rule_left = 7.0 if held != 5 else 8.0
    p["held"] = -1
    players[id] = p
    if held == 3:
        var other_ids: Array = players.keys().filter(func(other): return other != id)
        if other_ids.size() > 0:
            var other: int = int(other_ids[random.randi_range(0, other_ids.size() - 1)])
            var a: Dictionary = players[id]
            var b: Dictionary = players[other]
            var tmp: Vector2 = a["pos"]
            a["pos"] = b["pos"]
            b["pos"] = tmp
            players[id] = a
            players[other] = b
        active_rule = -1

func _steal(id: int) -> void:
    if active_rule < 0 or rule_owner == id or not players.has(id) or not players.has(rule_owner):
        return
    if (players[id]["pos"] as Vector2).distance_to(players[rule_owner]["pos"]) > 85.0:
        return
    # One successful steal per cooldown window; prevents instant ping-pong.
    var now := Time.get_ticks_msec()
    if now - int(steal_clock.get(id, 0)) < 1800:
        return
    steal_clock[id] = now
    var p: Dictionary = players[id]
    p["score"] = int(p["score"]) + 2
    p["held"] = active_rule
    players[id] = p
    active_rule = -1
    rule_owner = 0

@rpc("any_peer", "call_remote", "reliable")
func request_action(action: String) -> void:
    if not multiplayer.is_server():
        return
    var id := multiplayer.get_remote_sender_id()
    if action == "law":
        _activate_law(id)
    elif action == "steal":
        _steal(id)

func _action(action: String) -> void:
    if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
        request_action.rpc_id(1, action)
    elif action == "law":
        _activate_law(multiplayer.get_unique_id())
    elif action == "steal":
        _steal(multiplayer.get_unique_id())

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if editing_ip:
            if event.keycode == KEY_ENTER:
                editing_ip = false
            elif event.keycode == KEY_BACKSPACE:
                online_ip = online_ip.substr(0, maxi(0, online_ip.length() - 1))
            elif event.unicode >= 32 and event.unicode <= 126:
                online_ip += char(event.unicode)
            return
        if event.keycode == KEY_SPACE and mode == "play":
            _action("law")
        if event.keycode == KEY_E and mode == "play":
            _action("steal")
    if event is InputEventScreenTouch:
        if event.pressed:
            _touch_down(event.position, event.index)
        elif event.index == stick_pointer:
            stick_pointer = -1
            held_direction = Vector2.ZERO
    if event is InputEventScreenDrag and event.index == stick_pointer:
        held_direction = (event.position - stick_pos).limit_length(70.0) / 70.0
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not OS.has_feature("mobile"):
        if event.pressed:
            _touch_down(event.position, -2)
            mouse_stick = stick_pointer == -2
        else:
            mouse_stick = false
            if stick_pointer == -2:
                stick_pointer = -1
                held_direction = Vector2.ZERO
    if event is InputEventMouseMotion and mouse_stick and not OS.has_feature("mobile"):
        held_direction = (event.position - stick_pos).limit_length(70.0) / 70.0

func _touch_down(pos: Vector2, index: int) -> void:
    if mode == "menu":
        if Rect2(450, 250, 380, 72).has_point(pos):
            _practice()
        elif Rect2(450, 340, 380, 72).has_point(pos):
            _host()
        elif Rect2(450, 430, 380, 72).has_point(pos):
            _join()
        elif Rect2(450, 525, 380, 60).has_point(pos):
            ip_edit.grab_focus()
            status = "Enter the host IP using your Android keyboard."
    elif mode == "lobby":
        if Rect2(450, 450, 380, 72).has_point(pos) and multiplayer.is_server():
            if players.size() >= 2:
                _start_round()
            else:
                status = "Need at least 2 players. Use PRACTICE for solo."
        elif Rect2(30, 640, 170, 55).has_point(pos):
            _disconnect_peer()
            mode = "menu"
    elif mode == "play":
        if pos.distance_to(stick_pos) < 105:
            stick_pointer = index
            held_direction = (pos - stick_pos).limit_length(70.0) / 70.0
        elif pos.distance_to(Vector2(1150, 560)) < 80:
            _action("law")
        elif pos.distance_to(Vector2(1150, 395)) < 67:
            _action("steal")
    elif mode == "end" and Rect2(440, 460, 400, 80).has_point(pos):
        if multiplayer.has_multiplayer_peer():
            if multiplayer.is_server():
                _start_round()
        else:
            _practice()

func _physics_process(_delta: float) -> void:
    if mode != "play" or stick_pointer != -1:
        return
    held_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

func _draw() -> void:
    draw_rect(Rect2(0, 0, 1280, 720), Color("10172e"))
    if mode == "menu":
        _text("STEAL THE RULE", Vector2(640, 145), 56, Color("ffe17a"), HORIZONTAL_ALIGNMENT_CENTER, 750)
        _text("2D TOP-DOWN PARTY ARENA", Vector2(640, 198), 24, Color("b6c9e8"), HORIZONTAL_ALIGNMENT_CENTER, 700)
        _button(Rect2(450, 250, 380, 72), "SOLO PRACTICE", Color("287bc5"))
        _button(Rect2(450, 340, 380, 72), "HOST LAN / INTERNET", Color("2d9a72"))
        _button(Rect2(450, 430, 380, 72), "JOIN BY IP", Color("935bc5"))
        _button(Rect2(450, 525, 380, 60), "IP: " + online_ip, Color("394562"))
        _text(status, Vector2(640, 630), 18, Color("d2d8e8"), HORIZONTAL_ALIGNMENT_CENTER, 1100)
        return
    if mode == "lobby":
        _text("WAITING ROOM", Vector2(640, 145), 46, Color("ffe17a"), HORIZONTAL_ALIGNMENT_CENTER, 800)
        _text("PLAYERS: %d / 4" % players.size(), Vector2(640, 230), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 700)
        for id in players.keys():
            var p: Dictionary = players[id]
            var slot: int = p["slot"]
            draw_circle(Vector2(485 + slot * 100, 320), 29, COLORS[slot])
            _text("P%d" % (slot + 1), Vector2(485 + slot * 100, 327), 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 60)
        if multiplayer.is_server():
            _button(Rect2(450, 450, 380, 72), "START (2-4 PLAYERS)", Color("298e68"))
        _button(Rect2(30, 640, 170, 55), "BACK", Color("47516a"))
        _text(status, Vector2(640, 580), 18, Color("d0dbec"), HORIZONTAL_ALIGNMENT_CENTER, 1200)
        return
    _draw_arena()
    _draw_hud()
    if mode == "end":
        draw_rect(Rect2(280, 225, 720, 320), Color(0.07, 0.10, 0.20, 0.96))
        _text("ROUND FINISHED", Vector2(640, 320), 42, Color("ffe17a"), HORIZONTAL_ALIGNMENT_CENTER, 680)
        _text(last_winner, Vector2(640, 385), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 680)
        _button(Rect2(440, 460, 400, 80), "PLAY AGAIN (HOST)", Color("327db5"))

func _draw_arena() -> void:
    draw_rect(ARENA.grow(10), Color("12d5ef"))
    draw_rect(ARENA, Color("30395e"))
    for x in range(int(ARENA.position.x), int(ARENA.end.x), 48):
        draw_line(Vector2(x, ARENA.position.y), Vector2(x, ARENA.end.y), Color("465278"), 1)
    for y in range(int(ARENA.position.y), int(ARENA.end.y), 48):
        draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), Color("465278"), 1)
    if active_rule == 2:
        draw_rect(Rect2(420, 235, 90, 90), Color("e95c76"))
        draw_rect(Rect2(785, 430, 90, 90), Color("e95c76"))
    draw_circle(ARENA.get_center(), 63, Color("1396ad"))
    draw_circle(ARENA.get_center(), 47, Color("142c4c"))
    _text("RULE", ARENA.get_center() + Vector2(0, 8), 25, Color("f5cf69"), HORIZONTAL_ALIGNMENT_CENTER, 100)
    for orb in energy:
        draw_circle(orb, 13, Color("ffce4a"))
        draw_circle(orb, 6, Color("fff2b4"))
    if not rule_card.is_empty():
        draw_rect(Rect2(rule_card["pos"] - Vector2(20, 24), Vector2(40, 48)), Color("d07bff"))
        _text("?", rule_card["pos"] + Vector2(0, 8), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 40)
    for id in players.keys():
        var p: Dictionary = players[id]
        var slot: int = p["slot"]
        var position: Vector2 = p["pos"]
        draw_circle(position + Vector2(3, 6), 23, Color(0.05, 0.08, 0.18, 0.6))
        draw_circle(position, 21, COLORS[slot])
        draw_circle(position + Vector2(5, -5), 9, Color("e4f6ff"))
        _text("P%d" % (slot + 1), position + Vector2(0, -31), 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 55)

func _draw_hud() -> void:
    for id in players.keys():
        var p: Dictionary = players[id]
        var slot: int = p["slot"]
        var x := 22.0 + slot * 245.0
        draw_rect(Rect2(x, 15, 230, 75), COLORS[slot].darkened(0.65))
        _text("P%d   %d pts" % [slot + 1, int(p["score"])], Vector2(x + 115, 63), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 215)
    _text("%02d:%02d" % [int(ceil(round_left)) / 60, int(ceil(round_left)) % 60], Vector2(1135, 66), 40, Color("ffe17a"), HORIZONTAL_ALIGNMENT_CENTER, 250)
    draw_circle(stick_pos, 89, Color(0.24, 0.38, 0.63, 0.45))
    draw_arc(stick_pos, 86, 0, TAU, 64, Color("7aa5ed"), 3)
    draw_circle(stick_pos + held_direction * 46.0, 43, Color("4296ff"))
    draw_circle(Vector2(1150, 560), 73, Color("edb544"))
    draw_circle(Vector2(1150, 395), 62, Color("d85875"))
    _text("LAW", Vector2(1150, 572), 27, Color("1b2036"), HORIZONTAL_ALIGNMENT_CENTER, 135)
    _text("STEAL", Vector2(1150, 404), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 125)
    var my_id := multiplayer.get_unique_id()
    if players.has(my_id):
        var held: int = players[my_id]["held"]
        _text("HELD: " + (RULE_NAMES[held] if held >= 0 else "NONE"), Vector2(25, 675), 22, Color("ffe5a1"))
    _text("ACTIVE: " + (RULE_NAMES[active_rule] if active_rule >= 0 else "NONE"), Vector2(475, 675), 22, Color("b5edff"))

func _button(rect: Rect2, label: String, color: Color) -> void:
    draw_rect(rect, color)
    draw_rect(rect, color.lightened(0.35), false, 3)
    _text(label, rect.position + Vector2(rect.size.x / 2.0, rect.size.y / 2.0 + 9), 25, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x - 12))

func _text(value: String, pos: Vector2, size: int = 22, color: Color = Color.WHITE, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: int = -1) -> void:
    draw_string(ThemeDB.fallback_font, pos, value, alignment, width, size, color)
