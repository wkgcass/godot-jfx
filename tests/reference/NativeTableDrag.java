import io.vproxy.vfx.control.drag.DragHandler;
import io.vproxy.vfx.intro.IntroFXMain;
import io.vproxy.vfx.intro.IntroTheme;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.scene.VScene;
import io.vproxy.vfx.ui.scene.VSceneGroup;
import io.vproxy.vfx.ui.scene.VSceneShowMethod;
import javafx.animation.AnimationTimer;
import javafx.application.Application;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.Group;
import javafx.scene.layout.Pane;
import javafx.stage.Stage;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * Native-pipeline comparison for the table drag: runs the demo on whatever
 * Glass/Prism the JVM picks (launch with -Dprism.order=d3d etc.), shows the
 * same table page the Godot probe uses, and drags it through the OS Robot,
 * timing pulses. Vertical with GODOT_JFX_DRAG_AXIS unset, horizontal with =h.
 */
public final class NativeTableDrag extends IntroFXMain {
    private static final boolean HORIZONTAL = "h".equals(System.getenv("GODOT_JFX_DRAG_AXIS"));

    private static void collect(Node node, int depth, List<Map.Entry<Node, Integer>> handlers) {
        if (node.getOnMouseDragged() instanceof DragHandler) handlers.add(Map.entry(node, depth));
        if (node instanceof Parent parent) for (Node child : parent.getChildrenUnmodifiable()) collect(child, depth + 1, handlers);
    }

    private static Throwable failure;
    private static boolean complete;
    private com.sun.glass.ui.GlassRobot robot;
    private boolean pressed;
    private boolean cursorSaved;
    private double originalX, originalY;
    private AnimationTimer timer;

    private static void recordFailure(Throwable error) {
        if (failure == null) failure = error;
        else if (failure != error) failure.addSuppressed(error);
    }

    private void cleanup() {
        if (timer != null) timer.stop();
        if (robot == null) return;
        try {
            if (pressed) robot.mouseRelease(javafx.scene.input.MouseButton.PRIMARY);
        } catch (Throwable error) { recordFailure(error); }
        finally {
            pressed = false;
            try {
                if (cursorSaved) robot.mouseMove(originalX, originalY);
            } catch (Throwable error) { recordFailure(error); }
            finally { cursorSaved = false; }
            try { robot.destroy(); }
            catch (Throwable error) { recordFailure(error); }
            finally { robot = null; }
        }
    }

    @Override public void start(Stage stage) {
        super.start(stage);
        // All scene access, robot operations and statistics stay on the FX
        // thread. No latches, shared mutable frame list or polling driver.
        timer = new AnimationTimer() {
            final long started = System.nanoTime();
            final List<Long> gaps = new ArrayList<>();
            VSceneGroup group;
            VScene page;
            long shown, previous;
            int step;
            double pressX, pressY;
            Group content;
            double previousPosition, displaced;

            @Override public void handle(long now) {
                try {
                    if (now - started > 45_000_000_000L)
                        throw new AssertionError("Native table drag timed out before 96 pulses");
                    if (shown == 0) {
                        if (now - started < 6_000_000_000L) return;
                        String backend = com.sun.glass.ui.Application.GetApplication().getClass().getName();
                        if (!backend.equals("com.sun.glass.ui.win.WinApplication"))
                            throw new AssertionError("Native Windows Glass required: " + backend);
                        System.out.println("NATIVE_TABLE_DRAG_BACKEND glass=" + backend);
                        var sf = IntroFXMain.class.getDeclaredField("mainScenes"); sf.setAccessible(true);
                        var gf = IntroFXMain.class.getDeclaredField("sceneGroup"); gf.setAccessible(true);
                        group = (VSceneGroup) gf.get(NativeTableDrag.this);
                        page = ((List<?>) sf.get(NativeTableDrag.this)).stream().map(s -> (VScene) s)
                                .filter(s -> s.getClass().getSimpleName().equals("_06cVTableViewDemo2Scene"))
                                .findFirst().orElseThrow();
                        group.show(page, VSceneShowMethod.FROM_RIGHT);
                        shown = now;
                        return;
                    }
                    if (robot == null) {
                        if (now - shown < 2_000_000_000L || group.getCurrentMainScene() != page) return;
                        var handlers = new ArrayList<Map.Entry<Node,Integer>>();
                        collect(page.getNode(), 0, handlers);
                        var target = handlers.stream().filter(entry -> {
                            if (!(entry.getKey() instanceof Pane pane) || pane.getChildren().isEmpty()
                                    || !(pane.getChildren().get(0) instanceof Group contents)) return false;
                            return !HORIZONTAL || contents.getLayoutBounds().getWidth() > pane.getWidth() + 1;
                        }).max(Map.Entry.comparingByValue()).orElseThrow(
                                () -> new AssertionError("No viewport scrollable on selected axis")).getKey();
                        content = (Group) ((Pane) target).getChildren().get(0);
                        previousPosition = position();
                        var bounds = target.localToScreen(target.getBoundsInLocal());
                        if (bounds == null || !stage.isFocused())
                            throw new AssertionError("Native Robot comparison requires a visible foreground window");
                        pressX = bounds.getMinX() + 10;
                        pressY = (bounds.getMinY() + bounds.getMaxY()) / 2;
                        robot = com.sun.glass.ui.Application.GetApplication().createRobot();
                        robot.create();
                        originalX = robot.getMouseX();
                        originalY = robot.getMouseY();
                        cursorSaved = true;
                        robot.mouseMove(pressX, pressY);
                        pressed = true; // release even if press throws after injecting input
                        robot.mousePress(javafx.scene.input.MouseButton.PRIMARY);
                        previous = now;
                        return;
                    }
                    if (!stage.isFocused()) throw new AssertionError("Native Robot comparison lost focus");
                    double currentPosition = position();
                    displaced += Math.abs(currentPosition - previousPosition);
                    previousPosition = currentPosition;
                    if (step > 0) {
                        int phase = step % 32, sweep = step / 32;
                        double offset = (sweep % 2 == 0 ? -phase : phase) * 25.0;
                        robot.mouseMove(HORIZONTAL ? pressX + offset : pressX,
                                HORIZONTAL ? pressY : pressY + offset);
                    }
                    gaps.add(now - previous);
                    previous = now;
                    if (++step < 96) return;
                    cleanup();
                    if (failure != null) { javafx.application.Platform.exit(); return; }
                    double sum = gaps.stream().mapToLong(Long::longValue).sum();
                    if (gaps.size() != 96 || sum <= 0) throw new AssertionError("Incomplete native drag measurement");
                    if (!Double.isFinite(displaced) || displaced < 200)
                        throw new AssertionError("Native drag did not scroll the table: " + displaced);
                    Collections.sort(gaps);
                    System.out.printf(java.util.Locale.ROOT,
                            "NATIVE_TABLE_DRAG axis=%s pulses=%d fps=%.3f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f displaced_px=%.0f%n",
                            HORIZONTAL ? "h" : "v", gaps.size(), gaps.size() * 1e9 / sum,
                            quantile(.5), quantile(.95), quantile(1), displaced);
                    complete = true;
                    javafx.application.Platform.exit();
                } catch (Throwable error) {
                    recordFailure(error);
                    cleanup();
                    javafx.application.Platform.exit();
                }
            }
            double quantile(double q) { return gaps.get((int)Math.ceil(q * gaps.size()) - 1) / 1e6; }
            double position() { return HORIZONTAL ? content.getLayoutX() : content.getLayoutY(); }
        };
        timer.start();
    }

    @Override public void stop() { cleanup(); }

    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme());
        try { Application.launch(NativeTableDrag.class, args); }
        catch (Throwable error) { recordFailure(error); }
        finally {
            try { io.vproxy.vfx.manager.task.TaskManager.get().terminate(); }
            catch (Throwable error) { recordFailure(error); }
            try { io.vproxy.vfx.control.globalscreen.GlobalScreenUtils.unregister(); }
            catch (Throwable error) { recordFailure(error); }
        }
        if (failure != null) throw new AssertionError("Native table drag failed", failure);
        if (!complete) throw new AssertionError("Native table drag closed before completion");
        System.out.println("NATIVE_TABLE_DRAG_PASS");
    }
}
