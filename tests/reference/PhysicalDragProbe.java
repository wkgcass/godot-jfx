import javafx.application.*;
import javafx.scene.*;
import javafx.scene.layout.Background;
import javafx.scene.layout.BackgroundFill;
import javafx.scene.layout.CornerRadii;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Circle;
import javafx.stage.Stage;
import javafx.stage.StageStyle;

// Replicates the VFX title-bar drag and resize grip. Default is synthetic
// mode: the GDScript side injects the press/motion/release sequence host-side
// on the probe's title commands, with coordinates racing ahead of the window
// so the pointer position leaves the window bounds mid-gesture (the reported
// VFX failure). GODOT_JFX_PHYSICAL_DRAG_ROBOT=1 switches to physical mode,
// where the Glass Robot moves the real cursor faster than the window can
// follow; only that mode exercises OS-level delivery (cursor clamping at the
// screen edge, WM mouse-leave notifications). Every mouse event on the scene
// is recorded; a button-less MOUSE_MOVED or a MOUSE_EXITED mid-gesture ends
// Quantum's press-drag-release gesture (Scene$MouseHandler.process: "gesture
// ended" on MOUSE_MOVED), which is the failure mechanism this probe detects.
public final class PhysicalDragProbe extends Application {
    private static final boolean ROBOT_MODE = "1".equals(System.getenv("GODOT_JFX_PHYSICAL_DRAG_ROBOT"));
    private static volatile Throwable failure;
    private static volatile boolean complete;
    private Stage stage;
    private final java.util.List<String> trace = java.util.Collections.synchronizedList(new java.util.ArrayList<>());
    private static volatile Thread driver;
    private com.sun.glass.ui.GlassRobot robot;
    private boolean robotPressed;
    private boolean cursorSaved;
    private double originalCursorX, originalCursorY;
    private volatile int draggedEvents;
    private double oldStageX, oldStageY, oldScreenX, oldScreenY;
    private double oldStageW, oldStageH, oldSceneX, oldSceneY;
    private volatile String phase = "idle";
    private volatile boolean gestureActive;

    @Override public void start(Stage s) {
        try {
            stage = s;
            s.initStyle(StageStyle.TRANSPARENT);
            var root = new Pane();
            var content = new Pane();
            content.setLayoutX(0.5);
            content.setLayoutY(0.5);
            content.setPrefSize(419, 319);
            content.setBackground(new Background(new BackgroundFill(Color.rgb(40, 44, 52), new CornerRadii(8), null)));
            var bar = new Pane();
            bar.setPrefSize(420, 28);
            bar.setBackground(new Background(new BackgroundFill(Color.rgb(60, 64, 72), CornerRadii.EMPTY, null)));
            var grip = new Circle(8, Color.rgb(120, 130, 150));
            grip.setLayoutX(412); grip.setLayoutY(312);
            root.getChildren().addAll(content, bar, grip);
            bar.setOnMousePressed(e -> { oldStageX = s.getX(); oldStageY = s.getY(); oldScreenX = e.getScreenX(); oldScreenY = e.getScreenY(); });
            bar.setOnMouseDragged(e -> {
                ++draggedEvents;
                s.setX(oldStageX + (e.getScreenX() - oldScreenX));
                s.setY(oldStageY + (e.getScreenY() - oldScreenY));
            });
            grip.setOnMousePressed(e -> { oldStageW = s.getWidth(); oldStageH = s.getHeight(); oldSceneX = e.getSceneX(); oldSceneY = e.getSceneY(); });
            grip.setOnMouseDragged(e -> {
                ++draggedEvents;
                s.setWidth(Math.max(256, oldStageW + (e.getSceneX() - oldSceneX)));
                s.setHeight(Math.max(128, oldStageH + (e.getSceneY() - oldSceneY)));
            });
            var scene = new Scene(root, 420, 320, Color.TRANSPARENT);
            scene.addEventFilter(javafx.scene.input.MouseEvent.ANY, e -> {
                var type = e.getEventType().toString();
                // Record strictly press..release: a button-less move inside
                // that window is the gesture killer; moves re-sent by the OS
                // after release are ordinary input.
                if (type.endsWith("MOUSE_PRESSED") && e.isPrimaryButtonDown()) gestureActive = true;
                else if (type.endsWith("MOUSE_RELEASED")) gestureActive = false;
                if (gestureActive && type.startsWith("MOUSE_") && !phase.equals("idle")) {
                    trace.add(phase + " " + type + " primary=" + e.isPrimaryButtonDown()
                            + " screen=" + (int) e.getScreenX() + "," + (int) e.getScreenY());
                }
            });
            s.setScene(scene);
            s.setX(300); s.setY(300);
            // Only the physical drive needs the stage topmost and focused;
            // synthetic input routes by window ID and must not steal focus.
            if (ROBOT_MODE) s.setAlwaysOnTop(true);
            s.setTitle("PhysicalDrag ready");
            s.show();
            if (ROBOT_MODE) {
                s.toFront();
                s.requestFocus();
            }
            driver = new Thread(this::drive, "physical-drag-driver");
            driver.start();
        } catch (Throwable error) { recordFailure(error); Platform.exit(); }
    }

    private void fx(java.util.concurrent.Callable<?> action) throws Exception {
        var task = new java.util.concurrent.FutureTask<>(action);
        Platform.runLater(task);
        try { task.get(10, java.util.concurrent.TimeUnit.SECONDS); }
        catch (InterruptedException interrupted) {
            task.cancel(false);
            Thread.currentThread().interrupt();
            throw interrupted;
        } catch (java.util.concurrent.TimeoutException timeout) {
            task.cancel(false); // A queued action must not run after the driver gives up.
            throw new IllegalStateException("FX action timed out", timeout);
        }
    }

    private static synchronized void recordFailure(Throwable error) {
        if (failure == null) failure = error;
        else if (failure != error) failure.addSuppressed(error);
    }

    private void cleanupRobot() {
        if (robot == null) return;
        try { if (robotPressed) robot.mouseRelease(javafx.scene.input.MouseButton.PRIMARY); }
        catch (Throwable error) { recordFailure(error); }
        finally {
            robotPressed = false;
            try { if (cursorSaved) robot.mouseMove(originalCursorX, originalCursorY); }
            catch (Throwable error) { recordFailure(error); }
            finally { cursorSaved = false; }
            try { robot.destroy(); }
            catch (Throwable error) { recordFailure(error); }
            finally { robot = null; }
        }
    }

    @Override public void stop() {
        try { cleanupRobot(); }
        catch (Throwable error) { recordFailure(error); }
        finally { if (driver != null) driver.interrupt(); }
    }

    private void drive() {
        if (!ROBOT_MODE) {
            driveSynthetic();
            return;
        }
        try {
            Thread.sleep(2000);
            fx(() -> {
                robot = com.sun.glass.ui.Application.GetApplication().createRobot();
                robot.create();
                originalCursorX = robot.getMouseX();
                originalCursorY = robot.getMouseY();
                cursorSaved = true;
                return null;
            });
            // Physical presses land on the foreground window; wait for focus.
            var box = new boolean[1];
            for (int attempt = 0; attempt < 50 && !box[0]; ++attempt) {
                fx(() -> { box[0] = stage.isFocused(); if (!box[0]) stage.requestFocus(); return null; });
                Thread.sleep(200);
            }
            if (!box[0]) throw new AssertionError("Fixture window never gained focus");
            // Park the physical cursor away from the stage, then onto the title bar.
            fx(() -> { robot.mouseMove(40, 700); return null; });
            Thread.sleep(200);
            var bar = new double[4];
            fx(() -> { bar[0] = stage.getX() + 210; bar[1] = stage.getY() + 14; bar[2] = stage.getWidth(); bar[3] = stage.getHeight(); return null; });
            fx(() -> { robot.mouseMove(bar[0], bar[1]); return null; });
            Thread.sleep(400);
            var cursor = new double[2];
            fx(() -> { cursor[0] = robot.getMouseX(); cursor[1] = robot.getMouseY(); return null; });
            System.out.println("PHYS_CURSOR at " + cursor[0] + "," + cursor[1]
                    + " stage=" + (bar[0] - 210) + "," + (bar[1] - 14) + " " + bar[2] + "x" + bar[3]);
            var pixel = new Color[1];
            fx(() -> { pixel[0] = robot.getPixelColor(bar[0], bar[1]); return null; });
            System.out.println("PHYS_PIXEL bar=" + pixel[0]);
            var shot = new javafx.scene.image.WritableImage(700, 560);
            fx(() -> { robot.getScreenCapture(shot, 150, 150, 700, 560, false); return null; });
            javax.imageio.ImageIO.write(javafx.embed.swing.SwingFXUtils.fromFXImage(shot, null), "png",
                    new java.io.File(System.getenv("GODOT_JFX_PHYSICAL_DRAG_CAPTURE")));
            phase = "drag";
            fx(() -> { robotPressed = true; robot.mousePress(javafx.scene.input.MouseButton.PRIMARY); return null; });
            Thread.sleep(300);
            // 10 steps of 48 logical px upward every 30 ms (~1600 px/s): the
            // cursor escapes the 28-px bar and the window top within 2 steps.
            for (int k = 1; k <= 10; ++k) {
                double y = bar[1] - 48.0 * k;
                fx(() -> { robot.mouseMove(bar[0], y); return null; });
                Thread.sleep(30);
            }
            Thread.sleep(600);
            fx(() -> { robot.mouseRelease(javafx.scene.input.MouseButton.PRIMARY); robotPressed = false; return null; });
            Thread.sleep(500);
            phase = "idle";
            // The physical cursor is clamped to the screen (it stops at y=0
            // instead of the requested -166), so the expected window position
            // derives from the cursor's actual resting point, not the path sum.
            var finalCursor = new double[2];
            fx(() -> { finalCursor[0] = robot.getMouseX(); finalCursor[1] = robot.getMouseY(); return null; });
            double expectedY = 300 + (finalCursor[1] - bar[1]);
            var after = new double[4];
            fx(() -> { after[0] = stage.getX(); after[1] = stage.getY(); after[2] = stage.getWidth(); after[3] = stage.getHeight(); return null; });
            System.out.println("PHYS_DRAG dragEvents=" + draggedEvents + " finalY=" + after[1] + " expectedY=" + expectedY
                    + " finalCursorY=" + finalCursor[1]);
            if (Math.abs(after[1] - expectedY) > 12) {
                throw new AssertionError("Drag did not follow physical cursor outside the window: " + summarize());
            }
            int dragCount = draggedEvents;
            if (dragCount < 8) throw new AssertionError("Too few drag events: " + dragCount + "; " + summarize());

            // Resize grip: fast escape to the bottom-right.
            double gripX = after[0] + after[2] - 8, gripY = after[1] + after[3] - 8;
            fx(() -> { robot.mouseMove(gripX, gripY); return null; });
            Thread.sleep(300);
            draggedEvents = 0;
            phase = "resize";
            fx(() -> { robotPressed = true; robot.mousePress(javafx.scene.input.MouseButton.PRIMARY); return null; });
            Thread.sleep(300);
            for (int k = 1; k <= 8; ++k) {
                double x = gripX + 40.0 * k, y = gripY + 32.0 * k;
                fx(() -> { robot.mouseMove(x, y); return null; });
                Thread.sleep(30);
            }
            Thread.sleep(600);
            fx(() -> { robot.mouseRelease(javafx.scene.input.MouseButton.PRIMARY); robotPressed = false; return null; });
            Thread.sleep(500);
            phase = "idle";
            double expectedW = 420 + 320, expectedH = 320 + 256;
            fx(() -> { after[0] = stage.getWidth(); after[1] = stage.getHeight(); return null; });
            System.out.println("PHYS_RESIZE dragEvents=" + draggedEvents + " finalSize=" + after[0] + "x" + after[1]
                    + " expected=" + expectedW + "x" + expectedH);
            if (Math.abs(after[0] - expectedW) > 12 || Math.abs(after[1] - expectedH) > 12) {
                throw new AssertionError("Resize did not follow physical cursor outside the window: " + summarize());
            }
            if (draggedEvents < 6) throw new AssertionError("Too few resize drag events: " + draggedEvents + "; " + summarize());
            // Only a button-less MOUSE_MOVED ends Quantum's press-drag-release
            // gesture (Scene$MouseHandler). MOUSE_EXITED with a button held is
            // synthesized by Quantum on pick changes when the cursor leaves the
            // scene mid-drag — native JavaFX delivers the same, and both drag
            // phases above already assert the gesture survived (exact follow).
            checkTrace();
            fx(() -> { cleanupRobot(); return null; });
            complete = true;
            Platform.exit();
        } catch (Throwable error) {
            recordFailure(error);
            Platform.exit();
        }
    }

    // Synthetic mode: publish the gesture command as the window title; the
    // GDScript side injects press → fast steps → release host-side. Injected
    // coordinates are not screen-clamped, so expectations are the path sums.
    private void driveSynthetic() {
        try {
            Thread.sleep(2000);
            phase = "drag";
            fx(() -> { stage.setTitle("PhysicalDrag SYNTH DRAG"); return null; });
            // The gesture starts only when the GD side sees the title; wait for
            // the events themselves, not for settled geometry (the window is
            // stationary until the drag begins, which would pass a naive
            // settle check before the first injection).
            waitForDragEvents(10);
            double[] settled = waitSettle();
            phase = "idle";
            double expectedY = 300 - 10 * 48;
            System.out.println("PHYS_DRAG dragEvents=" + draggedEvents + " finalY=" + settled[1]
                    + " expectedY=" + expectedY + " synthetic");
            if (Math.abs(settled[1] - expectedY) > 12) {
                throw new AssertionError("Drag did not follow synthetic cursor outside the window: " + summarize());
            }

            draggedEvents = 0;
            phase = "resize";
            fx(() -> { stage.setTitle("PhysicalDrag SYNTH RESIZE"); return null; });
            waitForDragEvents(8);
            settled = waitSettle();
            phase = "idle";
            double expectedW = 420 + 8 * 40, expectedH = 320 + 8 * 32;
            System.out.println("PHYS_RESIZE dragEvents=" + draggedEvents + " finalSize=" + settled[2] + "x" + settled[3]
                    + " expected=" + expectedW + "x" + expectedH + " synthetic");
            if (Math.abs(settled[2] - expectedW) > 12 || Math.abs(settled[3] - expectedH) > 12) {
                throw new AssertionError("Resize did not follow synthetic cursor outside the window: " + summarize());
            }
            checkTrace();
            complete = true;
            Platform.exit();
        } catch (Throwable error) {
            recordFailure(error);
            Platform.exit();
        }
    }

    private void waitForDragEvents(int expected) throws Exception {
        long deadline = System.nanoTime() + 15_000_000_000L;
        while (draggedEvents < expected) {
            if (System.nanoTime() > deadline) {
                throw new AssertionError("Timed out waiting for " + expected + " drag events (got "
                        + draggedEvents + "); " + summarize());
            }
            Thread.sleep(50);
        }
    }

    // Poll the stage geometry until it is unchanged for three consecutive
    // 100 ms polls (a gesture runs ~1.5 s); fails after 15 s.
    private double[] waitSettle() throws Exception {
        double[] last = null;
        int stable = 0;
        long deadline = System.nanoTime() + 15_000_000_000L;
        while (System.nanoTime() < deadline) {
            double[] current = new double[4];
            fx(() -> { current[0] = stage.getX(); current[1] = stage.getY();
                    current[2] = stage.getWidth(); current[3] = stage.getHeight(); return null; });
            stable = java.util.Arrays.equals(last, current) ? stable + 1 : 0;
            if (stable >= 3) return current;
            last = current;
            Thread.sleep(100);
        }
        throw new AssertionError("Stage geometry never settled; " + summarize());
    }

    private void checkTrace() {
        var snapshot = traceSnapshot();
        var bad = snapshot.stream().filter(line -> line.contains("MOUSE_MOVED primary=false")).toList();
        if (!bad.isEmpty()) throw new AssertionError("Gesture-breaking events observed: " + bad.subList(0, Math.min(6, bad.size())));
        System.out.println("PHYS_TRACE " + snapshot.size() + " mouse events recorded during gestures");
    }

    private java.util.List<String> traceSnapshot() {
        synchronized (trace) { return java.util.List.copyOf(trace); }
    }

    private String summarize() {
        var snapshot = traceSnapshot();
        var tail = snapshot.subList(Math.max(0, snapshot.size() - 12), snapshot.size());
        return "trace tail: " + tail;
    }

    public static void main(String[] args) throws InterruptedException {
        try { launch(args); }
        finally {
            if (driver != null) {
                driver.interrupt();
                driver.join(10_000);
                if (driver.isAlive()) throw new AssertionError("Physical drag driver did not stop");
            }
        }
        if (failure != null) throw new AssertionError(failure);
        if (!complete) throw new AssertionError("Physical drag interaction incomplete");
        System.out.println("PHYSICAL_DRAG_PROBE_PASS");
    }
}
