import javafx.animation.PauseTransition;
import javafx.application.Application;
import javafx.application.GodotRuntime;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.layout.GodotView;
import javafx.scene.layout.Pane;
import javafx.stage.Stage;
import javafx.util.Duration;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/** Deliberately has no main. The JDK launcher must resolve javafx.graphics. */
public class DirectApplication extends Application {
    static String nativeWorkingDirectory() throws Exception {
        boolean windows = System.getProperty("os.name").startsWith("Windows");
        var command = windows ? new ProcessBuilder(System.getenv("ComSpec"), "/d", "/u", "/c", "cd")
                              : new ProcessBuilder("/bin/pwd", "-P");
        var process = command.start();
        String path = new String(process.getInputStream().readAllBytes(), windows ? StandardCharsets.UTF_16LE : StandardCharsets.UTF_8).strip();
        if (process.waitFor() != 0 || path.isBlank()) throw new AssertionError("Cannot read native working directory");
        return path;
    }

    @Override public void init() throws Exception {
        String expected = System.getProperty("test.expectedNativeCwd");
        if (expected != null) {
            String actual = nativeWorkingDirectory();
            if (!Files.isSameFile(Path.of(expected), Path.of(actual))) throw new AssertionError("Godot changed cwd to " + actual);
            System.out.println("NATIVE_CWD " + actual);
        }
        if (!GodotRuntime.PRISM_GODOT_ENABLED) throw new AssertionError("Prism was not ready in Application.init");
        System.out.println("APPLICATION_INIT " + Application.class.getResource("Application.class"));
    }

    @Override public void start(Stage stage) {
        Button button = new Button("Godot JavaFX");
        Pane root = new Pane(button);
        button.relocate(10, 10);
        stage.setScene(new Scene(root, 240, 160));
        stage.setTitle("Java library application");
        stage.show();
        if (!Platform.isFxApplicationThread()) throw new AssertionError("Wrong FX thread");
        System.out.println("APPLICATION_START");
        if (Boolean.getBoolean("test.input")) {
            GodotView view = new GodotView();
            view.setPrefSize(64, 64);
            view.relocate(150, 30);
            root.getChildren().add(view);
            view.loadScene("res://sample.tscn");
            Stage child = new Stage();
            child.initOwner(stage);
            child.setScene(new Scene(new Button("Child"), 100, 80));
            child.show();
            button.setOnAction(event -> {
                System.out.println("APPLICATION_INPUT_PASS");
                child.close();
                view.close();
                stage.close();
            });
        } else {
            PauseTransition delay = new PauseTransition(Duration.millis(350));
            delay.setOnFinished(event -> stage.close());
            delay.play();
        }
    }
    @Override public void stop() { System.out.println("APPLICATION_STOP"); }
}
