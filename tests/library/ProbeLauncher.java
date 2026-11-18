import javafx.application.GodotRuntime;
import java.nio.file.Path;

/** Runs an existing Java observer against the matching library-mode Godot scene. */
public final class ProbeLauncher {
    public static void main(String[] args) throws Throwable {
        GodotRuntime.init(new GodotRuntime.Options(
                Path.of(System.getProperty("test.project")), "mobile", GodotRuntime.StartupWindow.HIDDEN));
        try {
            Class.forName(args[0]).getMethod("main", String[].class).invoke(null, (Object) new String[0]);
        } catch (java.lang.reflect.InvocationTargetException ex) {
            throw ex.getCause();
        }
    }
}
