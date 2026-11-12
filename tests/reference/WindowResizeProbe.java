import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.stage.Stage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

public final class WindowResizeProbe {
    private static Stage stage;
    private static long tick;
    private static void waitFrames(int count) {
        for (int i = 0; i < count; ++i) {
            tick = GodotBridge.awaitTick(tick, 1000);
            if (tick < 0) throw new AssertionError("Resize host stopped");
        }
    }
    private static void onFx(Runnable action) throws Exception {
        var done = new CountDownLatch(1);
        Platform.runLater(() -> { try { action.run(); } finally { done.countDown(); } });
        if (!done.await(5, TimeUnit.SECONDS)) throw new AssertionError("FX action timeout");
    }
    public static void main(String[] args) throws Exception {
        var ready = new CountDownLatch(1);
        Platform.startup(() -> {
            Platform.setImplicitExit(false);
            stage = new Stage(); stage.setTitle("Resize warmup");
            stage.setScene(new Scene(new Pane(), 240, 160, Color.RED));
            stage.show(); ready.countDown();
        });
        if (!ready.await(10, TimeUnit.SECONDS)) throw new AssertionError("Startup timeout");
        waitFrames(90);
        onFx(() -> stage.setTitle("Resize active"));
        for (int i = 0; i < 40; ++i) {
            final int index = i;
            onFx(() -> { stage.setWidth(240 + (index % 2) * 80); stage.setHeight(160 + (index % 3) * 40); });
            waitFrames(12);
        }
        waitFrames(90);
        onFx(() -> { stage.setTitle("Resize closing"); stage.close(); });
        waitFrames(90);
        Platform.exit();
        System.out.println("WINDOW_RESIZE_PROBE_PASS");
    }
}
