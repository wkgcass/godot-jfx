extends SceneTree

func _initialize() -> void:
    call_deferred("check_mode")

func check_mode() -> void:
    var host = ClassDB.instantiate("JavaFXHost")
    root.add_child(host)
    if host.run_fixture_probe(""):
        push_error("Separate rendering unexpectedly admitted a probe")
        quit(1)
        return
    root.remove_child(host)
    if host.get_owned_resource_count() != 0:
        push_error("Rejected host retained rendering resources")
        host.free()
        quit(1)
        return
    host.free()
    print("RENDER_MODE_REJECTION_PASS")
    quit()
