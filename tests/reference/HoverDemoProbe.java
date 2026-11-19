import io.vproxy.vfx.intro.IntroFXMain;
import io.vproxy.vfx.ui.button.ImageButton;
import io.vproxy.vfx.ui.scene.*;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.stage.Stage;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;

/** Physical hover over the real LoadingStage demo. Requires an idle desktop. */
public final class HoverDemoProbe extends IntroFXMain {
    private static final AtomicReference<Throwable> failure = new AtomicReference<>();
    private static volatile Thread driver;
    private static volatile boolean complete, stopping;
    private javafx.scene.robot.Robot robot;
    private double oldX, oldY;
    private boolean savedMouse;
    // These observation fields and every scene-graph access stay on the FX thread.
    private long lastMoveAt;
    private int enters, flickers;

    private static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }

    private static void collectButtons(Node node, List<Node> found) {
        if (node instanceof ImageButton || node instanceof io.vproxy.vfx.ui.button.AbstractFusionButton) found.add(node);
        if (node instanceof Parent parent) for (Node child : parent.getChildrenUnmodifiable()) collectButtons(child, found);
    }

    private static String describe(Node node) {
        if (node instanceof io.vproxy.vfx.ui.button.FusionButton fusion) {
            return "FusionButton '" + fusion.getTextNode().getText() + "'";
        }
        if (node instanceof ImageButton image) return "ImageButton";
        return node.getClass().getSimpleName();
    }

    private static <T> T fx(Callable<T> action) throws Exception {
        FutureTask<T> task = new FutureTask<>(action);
        Platform.runLater(task);
        try { return task.get(10, TimeUnit.SECONDS); }
        catch (TimeoutException | InterruptedException error) {
            task.cancel(false);
            if (error instanceof InterruptedException) Thread.currentThread().interrupt();
            throw error;
        }
    }
    private static void record(Throwable error) {
        Throwable original = failure.get();
        if (original == null && failure.compareAndSet(null, error)) return;
        original = failure.get();
        if (original != error) original.addSuppressed(error);
    }
    @Override public void start(Stage stage) {
        try {
            Platform.setImplicitExit(false);
            super.start(stage);
            stage.setMaximized(true);
            driver = new Thread(() -> {
                try { observe(stage); complete = true; }
                catch (Throwable error) { record(error); }
                finally {
                    boolean interrupted = Thread.interrupted();
                    try {
                        fx(() -> {
                            try { if (savedMouse) robot.mouseMove(oldX, oldY); }
                            finally { stage.close(); }
                            return null;
                        });
                    } catch (Throwable error) { record(error); }
                    finally {
                        Platform.exit();
                        if (interrupted) Thread.currentThread().interrupt();
                    }
                }
            }, "hover-demo-driver");
            driver.setDaemon(true);
            driver.start();
        } catch (Throwable error) { record(error); Platform.exit(); }
    }
    private void observe(Stage stage) throws Exception {
        Thread.sleep(5000);
        fx(() -> {
            var sf = IntroFXMain.class.getDeclaredField("mainScenes"); sf.setAccessible(true);
            var gf = IntroFXMain.class.getDeclaredField("sceneGroup"); gf.setAccessible(true);
            var scenes = (List<?>) sf.get(this);
            var group = (VSceneGroup) gf.get(this);
            var page = scenes.stream().map(VScene.class::cast)
                    .filter(x -> x.getClass().getSimpleName().equals("_08bLoadingStageDemoScene"))
                    .findFirst().orElseThrow();
            group.show(page, VSceneShowMethod.FROM_RIGHT);
            return null;
        });
        Thread.sleep(2000);
        Node target = fx(() -> {
            var buttons = new ArrayList<Node>();
            collectButtons(stage.getScene().getRoot(), buttons);
            require(!buttons.isEmpty(), "No buttons on demo scene");
            long start = System.nanoTime();
            for (Node button : buttons) {
                String name = describe(button);
                button.boundsInParentProperty().addListener((ob, was, now) ->
                        System.out.printf(java.util.Locale.ROOT, "HOVER_DEMO_EVENT t=%.0fms %s BOUNDS %s -> %s%n",
                                (System.nanoTime()-start)/1e6, name, was, now));
                button.layoutXProperty().addListener((ob, was, now) ->
                        System.out.printf(java.util.Locale.ROOT, "HOVER_DEMO_EVENT t=%.0fms %s LAYOUTX %s -> %s%n",
                                (System.nanoTime()-start)/1e6, name, was, now));
                button.hoverProperty().addListener((obs, was, inside) -> {
                    System.out.printf(java.util.Locale.ROOT, "HOVER_DEMO_EVENT t=%.0fms %s %s%n",
                            (System.nanoTime()-start)/1e6, name, inside ? "ENTER" : "EXIT");
                    if (inside) enters++;
                    if (!inside && was && System.nanoTime()-lastMoveAt > 500_000_000L) flickers++;
                });
            }
            Node found = buttons.stream().filter(b -> b instanceof io.vproxy.vfx.ui.button.FusionButton f
                    && f.getTextNode().getText() != null && f.getTextNode().getText().contains("LoadingStage")
                    && !f.isDisabled()).findFirst().orElseThrow(() -> new AssertionError("LoadingStage button missing/disabled"));
            robot = new javafx.scene.robot.Robot();
            oldX = robot.getMouseX(); oldY = robot.getMouseY(); savedMouse = true;
            return found;
        });
        for (int cycle = 0; cycle < 8; cycle++) {
            final int current = cycle;
            var b = fx(() -> {
                stage.setTitle("HoverDemo moving");
                var bounds = target.localToScreen(target.getBoundsInLocal());
                require(bounds != null, "LoadingStage button is not on screen");
                return bounds;
            });
            for (int glide = 0; glide <= 30; glide++) {
                final double y = b.getMinY()+b.getHeight()+60-glide*(60+b.getHeight()/2)/30.0;
                move(b.getMinX()+b.getWidth()/2, y);
                Thread.sleep(8); // Never block the FX thread while moving.
            }
            fx(() -> {
                stage.setTitle("HoverDemo HOLD " + current + " " + (int)(b.getMinX()-stage.getX())
                        + " " + (int)(b.getMinY()-stage.getY()) + " " + (int)b.getWidth() + " " + (int)b.getHeight());
                return null;
            });
            Thread.sleep(2500);
            fx(() -> { stage.setTitle("HoverDemo moving"); return null; });
            for (int glide = 0; glide <= 30; glide++) {
                move(b.getMinX()+b.getWidth()/2, b.getMinY()+b.getHeight()/2+glide*(60+b.getHeight()/2)/30.0);
                Thread.sleep(8);
            }
            // Measure the resting gap only after the pointer has crossed
            // the button and reached the empty area below it.
            fx(() -> { stage.setTitle("HoverDemo GAP " + current); return null; });
            Thread.sleep(1200);
        }
        fx(() -> {
            System.out.println("HOVER_DEMO_STATS enters="+enters+" flickers="+flickers);
            require(enters >= 8, "Hover cycles did not reach the target");
            return null;
        });
    }
    private void move(double x, double y) throws Exception {
        fx(() -> {
            if (stopping) throw new CancellationException("Hover demo stopping");
            robot.mouseMove(x,y); lastMoveAt=System.nanoTime(); return null;
        });
    }
    @Override public void stop() {
        stopping = true;
        if (driver != null && driver != Thread.currentThread()) driver.interrupt();
    }
    public static void main(String[] args) throws Exception {
        require("1".equals(System.getenv("GODOT_JFX_HOVER_DEMO_ROBOT")),
                "Physical hover requires explicit GODOT_JFX_HOVER_DEMO_ROBOT=1 and user consent");
        io.vproxy.vfx.theme.Theme.setTheme(new io.vproxy.vfx.intro.IntroTheme());
        try { Application.launch(HoverDemoProbe.class, args); }
        finally {
            try {
                if (driver != null) {
                    driver.interrupt(); driver.join(12000);
                    if (driver.isAlive()) record(new AssertionError("Hover driver did not stop"));
                }
            } finally { try { TaskManager.get().terminate(); } finally { GlobalScreenUtils.unregister(); } }
        }
        if (failure.get() != null) throw new AssertionError("Hover demo failed", failure.get());
        require(complete, "Hover demo incomplete");
        System.out.println("HOVER_DEMO_PASS");
    }
}
