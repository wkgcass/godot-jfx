extends Node

func fail(message: String) -> void:
    push_error(message)
    get_tree().quit(1)

func _ready() -> void:
    var host = ClassDB.instantiate("JavaFXHost")
    add_child(host)
    if not host.run_fixture_probe("StartupProbe"):
        fail("Java probe startup failed")
        return
    var started := Time.get_ticks_msec()
    var logo := OS.get_environment("GODOT_JFX_STARTUP") == "logo"
    var cancel := OS.get_environment("GODOT_JFX_STARTUP_CANCEL") == "1"
    var saw_started := false
    var cancelled := false
    var first_logo := 0
    var completed := false
    var sampled := false
    var sampled_fade := false
    while host.get_runtime_status() != "finished":
        await get_tree().process_frame
        var state: Dictionary = host.get_startup_status()
        if host.get_runtime_status() == "failed" or Time.get_ticks_msec() - started > 20000:
            fail("Startup timeout/failure: " + host.get_runtime_error())
            return
        saw_started = saw_started or state.active
        if cancel and saw_started and not host.visible and not state.active:
            cancelled = true
        if cancel and cancelled and host.visible and not completed:
            await RenderingServer.frame_post_draw
            await RenderingServer.frame_post_draw
            var img := get_viewport().get_texture().get_image()
            var corner := img.get_pixel(8, 8)
            if corner.r > 0.7 and corner.g < 0.3:
                completed = true
        if cancelled and state.active:
            fail("Cancelled startup resumed")
            return
        if state.active and state.shown and logo:
            if first_logo == 0: first_logo = Time.get_ticks_msec()
            if not sampled and Time.get_ticks_msec() - first_logo > 100:
                await RenderingServer.frame_post_draw
                var img := get_viewport().get_texture().get_image()
                var corner := img.get_pixel(8, 8)
                if absf(corner.r - 0.14) > 0.04 or absf(corner.g - 0.14) > 0.04:
                    fail("Logo backdrop missing: " + str(corner))
                    return
                img.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/startup-logo.png"))
                sampled = true
        if not cancel and logo and state.active and state.fade_begin_us > 0 and not sampled_fade:
            var fade_elapsed: int = Time.get_ticks_usec() - state.fade_begin_us
            if fade_elapsed >= 200000 and fade_elapsed <= 350000:
                var img := get_viewport().get_texture().get_image()
                var corner := img.get_pixel(8, 8)
                if corner.r <= 0.2 or corner.r >= 0.85:
                    fail("Expected blended application frame during fade: " + str(corner))
                    return
                img.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/startup-fade.png"))
                sampled_fade = true
        if not cancel and state.shown and not state.active and not completed:
            if not state.frame_ready:
                fail("Window revealed before first frame")
                return
            if logo and (not sampled or not sampled_fade or Time.get_ticks_msec() - first_logo < 1500 or Time.get_ticks_usec() - state.fade_begin_us < 500000):
                fail("Logo duration too short")
                return
            await RenderingServer.frame_post_draw
            await RenderingServer.frame_post_draw
            var img := get_viewport().get_texture().get_image()
            var corner := img.get_pixel(8, 8)
            if corner.r < 0.7 or corner.g > 0.3:
                fail("First JavaFX frame missing: " + str(corner))
                return
            completed = true
        if state.logo_count > (1 if logo else 0):
            fail("Logo repeated")
            return
    if not completed:
        fail("Startup did not complete")
        return
    print("STARTUP_PASS mode=", OS.get_environment("GODOT_JFX_STARTUP"), " cancel=", cancel)
    get_tree().quit()
