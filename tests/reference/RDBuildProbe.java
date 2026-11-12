import com.sun.javafx.tk.godot.GodotBridge;

/** Checks the host build capability through the real registered JNI bridge. */
public final class RDBuildProbe {
    public static void main(String[] args) {
        String expected = System.getenv("GODOT_JFX_EXPECT_RD_COMPILED");
        if (!"0".equals(expected) && !"1".equals(expected)) {
            throw new AssertionError("Missing expected host build capability");
        }
        boolean compiled = GodotBridge.isRDDirectCompiled();
        if (compiled != "1".equals(expected)) {
            throw new AssertionError("Unexpected RD-direct build capability: " + compiled);
        }
        if (GodotBridge.hostInfo().length < 16) {
            throw new AssertionError("Missing host metadata");
        }
        System.out.println("RD_BUILD_JNI_PASS compiled=" + compiled);
    }
}
