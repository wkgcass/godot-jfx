import com.sun.javafx.tk.godot.GodotBridge;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** JNI transport probe, not a JavaFX control or Prism acceptance test. */
public final class BridgeProbe {
    private static void reject(Runnable action) {
        try { action.run(); }
        catch (IllegalArgumentException expected) { return; }
        throw new AssertionError("Native bridge accepted invalid input");
    }

    public static void main(String[] args) {
        run(false);
    }

    public static void run(boolean waitForHostStop) {
        reject(() -> GodotBridge.submit(ByteBuffer.allocate(24), 24));
        reject(() -> GodotBridge.submit(ByteBuffer.allocateDirect(24), 24));
        reject(() -> GodotBridge.awaitTick(0, 0));

        ByteBuffer frame = ByteBuffer.allocateDirect(264).order(ByteOrder.LITTLE_ENDIAN);
        frame.putInt(0x31465847).putInt(1).putInt(264).putInt(4).putLong(1);
        frame.putInt(3).putInt(8).putInt(400).putInt(240);
        frame.putInt(1).putInt(0);
        frame.putInt(2).putInt(32);
        for (float value : new float[] {16, 16, 160, 96, 0.8f, 0.2f, 0.6f, 1}) frame.putFloat(value);
        frame.putInt(4).putInt(168).putLong(0).putInt(4);
        for (int i = 0; i < 4; ++i) {
            frame.putFloat(200 + (i / 2) * 80).putFloat(16 + (i % 2) * 96).putFloat(0);
            frame.putFloat(i / 2).putFloat(i % 2).putFloat(0.25f).putFloat(0.75f);
            frame.putInt(0xff00ff00); // RGBA bytes: green, opaque.
        }
        for (float value : new float[] {1, 0, 0, 0, 1, 0, 1}) frame.putFloat(value); // Identity transform, opaque.
        if (!GodotBridge.submit(frame, 264)) throw new AssertionError("Empty host queue rejected frame");
        reject(() -> GodotBridge.submit(frame, 264)); // duplicate sequence
        // Native side must have copied the commands, not retained this memory.
        frame.clear();
        while (frame.hasRemaining()) frame.put((byte) 0);
        long tick = 0;
        for (int i = 0; i < 5; ++i) {
            long next = GodotBridge.awaitTick(tick, 1000);
            if (next <= tick) throw new AssertionError("Host stopped or failed to deliver a tick");
            tick = next;
        }
        System.out.println("BRIDGE_PROBE_PASS thread=" + Thread.currentThread().getName());
        if (waitForHostStop) {
            while ((tick = GodotBridge.awaitTick(tick, 1000)) >= 0) { }
            System.out.println("BRIDGE_STOP_PASS");
        }
    }
}
