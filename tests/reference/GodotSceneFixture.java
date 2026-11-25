package com.sun.javafx.tk.godot;

import javafx.application.Platform;
import java.lang.reflect.InvocationTargetException;
import com.sun.glass.utils.NativeLibLoader;
import java.nio.file.Files;
import java.nio.file.Path;

public final class GodotSceneFixture {
    private static native int run(String library, String driver, String[] arguments);

    private static native void runOnAppKitThread(Runnable loop);

    public static void main(String[] arguments) throws Exception {
        String library = NativeLibLoader.loadGodotEngine();
        // Verify the bytes actually loaded in this JVM against the classifier.
        try (var resource = GodotSceneFixture.class.getResourceAsStream("/" + System.mapLibraryName("godot"));
             var mapped = Files.newInputStream(Path.of(library))) {
            var sha = java.security.MessageDigest.getInstance("SHA-256");
            if (resource == null || !java.util.Arrays.equals(hash(sha, resource), hash(sha, mapped))) {
                throw new IllegalStateException("Godot DLL differs from the classpath resource: " + library);
            }
        }
        System.out.println("GODOT_FIXTURE_LIBRARY pid=" + ProcessHandle.current().pid() + " path=" + library);
        var options = new java.util.ArrayList<>(java.util.List.of(arguments));
        String startup = System.getenv("GODOT_JFX_STARTUP");
        if (startup != null && !startup.isBlank()) {
            if (!options.contains("--")) options.add("--");
            options.add("--javafx-startup=" + startup);
        }
        String driver = GodotBootstrap.resolveDriver(null);
        String[] engineArguments = options.toArray(String[]::new);
        if (System.getProperty("os.name").startsWith("Mac")) {
            int[] result = {1};
            runOnAppKitThread(() -> result[0] = run(library, driver, engineArguments));
            System.exit(result[0]);
        }
        System.exit(run(library, driver, engineArguments));
    }

    private static void runProbe(String mainClass) throws Throwable {
        // JNI-attached threads start with the bootstrap context loader.
        // Application.launch() and FXML resolve application classes through it.
        if (Thread.currentThread().getContextClassLoader() == null) {
            Thread.currentThread().setContextClassLoader(ClassLoader.getSystemClassLoader());
        }
        GodotBootstrap.fixtureReady();
        // Glass starts its frame receiver before launching the FX application.
        // It posts Platform.exit on host stop so the launcher can finish teardown once.
        try {
            Class.forName(mainClass).getMethod("main", String[].class)
                    .invoke(null, (Object) new String[0]);
            GodotBridge.awaitRendererShutdown(0);
        } catch (Throwable exception) {
            Throwable original = exception instanceof InvocationTargetException invocation ? invocation.getCause() : exception;
            try {
                // Keep JNI queues open while FX hides windows and the renderer
                // disposes their targets. Only then report the original failure
                // to the native worker, which closes queue admission.
                Platform.exit();
                GodotBridge.awaitRendererShutdown(10_000);
                long tick = 0, deadline = System.nanoTime()+10_000_000_000L;
                while (!GodotBridge.isShutdownDrained()) {
                    if (System.nanoTime()>deadline) throw new IllegalStateException("Godot failure cleanup did not drain");
                    tick=GodotBridge.awaitTick(tick,100);
                    if (tick<0) throw new IllegalStateException("Godot stopped before failure cleanup drained");
                }
            } catch (Throwable cleanup) { original.addSuppressed(cleanup); }
            throw original;
        }
    }

    private static byte[] hash(java.security.MessageDigest digest, java.io.InputStream input) throws Exception {
        try (var stream = new java.security.DigestInputStream(input, digest)) {
            stream.transferTo(java.io.OutputStream.nullOutputStream());
        }
        return digest.digest();
    }
}
