import com.sun.javafx.stage.WindowHelper;
import com.sun.javafx.tk.TKStage;
import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Platform;
import javafx.scene.Group;
import javafx.scene.Scene;
import javafx.stage.Stage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

public final class VirtualKeyboardProbe {
    private static Stage stage; // FX thread only.
    private static boolean inputRequested;

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static void fx(Runnable action) throws Exception {
        FutureTask<Void> task = new FutureTask<>(action, null);
        Platform.runLater(task);
        try { task.get(10, TimeUnit.SECONDS); }
        catch (TimeoutException error) {
            task.cancel(false);
            throw new IllegalStateException("Virtual keyboard FX task timed out", error);
        } catch (InterruptedException error) {
            task.cancel(false);
            Thread.currentThread().interrupt();
            throw error;
        }
    }

    public static void main(String[] args) throws Exception {
        CountDownLatch ready = new CountDownLatch(1);
        Throwable failure = null;
        try {
            Platform.startup(() -> { Platform.setImplicitExit(false); ready.countDown(); });
            require(ready.await(10, TimeUnit.SECONDS), "JavaFX startup timed out");
            fx(() -> {
                stage = new Stage();
                stage.setScene(new Scene(new Group(), 200, 100));
                stage.show();
                TKStage peer = WindowHelper.getPeer(stage);
                require(peer != null, "Stage peer missing");
                // Only call completion and host liveness are checked. Native
                // success does not prove that the OS keyboard became visible.
                inputRequested = true; // Also clean up a partially completed request.
                peer.requestInput("", 0, 100, 30, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0);
                peer.requestInput("draft", 0, 100, 30, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0);
                peer.releaseInput();
                inputRequested = false;
            });
            long tick = GodotBridge.awaitTick(0, 1000);
            require(tick >= 0, "Host stopped after virtual keyboard commands");
            long baseline = tick;
            long deadline = System.nanoTime() + 2_000_000_000L;
            while (System.nanoTime() < deadline) {
                long next = GodotBridge.awaitTick(tick, 1000);
                require(next >= tick, "Host stopped or tick moved backwards");
                tick = next;
            }
            require(tick > baseline, "Host ticks did not advance after virtual keyboard commands");
        } catch (Exception | Error error) {
            failure = error;
            throw error;
        } finally {
            boolean interrupted = Thread.interrupted();
            try {
                fx(() -> {
                    if (stage == null) return;
                    try {
                        TKStage peer = WindowHelper.getPeer(stage);
                        if (inputRequested && peer != null) peer.releaseInput();
                    } finally {
                        inputRequested = false;
                        stage.close();
                        stage = null;
                    }
                });
            } catch (Exception | Error error) {
                if (failure != null) failure.addSuppressed(error);
                else throw error;
            } finally {
                Platform.exit();
                if (interrupted) Thread.currentThread().interrupt();
            }
        }
        System.out.println("VIRTUAL_KEYBOARD_PASS: Java calls completed, host ticks advanced and cleanup completed; OS visibility not verified");
    }
}
