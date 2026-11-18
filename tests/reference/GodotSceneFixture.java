import com.sun.glass.utils.NativeLibLoader;
import java.nio.file.Files;
import java.nio.file.Path;

public final class GodotSceneFixture {
    private static native int run(String library, String[] arguments);

    public static void main(String[] arguments) throws Exception {
        String library = NativeLibLoader.loadGodotEngine();
        if (!com.sun.javafx.tk.godot.GodotLibraries.usesPackagedLibraries()) {
            throw new IllegalStateException("Scene fixtures require classpath native resources: " + library);
        }
        // Verify the bytes actually loaded in this JVM against the classifier.
        try (var resource = GodotSceneFixture.class.getResourceAsStream("/godot.dll");
             var mapped = Files.newInputStream(Path.of(library))) {
            var sha = java.security.MessageDigest.getInstance("SHA-256");
            if (resource == null || !java.util.Arrays.equals(hash(sha, resource), hash(sha, mapped))) {
                throw new IllegalStateException("Godot DLL differs from the classpath resource: " + library);
            }
        }
        System.out.println("GODOT_FIXTURE_LIBRARY pid=" + ProcessHandle.current().pid() + " path=" + library);
        System.exit(run(library, arguments));
    }

    private static byte[] hash(java.security.MessageDigest digest, java.io.InputStream input) throws Exception {
        try (var stream = new java.security.DigestInputStream(input, digest)) {
            stream.transferTo(java.io.OutputStream.nullOutputStream());
        }
        return digest.digest();
    }
}
