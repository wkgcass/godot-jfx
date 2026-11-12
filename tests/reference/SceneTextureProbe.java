import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.tk.godot.GodotRenderCommands;
import com.sun.prism.Texture;
import com.sun.prism.PixelFormat;
import com.sun.prism.godot.GodotSceneTexture;
import com.sun.prism.godot.GodotTexture;
import com.sun.prism.godot.GodotResourceFactory;
import java.nio.IntBuffer;
import java.util.Arrays;

public final class SceneTextureProbe {
    private static void draw(GodotRenderCommands commands,GodotTexture texture,int x,int width) {
        float[] vertices = new float[28]; byte[] colors = new byte[16]; Arrays.fill(colors,(byte)255);
        for (int i = 0; i < 4; ++i) {
            vertices[i*7] = x+(i/2)*width; vertices[i*7+1] = 16+(i%2)*128;
            vertices[i*7+3] = i/2; vertices[i*7+4] = i%2;
        }
        commands.drawTexturedQuads(texture.getNativeHandle(),vertices,colors,4,1,0,0,0,1,0,1);
    }
    private static long awaitTicks(long tick, int count, boolean allowStopped) {
        long deadline = System.nanoTime() + 10_000_000_000L;
        for (int observed = 0; observed < count;) {
            long remaining = deadline - System.nanoTime();
            if (remaining <= 0) throw new AssertionError("Scene texture host did not advance " + count + " ticks");
            int timeoutMillis = (int)Math.min(1000, Math.max(1, remaining / 1_000_000));
            long next = GodotBridge.awaitTick(tick, timeoutMillis);
            if (next < 0) {
                if (allowStopped) return next;
                throw new AssertionError("Scene texture host stopped");
            }
            if (next > tick) { tick = next; observed++; }
        }
        return tick;
    }
    public static void main(String[] args) {
        var factory = new GodotResourceFactory(null);
        var commands = factory.getContext().getCommands();
        commands.resize(400,240); commands.clear();
        boolean missing = "1".equals(System.getenv("GODOT_JFX_SCENE_MISSING"));
        boolean resize = "1".equals(System.getenv("GODOT_JFX_SCENE_RESIZE"));
        GodotSceneTexture first = factory.createSceneTexture(missing ? "res://missing-scene.tscn" : "res://embedded_scene.tscn",64,64);
        if (first == null) throw new AssertionError("Scene texture allocation failed");
        if (!missing) {
            Texture alias = first.getSharedTexture(Texture.WrapMode.CLAMP_TO_ZERO);
            if (!(alias instanceof GodotSceneTexture) || alias.getLockCount() != 2) throw new AssertionError("Scene alias lost its kind/lock");
            alias.unlock();
            boolean rejected = false;
            try { first.update(IntBuffer.allocate(1),PixelFormat.INT_ARGB_PRE,0,0,0,0,1,1,4,false); }
            catch (UnsupportedOperationException expected) { rejected = true; }
            if (!rejected) throw new AssertionError("Scene texture accepted CPU pixels");
            GodotSceneTexture second = factory.createSceneTexture("res://embedded_scene.tscn",96,64);
            if (second == null) throw new AssertionError("Second scene texture allocation failed");
            draw(commands,first,16,128); draw(commands,second,200,192);
            if (resize) {
                commands.submit();
                long tick = awaitTicks(0,60,false);
                first = factory.resizeSceneTexture(first,96,64);
                if (first == null || first.getPhysicalWidth() != 96 || !alias.isSurfaceLost()) throw new AssertionError("Scene resize metadata/old alias differs");
                if (factory.getTextureResourcePool().used() != 2L*96*64*4) throw new AssertionError("Scene resize retained old accounting");
                commands.clear();
                draw(commands,first,16,192); draw(commands,second,220,160);
                commands.endTargetPass();
                awaitTicks(tick,60,false);
            }
            first.dispose(); second.dispose();
            if (!alias.isSurfaceLost() || factory.getTextureResourcePool().used() != 0) throw new AssertionError("Scene texture disposal accounting differs");
        }
        commands.submit();
        if (awaitTicks(0,120,missing) < 0) return;
        if (missing) throw new AssertionError("Missing scene did not fail the host");
        System.out.println("SCENE_TEXTURE_PROBE_PASS");
    }
}
