import javafx.application.*;
import javafx.scene.*;
import javafx.scene.layout.Background;
import javafx.scene.layout.BackgroundFill;
import javafx.scene.layout.CornerRadii;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Circle;
import javafx.scene.shape.Rectangle;
import javafx.stage.Stage;
import javafx.stage.StageStyle;

// Replicates the VFX stage corner: a transparent stage, a rounded-corner
// clipped content pane, and a transparent-fill resize circle (NW_RESIZE)
// floating above the clip at the bottom-right corner. The Godot-side test
// synthesizes hover and asserts the native cursor survives follow-up motion.
public final class ResizeCursorProbe extends Application {
    private static Throwable failure;
    private static boolean complete;
    @Override public void start(Stage stage) {
        try {
            stage.initStyle(StageStyle.TRANSPARENT);
            var root = new Pane();
            var content = new Pane();
            content.setLayoutX(0.5);
            content.setLayoutY(0.5);
            content.setPrefSize(399, 299);
            var clip = new Rectangle(399, 299);
            clip.setArcWidth(16);
            clip.setArcHeight(16);
            content.setClip(clip);
            content.setBackground(new Background(new BackgroundFill(Color.rgb(40, 44, 52), new CornerRadii(8), null)));
            var resize = new Circle(8);
            resize.setStrokeWidth(0);
            resize.setFill(Color.TRANSPARENT);
            resize.setCursor(Cursor.NW_RESIZE);
            resize.setLayoutX(400 - 8);
            resize.setLayoutY(300 - 8);
            root.getChildren().addAll(content, resize);
            var scene = new Scene(root, 400, 300, Color.TRANSPARENT);
            resize.hoverProperty().addListener((ob, old, now) -> System.out.println("RESIZE_HOVER " + now));
            root.setOnMouseClicked(event -> {
                complete = true;
                Platform.exit();
            });
            stage.setScene(scene);
            stage.setTitle("ResizeCursor ready");
            stage.show();
        } catch (Throwable error) { failure = error; Platform.exit(); }
    }
    public static void main(String[] args) {
        launch(args);
        if (failure != null) throw new AssertionError(failure);
        if (!complete) throw new AssertionError("Resize cursor interaction incomplete");
        System.out.println("RESIZE_CURSOR_PROBE_PASS");
    }
}
