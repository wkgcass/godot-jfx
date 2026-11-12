import com.sun.javafx.tk.godot.GodotHostStoppedException;
import com.sun.javafx.tk.godot.GodotRenderCommands;
import com.sun.prism.PixelFormat;
import com.sun.prism.Texture;
import com.sun.prism.godot.GodotTexture;
import com.sun.prism.godot.GodotTexturePool;
import java.util.concurrent.atomic.AtomicReference;

public final class TextureCancellationProbe {
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    public static void main(String[] args) {
        var failure = new AtomicReference<RuntimeException>();
        var pool = new GodotTexturePool(new GodotRenderCommands(), () -> {
            if (failure.get() != null) throw failure.get();
        });
        var texture = GodotTexture.create(pool, PixelFormat.INT_ARGB_PRE, Texture.WrapMode.CLAMP_TO_EDGE, 8, 8);
        var shared = texture.getSharedTexture(Texture.WrapMode.REPEAT);
        require(shared != null, "Shared texture unavailable");
        shared.unlock();
        long handle = texture.getNativeHandle();
        require(pool.used() == 256, "Shared texture charged twice");
        failure.set(new GodotHostStoppedException("Injected host cancellation during vertex flush"));
        texture.dispose();
        require(texture.isSurfaceLost() && shared.isSurfaceLost() && pool.used() == 0,
                "Cancelled disposal retained Java resource/accounting");
        shared.dispose(); texture.dispose();
        require(pool.used() == 0, "Repeated disposal changed accounting");
        failure.set(null);
        var next = GodotTexture.create(pool, PixelFormat.INT_ARGB_PRE, Texture.WrapMode.CLAMP_TO_EDGE, 8, 8);
        require(next.getNativeHandle() == handle + (1L << 32), "Cancelled disposal retained slot");
        var protocolFailure = new IllegalStateException("Injected genuine failure");
        failure.set(protocolFailure);
        try { next.dispose(); throw new AssertionError("Non-cancellation error swallowed"); }
        catch (IllegalStateException expected) { require(expected == protocolFailure, "Error changed"); }
        require(!next.isSurfaceLost() && pool.used() == 256, "Failed disposal falsely released resource");
        failure.set(null); next.dispose();
        require(pool.used() == 0, "Retry did not release resource");
        System.out.println("TEXTURE_CANCELLATION_PASS");
    }
}
