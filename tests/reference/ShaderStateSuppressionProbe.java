import com.sun.javafx.tk.godot.GodotRenderCommands;
import com.sun.prism.godot.GodotShader;
import java.util.Map;

public final class ShaderStateSuppressionProbe {
    private static GodotShader.Snapshot state(boolean integer, int... words) {
        return new GodotShader.Snapshot("shader", Map.of("image", 0),
                Map.of("value", new GodotShader.Constant(integer, words.length, false, words)));
    }

    private static int write(GodotRenderCommands commands, GodotShader.Snapshot state, long... handles) {
        int before = commands.remainingBatchBytes();
        commands.shaderState(state, handles);
        return before - commands.remainingBatchBytes();
    }

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        var commands = new GodotRenderCommands();
        boolean enabled = !"0".equals(System.getenv("GODOT_JFX_STATE_SUPPRESS"));
        int[] input = {0, 31};
        long texture = (1L << 32) | 1;
        long replacement = (2L << 32) | 1;
        long[] handles = {texture};
        var snapshot = state(true, input);
        int first = write(commands, snapshot, handles);
        input[0] = 5;
        handles[0] = replacement;
        int repeat = write(commands, state(true, 0, 31), texture);
        System.out.println("SHADER_STATE_BYTES first=" + first + " repeated=" + repeat);
        require(first > 0 && repeat == (enabled ? 0 : first), "Fresh equal constants must obey suppression");
        require(snapshot.equals(state(true, 0, 31)) && snapshot.hashCode() == state(true, 0, 31).hashCode(),
                "Constant snapshots do not have value semantics");
        require(write(commands, state(true, 1, 0), texture) == first, "Different words with identical array hash were skipped");
        require(write(commands, state(false, 1, 0), texture) == first, "Changed type was skipped");
        require(write(commands, state(false, 1, 0), replacement) == first, "Changed texture handle was skipped");
        commands.updateTexture(texture, 1, 1, new byte[4]);
        require(write(commands, state(false, 1, 0), replacement) == repeat, "Unrelated upload changed sampler state");
        for (Runnable update : new Runnable[]{
                () -> commands.updateTexture(replacement, 1, 1, new byte[4]),
                () -> commands.updateTextureRegion(replacement, 0, 0, 1, 1, new byte[4]),
                () -> commands.updateAlphaTextureRegion(replacement, 0, 0, 1, 1, java.nio.ByteBuffer.allocate(1), 0, 0, 1),
                () -> commands.updateFloatTextureRegion(replacement, 0, 0, 1, 1, new byte[16])}) {
            update.run();
            require(write(commands, state(false, 1, 0), replacement) == first, "Texture revision was skipped");
        }
        var scalar = new GodotShader.Constant(true, 4, false, new int[4]);
        var vectorArray = new GodotShader.Constant(true, 4, true, new int[4]);
        require(!scalar.equals(vectorArray), "Scalar and array payloads compared equal");
        commands.selectTarget(0);
        require(write(commands, state(false, 1, 0), replacement) == first, "Target change did not invalidate state");
        var secondEncoder = new GodotRenderCommands();
        require(write(secondEncoder, snapshot, texture) == first && write(commands, state(false, 1, 0), replacement) == first,
                "Multiple encoders must not suppress state");
        System.out.println("SHADER_STATE_SUPPRESSION_PASS enabled=" + enabled);
    }
}
