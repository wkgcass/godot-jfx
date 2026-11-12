import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.tk.godot.GodotRenderCommands;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;

/** Exercises the production render encoder against the actual native queue. */
public final class RenderCommandsProbe {
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    public static void main(String[] args) throws Exception {
        GodotRenderCommands commands = new GodotRenderCommands();
        require(commands.submit() == 0, "Empty batch emitted a sequence");
        AtomicBoolean rejected = new AtomicBoolean();
        Thread wrongThread = new Thread(() -> {
            try { commands.clear(); }
            catch (IllegalStateException expected) { rejected.set(true); }
        });
        wrongThread.start(); wrongThread.join(3000);
        require(rejected.get(), "Encoder accepted cross-thread mutation");

        // Larger than the initial direct buffer; uses Prism's native quad order.
        float[] vertices = new float[1024 * 7];
        byte[] colors = new byte[1024 * 4];
        for (int i = 0; i < 1024; ++i) {
            boolean green = (i / 4) % 2 != 0;
            vertices[i * 7] = (green ? 200 : 16) + ((i % 4) / 2) * (green ? 80 : 160);
            vertices[i * 7 + 1] = 16 + (i % 2) * 96;
            vertices[i * 7 + 3] = (i % 4) / 2;
            vertices[i * 7 + 4] = i % 2;
            vertices[i * 7 + 5] = 0.25f; vertices[i * 7 + 6] = 0.75f;
            colors[i * 4] = (byte) (green ? 0 : 204);
            colors[i * 4 + 1] = (byte) (green ? 255 : 51);
            colors[i * 4 + 2] = (byte) (green ? 0 : 153);
            colors[i * 4 + 3] = (byte) 255;
        }
        for (int frame = 1; frame <= 32; ++frame) {
            commands.resize(400, 240);
            commands.clear();
            commands.drawQuads(vertices, colors, 1024);
            float old = vertices[0]; vertices[0] = Float.NaN;
            boolean badRejected = false;
            try { commands.drawQuads(vertices, colors, 1024); }
            catch (IllegalArgumentException expected) { badRejected = true; }
            vertices[0] = old;
            require(badRejected, "Invalid attributes were accepted");
            require(commands.submit() == frame, "Submission sequence differs");
        }
        // Overwrite both caller arrays and reusable encoder storage without
        // submitting; the accepted native frame must keep its original data.
        Arrays.fill(colors, (byte) 0);
        commands.clear(); commands.drawQuads(vertices, colors, 1024);
        long tick = 0;
        for (int i = 0; i < 5; ++i) {
            tick = GodotBridge.awaitTick(tick, 1000);
            require(tick > 0, "Host stopped unexpectedly");
        }
        System.out.println("BRIDGE_PROBE_PASS: production encoder, growth, reuse, ordered batches, invalid-command atomicity");
        if ("1".equals(System.getenv("GODOT_JFX_TEST_STOP"))) {
            while ((tick = GodotBridge.awaitTick(tick, 1000)) >= 0) { }
            boolean stopped = false;
            try { commands.submit(); }
            catch (IllegalStateException expected) { stopped = true; }
            require(stopped, "Submission after shutdown was accepted");
            System.out.println("BRIDGE_STOP_PASS: encoder rejects stopped host");
        }
    }
}
