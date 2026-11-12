import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Files;
import java.nio.file.Path;
import javax.tools.ToolProvider;

public final class PrismGodotDetectionProbe {
    private static final String MARKER = "javafx.application.GodotRuntime";
    private static final String UTILS = "io.vproxy.vfx.util.FXUtils";

    public static void main(String[] args) throws Exception {
        check("missing-class", null, false);
        check("missing-field", "", false);
        check("wrong-type", "public static String PRISM_GODOT_ENABLED = \"true\";", false);
        check("instance-field", "public boolean PRISM_GODOT_ENABLED = true;", false);
        check("private-field", "private static boolean PRISM_GODOT_ENABLED = true;", false);
        check("false", "public static volatile boolean PRISM_GODOT_ENABLED = false;", false);
        check("true", "public static volatile boolean PRISM_GODOT_ENABLED = true;", true);
        System.out.println("PRISM_GODOT_DETECTION_PASS");
    }

    private static void check(String name, String fields, boolean expected) throws Exception {
        Path dir = Path.of("artifacts/reference/prism-godot-detection", name);
        Files.createDirectories(dir);
        if (fields != null) {
            Path source = dir.resolve("GodotRuntime.java");
            Files.writeString(source, "package javafx.application; public final class GodotRuntime { " + fields + " }");
            int status = ToolProvider.getSystemJavaCompiler().run(null, null, null,
                "--release", "11", "-d", dir.toString(), source.toString());
            if (status != 0) throw new AssertionError("Fixture compilation failed: " + name);
        }
        URL[] urls = {dir.toUri().toURL(), Path.of("artifacts/vfx/classes/java/main").toUri().toURL()};
        try (var loader = new URLClassLoader(urls, PrismGodotDetectionProbe.class.getClassLoader()) {
            @Override protected Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
                synchronized (getClassLoadingLock(name)) {
                    if (name.equals(MARKER) || name.equals(UTILS) || name.startsWith(UTILS + "$")) {
                        Class<?> type = findLoadedClass(name);
                        if (type == null) type = findClass(name);
                        if (resolve) resolveClass(type);
                        return type;
                    }
                    return super.loadClass(name, resolve);
                }
            }
        }) {
            var method = loader.loadClass(UTILS).getMethod("isPrismGodot");
            if (!Boolean.valueOf(expected).equals(method.invoke(null))) throw new AssertionError(name);
            if (name.equals("true") || name.equals("false")) {
                loader.loadClass(MARKER).getField("PRISM_GODOT_ENABLED").setBoolean(null, !expected);
            }
            if (!Boolean.valueOf(expected).equals(method.invoke(null))) throw new AssertionError("Result not cached: " + name);
            System.out.println("DETECTION_CASE_PASS " + name);
        }
    }
}
