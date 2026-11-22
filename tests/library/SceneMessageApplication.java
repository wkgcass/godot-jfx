import javafx.application.Application;
import javafx.application.GodotRuntime;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.stage.Stage;

public final class SceneMessageApplication extends Application {
    private static final String TOPIC = "scene.温度";
    // Each tree occupies two UTF-16 code units.
    private static final String LONG_TOPIC = "🌲".repeat(64);

    @Override public void init() {
        // The launcher calls init() off the FX Application Thread.
        expect(IllegalStateException.class, () -> GodotRuntime.postSceneMessage(TOPIC, 0));
    }

    @Override public void start(Stage stage) {
        stage.setScene(new Scene(new Pane(), 160, 100));
        stage.show();
        expect(NullPointerException.class, () -> GodotRuntime.postSceneMessage(null, 0));
        expect(IllegalArgumentException.class, () -> GodotRuntime.postSceneMessage("", 0));
        expect(IllegalArgumentException.class, () -> GodotRuntime.postSceneMessage(LONG_TOPIC + "x", 0));
        System.out.println("SCENE_MESSAGE_VALIDATION_PASS");

        GodotRuntime.postSceneMessage(LONG_TOPIC, Integer.MIN_VALUE);
        GodotRuntime.postSceneMessage(TOPIC, 0);
        GodotRuntime.postSceneMessage(TOPIC, 0);
        GodotRuntime.postSceneMessage(LONG_TOPIC, Integer.MAX_VALUE);
        GodotRuntime.postSceneMessage("done", -1);
    }

    private static void expect(Class<? extends RuntimeException> type, Runnable call) {
        try {
            call.run();
        } catch (RuntimeException error) {
            if (type.isInstance(error)) return;
            throw error;
        }
        throw new AssertionError("Expected " + type.getSimpleName());
    }

    @Override public void stop() {
        System.out.println("SCENE_MESSAGE_STOP");
    }
}
