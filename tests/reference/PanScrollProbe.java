import javafx.application.*;
import javafx.animation.AnimationTimer;
import javafx.scene.Scene;
import javafx.scene.control.ScrollPane;
import javafx.scene.input.ScrollEvent;
import javafx.scene.layout.VBox;
import javafx.scene.shape.Rectangle;
import javafx.stage.Stage;
import java.util.ArrayList;
import java.util.List;

// Trackpad pan-stream probe. This probe drives phases through the stage title;
// the Godot side watches the title and injects InputEventPanGesture streams at
// 5 events/frame while a scrolling phase is active: scroll to the bottom,
// over-scroll, reverse to the top, over-scroll, then idle ("fingers released").
// A correct pipeline accumulates monotonically, clamps exactly at both ends and
// never moves after the stream stops.
public final class PanScrollProbe extends Application {
    private static Throwable failure;
    private static boolean complete;

    private static final String[] PHASES = {"down", "over", "up", "overUp", "idle"};
    private static final int[] LENGTHS = {240, 20, 260, 20, 60};

    private final List<List<Double>> samples = new ArrayList<>();
    private int phase = -1, tick;
    private double travel;
    private static int scrollEvents;

    @Override public void start(Stage stage) {
        try {
            for (int i = 0; i < PHASES.length; ++i) samples.add(new ArrayList<>());
            var content = new VBox();
            for (int i = 0; i < 200; ++i)
                content.getChildren().add(new Rectangle(380, 40, javafx.scene.paint.Color.hsb(i * 1.8, 0.4, 0.85)));
            var scroll = new ScrollPane(content);
            scroll.setPrefSize(400, 300);
            scroll.addEventFilter(ScrollEvent.SCROLL, e -> {
                if (scrollEvents < 5 || scrollEvents % 200 == 0)
                    System.out.println("PAN_EVT n=" + scrollEvents + " deltaY=" + e.getDeltaY() + " total=" + e.getTotalDeltaY() + " type=" + e.getEventType());
                ++scrollEvents;
                if (phase == 0) travel -= e.getDeltaY();
                if (phase == 2) travel += e.getDeltaY();
            });
            stage.setScene(new Scene(scroll, 400, 300));
            stage.setTitle("PanScroll ready");
            stage.show();
            new AnimationTimer() {
                @Override public void handle(long now) {
                    try {
                        if (phase >= 0) samples.get(phase).add(scroll.getVvalue());
                        // JavaFX pulses and Godot input frames can run at different
                        // rates. Inject enough distance to traverse the content before
                        // checking that the skin clamps at the exact boundary.
                        double extent = content.getHeight() - scroll.getViewportBounds().getHeight();
                        boolean enoughTravel = (phase != 0 && phase != 2) || travel >= extent + 8;
                        if (phase < 0 || (++tick >= LENGTHS[phase] && enoughTravel)) {
                            tick = 0;
                            travel = 0;
                            if (phase == PHASES.length - 1) {
                                verify(scroll);
                                complete = true;
                                stop();
                                Platform.exit();
                                return;
                            }
                            ++phase;
                            stage.setTitle("PAN " + PHASES[phase]);
                        }
                    } catch (Throwable error) {
                        failure = error;
                        stop();
                        Platform.exit();
                    }
                }
            }.start();
        } catch (Throwable error) { failure = error; Platform.exit(); }
    }

    private static void monotonic(List<Double> values, boolean increasing, String name) {
        for (int i = 1; i < values.size(); ++i) {
            double d = values.get(i) - values.get(i - 1);
            if (increasing ? d < -1e-6 : d > 1e-6)
                throw new AssertionError(name + " not monotonic at " + i + ": " + values.get(i - 1) + " -> " + values.get(i));
        }
    }

    private static void clamped(List<Double> values, double expected, String name) {
        for (double v : values)
            if (Math.abs(v - expected) > 1e-6)
                throw new AssertionError(name + " clamp drifted: " + v + " != " + expected);
    }

    private void verify(ScrollPane scroll) {
        List<Double> down = samples.get(0), over = samples.get(1), up = samples.get(2),
                overUp = samples.get(3), idle = samples.get(4);
        System.out.println("PAN_SAMPLES down=" + down.size() + " over=" + over.size()
                + " up=" + up.size() + " overUp=" + overUp.size() + " idle=" + idle.size());
        if (down.size() < 100 || up.size() < 100) throw new AssertionError("streams too short");
        monotonic(down, true, "down");
        monotonic(up, false, "up");
        double bottom = down.get(down.size() - 1);
        if (Math.abs(bottom - 1.0) > 1e-6) throw new AssertionError("did not reach bottom: " + bottom);
        clamped(over, 1.0, "bottom");
        double top = up.get(up.size() - 1);
        if (Math.abs(top) > 1e-6) throw new AssertionError("did not reach top: " + top);
        clamped(overUp, 0.0, "top");
        // Fingers released: nothing may move afterwards (the reported jump).
        clamped(idle, 0.0, "post-release");
    }

    public static void main(String[] args) {
        launch(args);
        if (failure != null) throw new AssertionError(failure);
        if (!complete) throw new AssertionError("Pan scroll interaction incomplete");
        // Exactly-once contract: every injected InputEventPanGesture must reach
        // Java as exactly one ScrollEvent. The Godot side prints PAN_INJECTED;
        // the shell wrapper compares the two totals.
        System.out.println("PAN_EVENTS total=" + scrollEvents);
        System.out.println("PAN_SCROLL_PROBE_PASS");
    }
}
