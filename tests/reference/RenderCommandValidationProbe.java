import com.sun.javafx.tk.godot.GodotRenderCommands;
import java.nio.ByteBuffer;
import java.util.Arrays;

/** Encoder admission checks; no toolkit, JNI, clipboard or input devices. */
public final class RenderCommandValidationProbe {
    static void reject(Runnable action) {
        try { action.run(); }
        catch (IllegalArgumentException expected) { return; }
        throw new AssertionError("Invalid geometry accepted");
    }
    public static void main(String[] args) throws Exception {
        var commands = new GodotRenderCommands();
        float[] vertices = new float[28];
        byte[] colors = new byte[16]; Arrays.fill(colors, (byte)255);
        var field = GodotRenderCommands.class.getDeclaredField("buffer");
        field.setAccessible(true);
        ByteBuffer buffer = (ByteBuffer)field.get(commands);
        int initial = buffer.position();
        vertices[0] = Float.NaN;
        for (int attempt = 0; attempt < 2; ++attempt)
            reject(() -> commands.drawQuads(vertices, colors, 4, 1, 0, 0, 0, 1, 0));
        vertices[0] = 0; vertices[2] = 1;
        for (int attempt = 0; attempt < 2; ++attempt)
            reject(() -> commands.drawQuads(vertices, colors, 4, 1, 0, 0, 0, 1, 0));
        vertices[2] = 0;
        reject(() -> commands.drawQuads(vertices, colors, 4, Double.MAX_VALUE, 0, 0, 0, 1, 0));
        if (buffer.position() != initial) throw new AssertionError("Rejected write modified the frame");
        commands.drawQuads(vertices, colors, 4, 1, 0, 0, 0, 1, 0);
        if (buffer.getInt(initial) != 4) throw new AssertionError("First valid batch was not registered");
        long registered = buffer.getLong(initial + 8);
        int second = buffer.position();
        commands.drawQuads(vertices, colors, 4, 1, 0, 7, 0, 1, 9);
        if (registered == 0 || buffer.getInt(second) != 29 || buffer.getLong(second + 8) != registered)
            throw new AssertionError("Valid repeated geometry did not reference its registration");
        checkOwnedSnapshots();
        checkCollision();
        checkCapacityAndRetirement();
        checkByteBudget();
        checkThreadOwnership();
        checkFailedSubmission();
        checkBatchBoundary();
        System.out.println("RENDER_COMMAND_VALIDATION_PASS");
    }

    static Object field(GodotRenderCommands commands, String name) throws Exception {
        var field = GodotRenderCommands.class.getDeclaredField(name);
        field.setAccessible(true);
        return field.get(commands);
    }
    static ByteBuffer buffer(GodotRenderCommands commands) throws Exception {
        return (ByteBuffer)field(commands, "buffer");
    }
    static int draw(GodotRenderCommands commands, float[] vertices, byte[] colors) throws Exception {
        int start = buffer(commands).position();
        commands.drawQuads(vertices, colors, 4, 1, 0, 0, 0, 1, 0);
        return start;
    }
    static void checkOwnedSnapshots() throws Exception {
        var commands = new GodotRenderCommands();
        float[] vertices = new float[28];
        byte[] colors = new byte[16];
        int first = draw(commands, vertices, colors);
        long handle = buffer(commands).getLong(first + 8);
        vertices[0] = 7; colors[0] = 42;
        int changed = draw(commands, vertices, colors);
        if (buffer(commands).getInt(changed) != 4) throw new AssertionError("Mutable caller arrays aliased cache");
        vertices[0] = 0; colors[0] = 0;
        int restored = draw(commands, vertices, colors);
        if (buffer(commands).getInt(restored) != 29 || buffer(commands).getLong(restored + 8) != handle)
            throw new AssertionError("Owned geometry snapshot changed with caller arrays");
    }
    @SuppressWarnings("unchecked")
    static void checkCollision() throws Exception {
        var commands = new GodotRenderCommands();
        float[] vertices = new float[28];
        byte[] colors = new byte[16];
        draw(commands, vertices, colors);
        var cache = (java.util.Map<Long,Object>)field(commands, "geometryCache");
        Object original = cache.values().iterator().next();
        vertices[0] = 3;
        var hash = GodotRenderCommands.class.getDeclaredMethod("geometryHash", float[].class, byte[].class, int.class);
        hash.setAccessible(true);
        // Deterministically place different content in the candidate hash slot.
        // No production hash override or probabilistic collision search needed.
        cache.clear(); cache.put((Long)hash.invoke(null, vertices, colors, 4), original);
        int changed = draw(commands, vertices, colors);
        if (buffer(commands).getInt(changed) != 4 || buffer(commands).getLong(changed + 8) != 0)
            throw new AssertionError("Hash collision referenced or replaced foreign geometry");
        if (cache.size() != 1 || cache.values().iterator().next() != original)
            throw new AssertionError("Collision lost ownership of existing registration");
    }
    static void checkCapacityAndRetirement() throws Exception {
        var commands = new GodotRenderCommands();
        int limit = (Integer)field(commands, "GEOMETRY_CACHE_MAX");
        if (limit < 2 || limit > 4096) throw new AssertionError("Use a small positive cache limit for this fixture");
        float[] vertices = new float[28]; byte[] colors = new byte[16];
        for (int i = 0; i < limit + 3; ++i) {
            vertices[0] = i;
            int start = draw(commands, vertices, colors);
            long handle = buffer(commands).getLong(start + 8);
            if (buffer(commands).getInt(start) != 4 || (handle != 0) != (i < limit))
                throw new AssertionError("Cache admission did not respect capacity");
        }
        var cache = (java.util.Map<?,?>)field(commands, "geometryCache");
        if (cache.size() != limit || (Long)field(commands, "geometryCacheBytes") != limit * 128L)
            throw new AssertionError("Geometry cache grew beyond its budget");
        var clock = GodotRenderCommands.class.getDeclaredField("submissionClock");
        clock.setAccessible(true); clock.setLong(commands, 65);
        vertices[0] = -1;
        int start = draw(commands, vertices, colors);
        if (buffer(commands).getInt(start) != 30 || buffer(commands).getInt(start + 16) != 4
                || buffer(commands).getLong(start + 24) == 0 || cache.size() != limit
                || (Long)field(commands, "geometryCacheBytes") != limit * 128L)
            throw new AssertionError("Idle retirement did not free budget and register new geometry");
    }

    static void checkByteBudget() throws Exception {
        var commands = new GodotRenderCommands();
        int vertices = 32768; // one MiB of coordinates and colors per entry
        float[] coordinates = new float[vertices * 7];
        byte[] colors = new byte[vertices * 4];
        var count = GodotRenderCommands.class.getDeclaredField("count"); count.setAccessible(true);
        for (int i = 0; i < 33; ++i) {
            coordinates[0] = i;
            commands.drawQuads(coordinates, colors, vertices, 1, 0, 0, 0, 1, 0);
            ByteBuffer encoded = buffer(commands);
            if (encoded.getInt(24) != 4 || (encoded.getLong(32) != 0) != (i < 32))
                throw new AssertionError("Geometry byte budget not enforced");
            // Inspect and discard transport bytes without calling JNI. Keep all
            // registrations recent to isolate admission from idle retirement.
            encoded.clear().position(24); count.setInt(commands, 0);
        }
        if (((java.util.Map<?,?>)field(commands, "geometryCache")).size() != 32
                || (Long)field(commands, "geometryCacheBytes") != 32L * 1024 * 1024)
            throw new AssertionError("Geometry payload budget exceeded");
    }

    static void checkThreadOwnership() throws Exception {
        var commands = new GodotRenderCommands();
        var result = new java.util.concurrent.atomic.AtomicReference<Throwable>();
        Thread foreign = new Thread(() -> {
            try { commands.clear(); }
            catch (Throwable error) { result.set(error); }
        }, "encoder-foreign-thread");
        foreign.start();
        foreign.join(5000);
        if (foreign.isAlive()) throw new AssertionError("Foreign encoder call did not terminate");
        if (!(result.get() instanceof IllegalStateException)
                || buffer(commands).position() != 24 || (Integer)field(commands, "count") != 0)
            throw new AssertionError("Foreign thread modified the batch or escaped ownership checks", result.get());
        commands.clear(); // Rejected foreign use must not poison the actual owner.
        if (buffer(commands).getInt(24) != 1) throw new AssertionError("Owner cannot continue after foreign rejection");
    }

    static void checkFailedSubmission() throws Exception {
        var commands = new GodotRenderCommands();
        commands.clear();
        // This standalone JVM has no registered Godot JNI methods. Exercise
        // the real submit Error path without installing a replacement bridge.
        try {
            commands.submit();
            throw new AssertionError("Unregistered native submit unexpectedly succeeded");
        } catch (UnsatisfiedLinkError expected) { }
        int position = buffer(commands).position();
        try {
            commands.clear();
            throw new AssertionError("Encoder accepted writes after failed submission");
        } catch (IllegalStateException expected) { }
        try {
            commands.submit();
            throw new AssertionError("Encoder retried a failed submission");
        } catch (IllegalStateException expected) { }
        if (!(Boolean)field(commands, "failed") || buffer(commands).position() != position
                || (Long)field(commands, "lastSubmittedSequence") != 0L)
            throw new AssertionError("Failed submission changed completion or pending state");
        System.out.println("ENCODER_OWNERSHIP_FAILURE_PASS");
    }

    static void checkBatchBoundary() throws Exception {
        for (boolean cached : new boolean[] {false, true}) {
            var exact = new GodotRenderCommands();
            float[] exactVertices = new float[28]; byte[] exactColors = new byte[16];
            if (cached) draw(exact, exactVertices, exactColors);
            var exactStorage = GodotRenderCommands.class.getDeclaredField("buffer"); exactStorage.setAccessible(true);
            ByteBuffer exactBuffer = ByteBuffer.allocateDirect(4 * 1024 * 1024).order(java.nio.ByteOrder.LITTLE_ENDIAN);
            exactBuffer.position(exactBuffer.capacity() - (cached ? 52 : 176));
            exactStorage.set(exact, exactBuffer);
            draw(exact, exactVertices, exactColors);
            if (exactBuffer.position() != exactBuffer.capacity()) throw new AssertionError("Exact-fit draw length differs");
            for (boolean countLimit : new boolean[] {false, true}) {
                var commands = new GodotRenderCommands();
                float[] vertices = new float[28]; byte[] colors = new byte[16];
                if (cached) draw(commands, vertices, colors);
                var storage = GodotRenderCommands.class.getDeclaredField("buffer"); storage.setAccessible(true);
                var count = GodotRenderCommands.class.getDeclaredField("count"); count.setAccessible(true);
                // Seed a nonempty almost-full transport without sending dummy
                // records to any host. The next draw must attempt submission.
                ByteBuffer full = ByteBuffer.allocateDirect(4 * 1024 * 1024).order(java.nio.ByteOrder.LITTLE_ENDIAN);
                full.position(countLimit ? 24 : full.capacity() - (cached ? 48 : 164));
                storage.set(commands, full);
                count.setInt(commands, countLimit ? 65536 : 1);
                try {
                    draw(commands, vertices, colors);
                    throw new AssertionError("Full batch did not attempt submission");
                } catch (UnsatisfiedLinkError expected) {
                    // Standalone JVM: reaching JNI proves it flushed rather
                    // than throwing a batch-limit error or writing past it.
                }
            }
        }
        System.out.println("ENCODER_BATCH_BOUNDARY_PASS");
    }
}
