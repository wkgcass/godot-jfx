import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.tk.godot.GodotWindowLifecycle;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.stage.Stage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class WindowLifecycleProbe {
    private static Stage stage;
    private static long tick;
    private static void waitFrames(int count) {
        for (int i = 0; i < count; ++i) {
            tick = GodotBridge.awaitTick(tick,1000);
            if (tick < 0) throw new AssertionError("Lifecycle host stopped");
        }
    }
    private static void onFx(Runnable action) throws Exception {
        var done = new CountDownLatch(1); var error = new AtomicReference<Throwable>();
        Platform.runLater(() -> { try { action.run(); } catch (Throwable failure) { error.set(failure); } finally { done.countDown(); } });
        if (!done.await(5,TimeUnit.SECONDS)) throw new AssertionError("FX action timeout");
        if (error.get() != null) throw new AssertionError(error.get());
    }
    public static void main(String[] args) throws Exception {
        var closed = GodotWindowLifecycle.create(999999);
        closed.setVisible(true); closed.close(); closed.setVisible(true);
        if (!closed.snapshot().closed() || closed.snapshot().visible()) throw new AssertionError("Closed token resurrected");
        boolean missing = false;
        try { GodotWindowLifecycle.get(999999); } catch (IllegalStateException expected) { missing = true; }
        if (!missing) throw new AssertionError("Closed token retained in registry");
        var ready = new CountDownLatch(1);
        Platform.startup(() -> {
            Platform.setImplicitExit(false); stage = new Stage();
            stage.setTitle("Lifecycle warmup"); stage.setScene(new Scene(new Pane(),240,160,Color.RED));
            stage.show(); ready.countDown();
        });
        if (!ready.await(10,TimeUnit.SECONDS)) throw new AssertionError("Startup timeout");
        waitFrames(60);
        for (int i = 0; i < 8; ++i) {
            final int index = i;
            onFx(() -> { stage.setTitle("Transition"); stage.hide(); stage.getScene().setFill(index % 2 == 0 ? Color.LIME : Color.RED); });
            waitFrames(45);
            // Native title remains usable while a Stage is hidden; its peer may
            // be detached, so use the existing host title command as a test marker.
            GodotBridge.hostCommand(1,0,0,"Hidden " + index); waitFrames(20);
            onFx(() -> { stage.setTitle("Transition"); stage.show(); });
            waitFrames(45);
            onFx(() -> stage.setTitle("Visible " + index)); waitFrames(20);
        }
        onFx(() -> { stage.setTitle("Transition"); stage.close(); });
        waitFrames(60);
        Platform.exit();
        System.out.println("WINDOW_LIFECYCLE_PROBE_PASS");
    }
}
