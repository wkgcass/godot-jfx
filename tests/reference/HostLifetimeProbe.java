import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class HostLifetimeProbe {
    private static final CountDownLatch done = new CountDownLatch(1);
    private static final AtomicReference<Throwable> failure = new AtomicReference<>();
    private static int actions;
    private static volatile Thread fxThread;
    private static void guarded(Runnable action) {
        try { action.run(); } catch (Throwable error) { failure.set(error); done.countDown(); }
    }
    private static Button button(String text) {
        Button result = new Button(text); result.relocate(10, 10); result.setPrefSize(110, 35); return result;
    }
    private static Scene scene(Button button, int w, int h, Color color) {
        Pane root = new Pane(button); root.setStyle("-fx-background-color: transparent;");
        return new Scene(root, w, h, color);
    }
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> guarded(() -> {
            fxThread=Thread.currentThread();
            // Keep standard implicit-exit behavior: closing the primary must not
            // terminate JavaFX while an independent Stage is still showing.
            Stage main = new Stage(); Button close = button("Close main");
            main.setScene(scene(close, 360, 230, Color.RED)); main.setTitle("Lifetime ready"); main.show();
            double x = main.getX(), y = main.getY();
            Stage survivor = new Stage(StageStyle.UNDECORATED);
            Button next = button("Continue");
            survivor.setScene(scene(next, 140, 90, Color.BLUE));
            survivor.setX(x + 170); survivor.setY(y + 60); survivor.show();
            close.setOnAction(event -> guarded(() -> {
                main.setTitle("Lifetime surviving"); main.close();
                survivor.requestFocus(); next.requestFocus();
            }));
            next.setOnAction(event -> guarded(() -> {
                if (main.isShowing()) throw new AssertionError("Primary did not close");
                if (++actions == 1) {
                    survivor.setResizable(false);
                    survivor.setAlwaysOnTop(true);
                    survivor.setAlwaysOnTop(false);
                    survivor.getScene().setFill(Color.LIME);
                }
                else if (actions == 2) {
                    survivor.getScene().setFill(Color.CYAN);
                    Stage third = new Stage(StageStyle.UNDECORATED);
                    Button finish = button("Finish"); third.setScene(scene(finish, 140, 70, Color.YELLOW));
                    third.setX(x + 20); third.setY(y + 150);
                    finish.setOnAction(e -> guarded(() -> {
                        third.close(); survivor.close(); done.countDown();
                    }));
                    third.show();
                } else throw new AssertionError("Duplicate surviving action");
            }));
        }));
        boolean completed = done.await(30, TimeUnit.SECONDS);
        if(completed && failure.get()==null) fxThread.join(5000);
        boolean implicitExit=fxThread!=null && !fxThread.isAlive();
        Platform.exit(); // Failure cleanup; success must already have exited implicitly.
        if (failure.get() != null) throw new AssertionError(failure.get());
        if (!completed || actions != 2) throw new AssertionError("Host lifetime interaction timeout: " + actions);
        if (!implicitExit) throw new AssertionError("Last independent Stage did not trigger implicit exit");
        System.out.println("HOST_LIFETIME_PROBE_PASS");
    }
}
