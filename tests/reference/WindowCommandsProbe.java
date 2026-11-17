import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.tk.godot.GodotRenderCommands;
import com.sun.prism.godot.GodotShader;
import java.util.Map;

/** Exercises retained window publication without enabling Glass popup creation. */
public final class WindowCommandsProbe {
    private static long tick;
    private static void settle() {
        // Advance only after Godot has checked this state's GPU pixels.
        long deadline = System.nanoTime() + 10_000_000_000L;
        for (;;) {
            double[] events = GodotBridge.pollInput();
            for (int i = 0; i < events.length; i += 9) if (events[i] == 2) return;
            tick = GodotBridge.awaitTick(tick, 100);
            if (tick < 0) throw new AssertionError("Window host stopped");
            if (System.nanoTime() > deadline) throw new AssertionError("Window pixel verification timed out");
        }
    }
    private static void publish(GodotRenderCommands c, long target, long window,
                                int x, int z, int red, int green, int blue, float opacity) {
        c.beginPresent(); c.selectTarget(target); c.clear();
        var shader = new GodotShader("shader_type canvas_item; render_mode unshaded, blend_premul_alpha;", Map.of(), Map.of(), selected -> {});
        c.shaderState(shader.snapshot()); shader.dispose();
        float[] vertices = new float[28]; byte[] colors = new byte[16];
        for (int i = 0; i < 4; ++i) {
            vertices[i * 7] = (i / 2) * 32;
            vertices[i * 7 + 1] = (i % 2) * 32;
            colors[i * 4] = (byte) red; colors[i * 4 + 1] = (byte) green;
            colors[i * 4 + 2] = (byte) blue; colors[i * 4 + 3] = (byte) 255;
        }
        c.drawQuads(vertices, colors, 4, 1, 0, 0, 0, 1, 0);
        c.presentWindow(window, x, 10, 100, 80, z, opacity);
    }
    public static void main(String[] args) {
        var c = new GodotRenderCommands();
        long first = 0x100000001L, second = 0x100000002L;
        c.resize(160, 120);
        c.allocateRenderTarget(first, 32, 32); c.allocateRenderTarget(second, 32, 32);
        publish(c, first, 101, 10, 0, 255, 0, 0, 1);
        publish(c, second, 205, 60, 1, 0, 0, 255, .5f);
        settle();
        publish(c, first, 101, 10, 0, 0, 255, 0, 1);
        settle();
        c.configureWindow(205, 60, 10, 100, 80, 1, .5f, false); settle();
        c.configureWindow(205, 60, 10, 100, 80, 1, .5f, true); settle();
        c.configureWindow(205, 110, 10, 50, 80, 1, .5f, true); settle();
        c.configureWindow(205, 60, 10, 100, 80, -1, .5f, true); settle();
        c.configureWindow(205, 60, 10, 100, 80, 1, 1, true); settle();
        c.removeWindow(205); c.disposeTexture(second); c.submit();
        settle();
        c.removeWindow(101); c.disposeTexture(first); c.submit();
        settle();
        System.out.println("WINDOW_COMMANDS_PROBE_PASS");
    }
}
