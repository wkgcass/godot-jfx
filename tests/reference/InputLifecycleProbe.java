import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.layout.Pane;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** Hide/close a secondary Stage during a held gesture, then reuse its Scene. */
public final class InputLifecycleProbe {
    private static final CountDownLatch done = new CountDownLatch(1);
    private static final AtomicReference<Throwable> failure = new AtomicReference<>();
    private static Stage main, child;
    private static Button target;
    private static int cycle, actions, drags;
    private static boolean scheduled, canceled;

    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    private static void guarded(Runnable action) {
        try { action.run(); } catch (Throwable error) { failure.set(error); done.countDown(); }
    }
    private static void showChild(String title) {
        child.setX(main.getX() + 160); child.setY(main.getY() + 70);
        child.show(); child.requestFocus(); target.requestFocus(); main.setTitle(title);
    }
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> guarded(() -> {
            Platform.setImplicitExit(false);
            main = new Stage();
            Button resume = new Button("Resume"); resume.resizeRelocate(20, 20, 110, 35);
            resume.setPrefSize(110, 35);
            resume.setOnAction(event -> guarded(() -> {
                check(canceled, "Resume arrived before cancellation");
                check(actions == cycle, "Late release activated hidden control");
                showChild("Lifecycle restored " + cycle);
            }));
            main.setScene(new Scene(new Pane(resume), 360, 230)); main.show();
            child = new Stage(StageStyle.UNDECORATED); child.initOwner(main);
            target = new Button("Hold"); target.relocate(10, 10); target.setPrefSize(110, 35);
            target.setOnMouseDragged(event -> ++drags);
            target.armedProperty().addListener((o, old, armed) -> {
                if (!armed || scheduled || canceled) return;
                scheduled = true;
                Platform.runLater(() -> guarded(() -> {
                    if (cycle < 3) child.hide(); else child.close();
                    check(!target.isArmed(), "Hidden/closed Button stayed armed in cycle " + cycle);
                    check(actions == cycle, "Cancellation activated Button");
                    check(drags == 0, "Cancellation generated a drag");
                    canceled = true; main.setTitle("Lifecycle hidden " + cycle);
                }));
            });
            target.setOnAction(event -> guarded(() -> {
                check(canceled, "Unexpected held-input action");
                check(++actions == cycle + 1, "Duplicate action");
                if (++cycle == 6) { child.close(); main.close(); done.countDown(); return; }
                canceled = false; scheduled = false;
                main.setTitle("Lifecycle ready " + cycle);
            }));
            child.setScene(new Scene(new Pane(target), 140, 90));
            showChild("Lifecycle ready 0");
        }));
        boolean completed = done.await(30, TimeUnit.SECONDS); Platform.exit();
        if (failure.get() != null) throw new AssertionError(failure.get());
        check(completed, "Lifecycle input timeout");
        System.out.println("INPUT_LIFECYCLE_PROBE_PASS");
    }
}
