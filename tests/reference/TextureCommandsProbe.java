import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.tk.godot.GodotRenderCommands;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;

public final class TextureCommandsProbe {
    private static final long FIRST = (1L << 32) | 1, SECOND = (2L << 32) | 1;
    private static byte[] image(int r, int g, int b) {
        return image(2, r, g, b);
    }
    private static byte[] image(int size, int r, int g, int b) {
        byte[] pixels = new byte[size * size * 4];
        for (int i = 0; i < size * size; ++i) {
            pixels[i * 4] = (byte) r; pixels[i * 4 + 1] = (byte) g; pixels[i * 4 + 2] = (byte) b; pixels[i * 4 + 3] = (byte) 255;
        }
        return pixels;
    }
    private static void reject(ByteBuffer bytes) {
        try { GodotBridge.submit(bytes, bytes.position()); }
        catch (IllegalArgumentException expected) { return; }
        throw new AssertionError("Invalid texture transaction was accepted");
    }
    private static void draw(GodotRenderCommands commands, long texture, int x, int width) {
        float[] vertices = new float[28];
        byte[] colors = new byte[16]; Arrays.fill(colors, (byte) 255);
        for (int i = 0; i < 4; ++i) {
            vertices[i * 7] = x + (i / 2) * width;
            vertices[i * 7 + 1] = 16 + (i % 2) * 96;
            vertices[i * 7 + 3] = i / 2; vertices[i * 7 + 4] = i % 2;
        }
        commands.drawTexturedQuads(texture, vertices, colors, 4);
    }
    public static void main(String[] args) {
        ByteBuffer bad = ByteBuffer.allocateDirect(80).order(ByteOrder.LITTLE_ENDIAN);
        bad.putInt(0x31465847).putInt(1).putInt(80).putInt(2).putLong(1);
        bad.putInt(5).putInt(32).putLong(FIRST).putInt(2).putInt(2).put(image(204, 51, 153));
        bad.putInt(7).putInt(8).putLong((99L << 32) | 1);
        reject(bad); // Must not reserve FIRST or consume sequence 1.

        GodotRenderCommands commands = new GodotRenderCommands();
        commands.resize(400, 240); commands.clear();
        commands.allocateTexture(FIRST, 4, 4);
        commands.updateTextureRegion(FIRST, 0, 0, 4, 4, image(4, 204, 51, 153));
        draw(commands, FIRST, 16, 160);
        // Adjacent overlapping patches obey last-write-wins semantics,
        // while the preceding draw must retain the original magenta revision.
        commands.updateTextureRegion(FIRST, 0, 0, 2, 2, image(255, 255, 0));
        commands.updateTextureRegion(FIRST, 0, 0, 2, 2, image(0, 255, 0));
        draw(commands, FIRST, 200, 80);
        commands.disposeTexture(FIRST);
        commands.createTexture(SECOND, 2, 2, image(0, 0, 255));
        draw(commands, SECOND, 310, 60);
        commands.disposeTexture(SECOND);
        long atlas = (1L << 32) | 2;
        commands.allocateTexture(atlas, 1024, 1024);
        drawAtlas(commands, atlas, 16);
        commands.updateTextureRegion(atlas, 1023, 1023, 1, 1, image(1, 255, 0, 0));
        commands.updateTextureRegion(atlas, 1023, 1023, 1, 1, image(1, 0, 0, 255));
        drawAtlas(commands, atlas, 310);
        commands.disposeTexture(atlas);
        if (commands.submit() != 1) throw new AssertionError("Rejected transaction consumed a sequence");

        bad.clear(); bad.putInt(0x31465847).putInt(1).putInt(40).putInt(1).putLong(2);
        bad.putInt(7).putInt(8).putLong(FIRST);
        reject(bad); // Stale generation, even before the host consumes the frame.
        long tick = 0;
        for (int i = 0; i < 8; ++i) {
            tick = GodotBridge.awaitTick(tick, 1000);
            if (tick < 0) throw new AssertionError("Host stopped unexpectedly");
        }
        System.out.println("BRIDGE_PROBE_PASS: texture rollback, region update, zero initialization, large atlas, disposal and generation reuse");
    }

    private static void drawAtlas(GodotRenderCommands commands, long texture, int x) {
        float[] vertices = new float[28];
        byte[] colors = new byte[16]; Arrays.fill(colors, (byte) 255);
        for (int i = 0; i < 4; ++i) {
            vertices[i * 7] = x + (i / 2) * 60; vertices[i * 7 + 1] = 144 + (i % 2) * 64;
            vertices[i * 7 + 3] = vertices[i * 7 + 4] = 1023.5f / 1024;
        }
        commands.drawTexturedQuads(texture, vertices, colors, 4);
    }
}
