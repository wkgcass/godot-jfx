import io.vproxy.vfx.intro.*;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.scene.*;
import io.vproxy.vfx.control.drag.DragHandler;
import io.vproxy.vfx.ui.button.FusionButton;
import javafx.scene.control.CheckBox;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import javafx.animation.AnimationTimer;
import javafx.application.*;
import javafx.scene.*;
import javafx.scene.input.MouseButton;
import javafx.scene.input.MouseEvent;
import javafx.scene.layout.Pane;
import javafx.stage.Stage;
import java.util.*;

/**
 * Drives the large-table page's own drag-scroll handler once per pulse and
 * times the pulse cadence. Events go straight to the handler the viewport
 * installed, so the probe never needs window focus or a physical mouse; the
 * measured cost is the render pipeline the drag exercises (content translation
 * re-encoding, pass and presentation work), which is where the jank lives.
 */
public final class VfxTableScrollProbe extends IntroFXMain {
    private static Throwable failure;
    private static boolean complete;
    private AnimationTimer driver;
    private javafx.scene.robot.Robot robot;
    private boolean pressed, cursorSaved;
    private double originalX, originalY;

    private static void recordFailure(Throwable error) {
        if (failure == null) failure = error;
        else if (failure != error) failure.addSuppressed(error);
    }

    private void cleanupInput() {
        if (driver != null) driver.stop();
        if (robot == null) return;
        try { if (pressed) robot.mouseRelease(MouseButton.PRIMARY); }
        catch (Throwable error) { recordFailure(error); }
        finally { pressed = false; }
        try { if (cursorSaved) robot.mouseMove(originalX, originalY); }
        catch (Throwable error) { recordFailure(error); }
        finally { cursorSaved = false; robot = null; }
    }

    @Override public void stop() { cleanupInput(); }

    // "real": the Godot side injects high-rate synthesized motion through the
    // full input pipeline; the probe only publishes the press point and
    // observes. Default "direct" drives the viewport's own handler per pulse.
    private static final boolean REAL_DRAG = "real".equals(System.getenv("GODOT_JFX_DRAG_MODE"));
    // "robot": the Glass Robot drives the physical cursor (real OS input
    // layer); the window must be foreground for the duration.
    private static final boolean ROBOT_DRAG = "robot".equals(System.getenv("GODOT_JFX_DRAG_MODE"));
    // "h": drag horizontally (exercises the wrapping horizontal scroll pane);
    // default vertical (the table's own row-recycling handler).
    private static final boolean HORIZONTAL = "h".equals(System.getenv("GODOT_JFX_DRAG_AXIS"));

    private static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }

    private static void collect(Node node, int depth, List<Map.Entry<Node, Integer>> handlers) {
        if (node.getOnMouseDragged() instanceof DragHandler) handlers.add(Map.entry(node, depth));
        if (node instanceof Parent parent) for (Node child : parent.getChildrenUnmodifiable()) collect(child, depth + 1, handlers);
    }

    private static MouseEvent event(javafx.event.EventType<MouseEvent> type, Node node,
                                    double x, double y, boolean pressed) {
        var screen = node.localToScreen(x, y);
        require(screen != null, "Drag target has no screen coordinates");
        var scene = node.localToScene(x, y);
        return new MouseEvent(null, node, type, scene.getX(), scene.getY(), screen.getX(), screen.getY(), MouseButton.PRIMARY, 1,
                false, false, false, false, pressed, false, false, false, false, false, null).copyFor(node, node);
    }

    static ThreadStackSampler sampler;
    static void startSampler() {
        String configured = System.getenv("GODOT_JFX_STACK_SAMPLE");
        if (configured == null || configured.isBlank()) return;
        int period;
        try { period = Integer.parseInt(configured); }
        catch (NumberFormatException invalid) { throw new IllegalArgumentException("Invalid GODOT_JFX_STACK_SAMPLE: " + configured, invalid); }
        sampler = new ThreadStackSampler(period);
        System.out.println("VFX_TABLE_SAMPLING period_ms=" + period + " diagnostic_only=true");
    }
    static void stopSamplerAndReport() {
        if (sampler == null) return;
        var entries = sampler.snapshot();
        for (int i = 0; i < Math.min(30, entries.size()); ++i)
            System.out.println("VFX_TABLE_SAMPLE " + entries.get(i).count() + " " + entries.get(i).stack());
        System.out.println("VFX_TABLE_SAMPLE_DROPPED " + sampler.droppedSamples());
    }

    private static int sweeps() {
        String configured = System.getenv("GODOT_JFX_TABLE_SWEEPS");
        int value = configured == null || configured.isBlank() ? 3 : Integer.parseInt(configured);
        require(value >= 3 && value <= 30, "Table sweeps must be in [3,30]");
        return value;
    }

    @Override public void start(Stage stage) {
        try {
            super.start(stage);
            startSampler();
            System.out.println("VFX_TABLE_SCROLL_BACKEND glass=" + com.sun.glass.ui.Application.GetApplication().getClass().getName()
                    + " prism=" + com.sun.prism.GraphicsPipeline.getPipeline().getClass().getName());
            var sf = IntroFXMain.class.getDeclaredField("mainScenes"); sf.setAccessible(true);
            var gf = IntroFXMain.class.getDeclaredField("sceneGroup"); gf.setAccessible(true);
            var pages = (List<?>) sf.get(this);
            var page = pages.stream()
                    .map(s -> (VScene) s)
                    .filter(s -> s.getClass().getSimpleName().equals("_06cVTableViewDemo2Scene"))
                    .findFirst().orElseThrow();
            var group = (VSceneGroup) gf.get(this);
            boolean lens = "1".equals(System.getenv("GODOT_JFX_TABLE_BLACKHOLE"));
            if (lens) {
                ((FusionButton)stage.getScene().lookup("#intro-menu-button")).getOnAction().handle(null);
            } else {
                group.show(page, VSceneShowMethod.FROM_RIGHT);
            }
            driver = new AnimationTimer() {
                final long started = System.nanoTime();
                final long deadline = started + 120_000_000_000L;
                Node target;
                Group container;
                long seenEvents;
                double displaced, lastPosition = Double.NaN;
                String lastSeen = "none";
                double pressX, pressY;
                double baseY, nodeHeight;
                final List<Long> gaps = new ArrayList<>();
                final List<Long> idleGaps = new ArrayList<>();
                long previous, finish;
                int step, idleStep;
                boolean lensSelected;
                final int total = sweeps() * 32;
                @Override public void handle(long now) {
                    if (finish != 0) {
                        if (now - finish > 600_000_000L) { complete = true; stop(); Platform.exit(); }
                        return;
                    }
                    try {
                        require(now < deadline, "Table scroll timeout");
                        if (lens && !lensSelected) {
                            var toggle = (CheckBox)stage.getScene().lookup("#blackhole-effect-toggle");
                            if (toggle == null) return;
                            toggle.fire();
                            require(toggle.isSelected(), "Blackhole checkbox was not selected");
                            toggle.getParent().getChildrenUnmodifiable().stream()
                                .filter(FusionButton.class::isInstance).map(FusionButton.class::cast)
                                .skip(pages.indexOf(page)).findFirst().orElseThrow().getOnAction().handle(null);
                            lensSelected = true;
                            return;
                        }
                        if (container == null) {
                            if (now - started < 3_000_000_000L || group.getCurrentMainScene() != page) return;
                            var handlers = new ArrayList<Map.Entry<Node, Integer>>();
                            collect(page.getNode(), 0, handlers);
                            require(!handlers.isEmpty(), "No drag-scroll handler on the table page");
                            // Vertical: the deepest table viewport. Horizontal: the
                            // deepest viewport whose content actually exceeds its width.
                            target = handlers.stream().filter(entry -> {
                                if (!HORIZONTAL) return true;
                                if (!(entry.getKey() instanceof Pane pane) || pane.getChildren().isEmpty()
                                        || !(pane.getChildren().get(0) instanceof Group contents)) return false;
                                return contents.getLayoutBounds().getWidth() > pane.getWidth() + 1;
                            }).max(Map.Entry.comparingByValue()).orElseThrow(
                                    () -> new AssertionError("No viewport scrollable on selected axis")).getKey();
                            var bounds = target.localToScreen(target.getBoundsInLocal());
                            require(bounds != null && bounds.getHeight() > 100, "Table viewport is not laid out");
                            container = (Group) ((Pane) target).getChildren().get(0);
                            require(container != null && !container.getChildren().isEmpty(), "Viewport has no content");
                            baseY = (bounds.getMinY() + bounds.getMaxY()) / 2;
                            nodeHeight = bounds.getHeight();
                            if (lens) {
                                target.fireEvent(event(MouseEvent.MOUSE_MOVED, target, 10, nodeHeight / 2, false));
                                require(group.getNode().getEffect() instanceof javafx.scene.effect.GodotShaderEffect,
                                    "Blackhole effect did not attach to the table scene group");
                            }
                            stage.setTitle("VfxTableScroll IDLE");
                            previous = now;
                            return;
                        }
                        // Steady-state reference window: the scene is static, so
                        // anything measured here is the page's idle render cost.
                        if (idleStep < 60) {
                            if (++idleStep > 3) idleGaps.add(now - previous);
                            previous = now;
                        if (idleStep == 60) {
                            Collections.sort(idleGaps);
                            double idleSum = idleGaps.stream().mapToLong(Long::longValue).sum();
                            System.out.printf(java.util.Locale.ROOT,
                                    "VFX_TABLE_SCROLL_IDLE pulses=%d fps=%.3f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f%n",
                                    idleGaps.size(), idleGaps.size() * 1e9 / idleSum,
                                    idleQuantile(.5), idleQuantile(.95), idleQuantile(1));
                            if (!REAL_DRAG && !ROBOT_DRAG) target.getOnMousePressed().handle(event(MouseEvent.MOUSE_PRESSED, target, 10,
                                    nodeHeight / 2, true));
                        }
                        return;
                    }
                    if ((REAL_DRAG || ROBOT_DRAG) && step == 0) {
                        stage.getScene().addEventFilter(MouseEvent.ANY,
                                e -> { seenEvents++; if (seenEvents <= 3 || seenEvents % 32 == 0) lastSeen = e.getEventType() + " " + e.getX() + "," + e.getY(); });
                        System.out.println("VFX_TABLE_TARGET bounds=" + target.localToScreen(target.getBoundsInLocal())
                                + " stage=" + stage.getX() + "," + stage.getY());
                    }
                    if (REAL_DRAG && step == 0) {
                        // Publish the stage-logical press point once; the Godot
                        // side injects real high-rate motion events from here.
                        int localX = (int) Math.round(10 + target.localToScreen(target.getBoundsInLocal()).getMinX() - stage.getX());
                        int localY = (int) Math.round(baseY - stage.getY());
                        stage.setTitle("VfxTableScroll REAL " + localX + " " + localY);
                    }
                    if (ROBOT_DRAG && step == 0) {
                        stage.setTitle("VfxTableScroll START");
                        require(stage.isFocused(), "Robot drag requires foreground window");
                        robot = new javafx.scene.robot.Robot();
                        originalX = robot.getMouseX();
                        originalY = robot.getMouseY();
                        cursorSaved = true;
                        pressX = target.localToScreen(target.getBoundsInLocal()).getMinX() + 10;
                        pressY = baseY;
                        robot.mouseMove(pressX, pressY);
                        pressed = true; // Clean up even if injection partially succeeds.
                        robot.mousePress(javafx.scene.input.MouseButton.PRIMARY);
                    }
                    if (ROBOT_DRAG && step > 0) {
                        require(stage.isFocused(), "Robot drag lost focus");
                        int phase = step % 32, sweep = step / 32;
                        double offset = (sweep % 2 == 0 ? -phase : phase) * 25.0;
                        if (HORIZONTAL) robot.mouseMove(pressX + offset, pressY);
                        else robot.mouseMove(pressX, pressY + offset);
                    }
                    if (ROBOT_DRAG && step == total - 1) {
                        robot.mouseRelease(javafx.scene.input.MouseButton.PRIMARY);
                        pressed = false;
                    }
                    // Sawtooth screen position: 32 pulses up (content scrolls),
                    // 32 back down to the top, 32 up again. Dragging down past
                    // the top clamps to zero, so the first sweep must go up.
                    if (step == 0 && !REAL_DRAG) stage.setTitle("VfxTableScroll START");
                    if (!REAL_DRAG && !ROBOT_DRAG) {
                        int phase = step % 32, sweep = step / 32;
                        double offset = (sweep % 2 == 0 ? -phase : phase) * 25.0;
                        double before = position();
                        var motion = event(MouseEvent.MOUSE_DRAGGED, target,
                                HORIZONTAL ? 10 + offset : 10,
                                HORIZONTAL ? nodeHeight / 2 : nodeHeight / 2 + offset, true);
                        if (lens) target.fireEvent(motion);
                        else target.getOnMouseDragged().handle(motion);
                        displaced += Math.abs(position() - before);
                    } else {
                        // The Godot side drives the real events; observe the
                        // resulting scroll between pulses.
                        double current = position();
                        if (!Double.isNaN(lastPosition)) displaced += Math.abs(current - lastPosition);
                        lastPosition = current;
                    }
                        gaps.add(now - previous);
                        previous = now;
                        if (++step < total) return;
                        double sum = gaps.stream().mapToLong(Long::longValue).sum();
                        var chronologicalGaps = new ArrayList<>(gaps);
                        Collections.sort(gaps);
                        System.out.printf(java.util.Locale.ROOT,
                                "VFX_TABLE_SCROLL pulses=%d fps=%.3f p50_ms=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f displaced_px=%.0f width=%.1f height=%.1f scale=%.2f%n",
                                gaps.size(), gaps.size() * 1e9 / sum, quantile(.5), quantile(.95), quantile(.99),
                                quantile(1), (double) displaced, stage.getWidth(), stage.getHeight(), stage.getRenderScaleX());
                        System.out.println("VFX_TABLE_AXIS " + (HORIZONTAL ? "h" : "v"));
                        {   // Raw series for spike-period analysis in the log.
                            var series = new StringBuilder("VFX_TABLE_SCROLL_GAPS_MS");
                            var order = chronologicalGaps;
                            for (int i = 0; i < order.size(); ++i) series.append(' ').append(i).append(':')
                                    .append(String.format(java.util.Locale.ROOT, "%.1f", order.get(i) / 1e6));
                            System.out.println(series);
                        }
                        require(displaced >= 200, "Drag did not scroll the table; observed " + seenEvents + " events, last: " + lastSeen);
                        stage.setTitle("VfxTableScroll END");
                        stopSamplerAndReport();
                        finish = now;
                    } catch (Throwable error) { recordFailure(error); cleanupInput(); Platform.exit(); }
                }
                double position() { return HORIZONTAL ? container.getLayoutX() : container.getLayoutY(); }
                double quantile(double q) { return gaps.get(Math.min(gaps.size() - 1, (int) Math.ceil(q * gaps.size()) - 1)) / 1e6; }
                double idleQuantile(double q) { return idleGaps.get(Math.min(idleGaps.size() - 1, (int) Math.ceil(q * idleGaps.size()) - 1)) / 1e6; }
            };
            driver.start();
        } catch (Throwable error) { recordFailure(error); cleanupInput(); Platform.exit(); }
    }

    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme());
        try {
            Application.launch(VfxTableScrollProbe.class, args);
        } catch (Throwable error) { recordFailure(error); }
        finally {
            try { if (sampler != null) sampler.close(); }
            catch (Throwable error) { recordFailure(error); }
            try { TaskManager.get().terminate(); }
            catch (Throwable error) { recordFailure(error); }
            try { GlobalScreenUtils.unregister(); }
            catch (Throwable error) { recordFailure(error); }
        }
        if (failure != null) throw new AssertionError(failure);
        require(complete, "Table scroll interaction incomplete");
        System.out.println("VFX_TABLE_SCROLL_PROBE_PASS");
    }
}
