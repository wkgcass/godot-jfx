import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.layout.VBox;
import javafx.stage.Stage;
import java.util.concurrent.Callable;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Hover-flicker observation. Default is synthetic mode: the GDScript side
 * injects motion events host-side on each HOLD/GAP title (no OS cursor
 * involvement). GODOT_JFX_HOVER_ROBOT=1 switches to the physical mode, which
 * drives the real OS cursor onto styled buttons via the Glass Robot and holds
 * it still. Any hoverProperty drop while the cursor is stationary is an
 * input-side flicker; a flicker seen on screen without one here is a
 * present-side defect. Phases: static scene, then a per-pulse animated label
 * so hover changes ride an active render loop like the demo's pages. The
 * driver sleeps on a worker thread — the FX thread must stay free to pulse
 * and render.
 */
public final class HoverFlickerProbe {
    static final boolean ROBOT_MODE = "1".equals(System.getenv("GODOT_JFX_HOVER_ROBOT"));
    static volatile Stage stage;
    static volatile Button[] buttons;
    static javafx.animation.AnimationTimer timer;
    // Accessed only by FX tasks, including cleanup after a failed probe.
    private static javafx.scene.robot.Robot robot;
    private static boolean cursorSaved;
    private static double originalX, originalY;


    public static void main(String[] args) throws Exception {
        Platform.startup(() -> Platform.setImplicitExit(false));
        Throwable failure = null;
        try {
            runProbe();
        } catch (Exception | Error e) {
            failure = e;
            throw e;
        } finally {
            // Clear interruption while waiting for cleanup, then restore it.
            boolean interrupted = Thread.interrupted();
            try {
                fx(() -> {
                    try {
                        if (timer != null) timer.stop();
                    } finally {
                        try {
                            if (robot != null && cursorSaved) robot.mouseMove(originalX, originalY);
                        } finally {
                            cursorSaved = false;
                            robot = null;
                            if (stage != null) stage.close();
                        }
                    }
                    return null;
                });
            } catch (Exception | Error e) {
                if (failure != null) failure.addSuppressed(e);
                else throw e;
            } finally {
                Platform.exit();
                if (interrupted) Thread.currentThread().interrupt();
            }
        }
        System.out.println("HOVER_FLICKER_PASS");
    }

    private static void runProbe() throws Exception {
        AtomicInteger flickers = new AtomicInteger();
        AtomicInteger enters = new AtomicInteger();
        AtomicInteger exits = new AtomicInteger();
        final long[] lastMoveAt = { 0 };
        fx(() -> {
            Button[] created = new Button[4];
            VBox box = new VBox(12);
            for (int i = 0; i < created.length; ++i) {
                Button button = new Button("按钮 " + i);
                button.getStyleClass().add("hover-probe");
                button.setMinWidth(300);
                button.setMinHeight(48);
                final boolean[] inside = { false };
                button.hoverProperty().addListener((obs, was, is) -> {
                    if (is) enters.incrementAndGet();
                    // A drop long after the last cursor move is a genuine
                    // flicker; right after a move it is the button change.
                    if (!is && inside[0]) exits.incrementAndGet();
                    if (!is && inside[0] && System.nanoTime() - lastMoveAt[0] > 500_000_000L) flickers.incrementAndGet();
                    inside[0] = is;
                });
                created[i] = button;
                box.getChildren().add(button);
            }
            Scene scene = new Scene(box, 360, 300);
            // JavaFX does not load data: stylesheets; drive the hover visual
            // from the property so the presented frame is observable.
            for (Button b : created) {
                b.hoverProperty().addListener((obs, was, is) ->
                        b.setStyle(is ? "-fx-background-color: #40a040;" : ""));
            }
            Stage shown = new Stage();
            shown.setScene(scene);
            shown.setX(120);
            shown.setY(120);
            // Robot mode drives the real OS cursor: the stage must actually be
            // topmost or the hover lands on whatever window overlaps it.
            // Synthetic mode injects host-side and needs no topmost.
            if (ROBOT_MODE) shown.setAlwaysOnTop(true);
            shown.setTitle("HoverFlicker READY");
            shown.show();
            stage = shown;
            buttons = created;
            timer = new javafx.animation.AnimationTimer() {
                @Override public void handle(long now) {
                    buttons[3].setText("按钮 " + (now / 1_000_000) % 10000);
                }
            };
            return null;
        });
        fx(() -> {
            if (ROBOT_MODE) {
                robot = new javafx.scene.robot.Robot();
                originalX = robot.getMouseX();
                originalY = robot.getMouseY();
                cursorSaved = true;
            }
            return null;
        });
        for (int phase = 0; phase < 2; ++phase) {
            final boolean animated = phase == 1;
            if (animated) fx(() -> { timer.start(); return null; });
            final int currentPhase = phase;
            for (int i = 0; i < buttons.length; ++i) {
                final int index = i;
                // Scene access, optional OS cursor movement and the title
                // publication form one FX task. The driver sleeps off-thread.
                fx(() -> {
                    stage.setTitle("HoverFlicker " + (animated ? "ANIM" : "STATIC"));
                    var b = buttons[index].localToScreen(buttons[index].getBoundsInLocal());
                    if (b == null) throw new IllegalStateException("Button not on screen");
                    if (robot != null) robot.mouseMove(b.getMinX() + b.getWidth() / 2, b.getMinY() + 6);
                    lastMoveAt[0] = System.nanoTime();
                    stage.setTitle("HoverFlicker HOLD " + currentPhase + " " + index
                            + " " + (int) (b.getMinX() - stage.getX()) + " " + (int) (b.getMinY() - stage.getY())
                            + " " + (int) b.getWidth() + " " + (int) b.getHeight());
                    return null;
                });
                Thread.sleep(3000);
                fx(() -> {
                    stage.setTitle("HoverFlicker GAP " + currentPhase + " " + index);
                    return null;
                });
                Thread.sleep(400);
            }
            if (animated) fx(() -> { timer.stop(); return null; });
        }
        // Attach the replacement scene before adding FusionButton: its
        // scene listener needs the owning window immediately.
        var fusion = fx(() -> {
            io.vproxy.vfx.theme.Theme.setTheme(new io.vproxy.vfx.intro.IntroTheme());
            VBox box = new VBox(12);
            stage.setScene(new Scene(box, 360, 300));
            var button = new io.vproxy.vfx.ui.button.FusionButton("Hover Me");
            button.setPrefWidth(300);
            button.setPrefHeight(200);
            box.getChildren().add(button);
            stage.setTitle("HoverFlicker FUSION READY");
            return button;
        });
        Thread.sleep(800); // let the replaced scene lay out before mapping to screen
        for (int fusionCycle = 0; fusionCycle < 6; ++fusionCycle) {
            final int cycle = fusionCycle;
            fx(() -> {
                var b = fusion.localToScreen(fusion.getBoundsInLocal());
                if (b == null) throw new IllegalStateException("FusionButton not on screen");
                if (robot != null) robot.mouseMove(b.getMinX() + b.getWidth() / 2, b.getMinY() + b.getHeight() / 2);
                stage.setTitle("HoverFlicker FUSION HOLD " + cycle
                        + " " + (int) (b.getMinX() - stage.getX()) + " " + (int) (b.getMinY() - stage.getY())
                        + " " + (int) b.getWidth() + " " + (int) b.getHeight());
                return null;
            });
            Thread.sleep(2000);
            fx(() -> {
                stage.setTitle("HoverFlicker FUSION GAP " + cycle);
                if (robot != null) robot.mouseMove(stage.getX() - 60, stage.getY() - 60);
                return null;
            });
            Thread.sleep(1000);
        }
        System.out.println("HOVER_FLICKER_STATS enters=" + enters.get() + " exits=" + exits.get() + " flickers=" + flickers.get());
        GodotBridge.awaitTick(0, 500);
    }

    private static <T> T fx(Callable<T> action) throws Exception {
        FutureTask<T> task = new FutureTask<>(action);
        Platform.runLater(task);
        try {
            return task.get(10, TimeUnit.SECONDS);
        } catch (TimeoutException e) {
            task.cancel(false);
            throw new IllegalStateException("FX task did not complete within 10 seconds", e);
        } catch (InterruptedException e) {
            task.cancel(false);
            Thread.currentThread().interrupt();
            throw e;
        }
    }

    private HoverFlickerProbe() {}
}
