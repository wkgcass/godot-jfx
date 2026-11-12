import javafx.application.*;
import javafx.scene.Scene;
import javafx.scene.control.ScrollPane;
import javafx.scene.input.ScrollEvent;
import javafx.scene.layout.VBox;
import javafx.scene.shape.Rectangle;
import javafx.stage.Stage;

// Wheel-scroll contract probe. Native Win Glass reports the system wheel
// settings per event and uses 40px multipliers (ViewContainer.cpp), so one
// notch yields ScrollEvent deltaY = scrollY * round(40 * lines / 3) with
// lines = SPI_GETWHEELSCROLLLINES (or 40px page units when lines = -1). The
// Godot side injects three one-notch WHEEL_DOWN events; this probe verifies
// each ScrollEvent matches the native formula.
public final class ScrollWheelProbe extends Application {
    private static Throwable failure;
    private static boolean complete;
    private final java.util.List<Double> deltas = new java.util.ArrayList<>();

    @Override public void start(Stage stage) {
        try {
            var content = new VBox();
            for (int i = 0; i < 40; ++i) content.getChildren().add(new Rectangle(180, 48, javafx.scene.paint.Color.hsb(i * 9, 0.4, 0.85)));
            var scroll = new ScrollPane(content);
            scroll.setPrefSize(300, 300);
            scroll.addEventFilter(ScrollEvent.SCROLL, e -> {
                double expected;
                if (e.getTextDeltaYUnits() == ScrollEvent.VerticalTextScrollUnits.PAGES) {
                    expected = -40.0; // page-scroll setting: multiplier stays 40
                } else {
                    double lines = -e.getTextDeltaY(); // WHEEL_DOWN: scrollY = -1, so textDeltaY = -lines
                    expected = -Math.round(40.0 * lines / 3.0);
                }
                System.out.println("SCROLL_EVENT deltaY=" + e.getDeltaY() + " textDeltaY=" + e.getTextDeltaY()
                        + " units=" + e.getTextDeltaYUnits() + " expected=" + expected);
                if (e.getDeltaY() != expected) {
                    failure = new AssertionError("Scroll delta " + e.getDeltaY() + " != native-formula " + expected);
                    Platform.exit();
                    return;
                }
                deltas.add(e.getDeltaY());
                if (deltas.size() == 3) {
                    // Filters run before the skin consumes this third event.
                    // Observe after dispatch, including the third notch, and
                    // respect the user's wheel setting (including zero lines).
                    Platform.runLater(() -> {
                        try {
                            double extent = Math.max(0, content.getHeight() - scroll.getViewportBounds().getHeight());
                            double expectedMoved = Math.min(extent, -deltas.stream().mapToDouble(Double::doubleValue).sum());
                            double moved = scroll.getVvalue() * extent;
                            System.out.println("SCROLL_RESULT events=" + deltas.size() + " pixels=" + moved + " expected=" + expectedMoved);
                            if (deltas.size() != 3 || !Double.isFinite(moved) || Math.abs(moved - expectedMoved) > 0.01)
                                throw new AssertionError("ScrollPane moved " + moved + " != three-notch expected " + expectedMoved);
                            complete = true;
                        } catch (Throwable error) { failure = error; }
                        finally { Platform.exit(); }
                    });
                }
            });
            stage.setScene(new Scene(scroll, 300, 300));
            stage.setTitle("ScrollWheel ready");
            stage.show();
        } catch (Throwable error) { failure = error; Platform.exit(); }
    }

    public static void main(String[] args) {
        launch(args);
        if (failure != null) throw new AssertionError(failure);
        if (!complete) throw new AssertionError("Scroll wheel interaction incomplete");
        System.out.println("SCROLL_WHEEL_PROBE_PASS");
    }
}
