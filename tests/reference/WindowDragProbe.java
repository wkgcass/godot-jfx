import javafx.application.*;
import javafx.scene.*;
import javafx.scene.layout.Background;
import javafx.scene.layout.BackgroundFill;
import javafx.scene.layout.CornerRadii;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.stage.Screen;
import javafx.stage.Stage;
import javafx.stage.StageStyle;

// Replicates the VFX title-bar drag: a transparent stage whose top 28 px pane
// moves the window by the screen-space mouse delta (VFX DragHandler semantics).
// The Godot-side test synthesizes a fast upward drag and measures how many
// frames the native window trails each absolute mouse position.
public final class WindowDragProbe extends Application {
    private static Throwable failure;
    private static boolean complete;
    private double oldStageX, oldStageY, oldScreenX, oldScreenY;
    @Override public void start(Stage stage) {
        try {
            stage.initStyle(StageStyle.TRANSPARENT);
            var root = new Pane();
            var content = new Pane();
            content.setLayoutX(0.5);
            content.setLayoutY(0.5);
            content.setPrefSize(399, 299);
            content.setBackground(new Background(new BackgroundFill(Color.rgb(40, 44, 52), new CornerRadii(8), null)));
            var movingPane = new Pane();
            movingPane.setPrefSize(400, 28);
            movingPane.setBackground(new Background(new BackgroundFill(Color.rgb(60, 64, 72), CornerRadii.EMPTY, null)));
            root.getChildren().addAll(content, movingPane);
            movingPane.setOnMousePressed(event -> {
                oldStageX = stage.getX();
                oldStageY = stage.getY();
                oldScreenX = event.getScreenX();
                oldScreenY = event.getScreenY();
                System.out.println("DRAG_BASELINE " + oldStageX + "," + oldStageY);
            });
            movingPane.setOnMouseDragged(event -> {
                double x = oldStageX + (event.getScreenX() - oldScreenX);
                double y = oldStageY + (event.getScreenY() - oldScreenY);
                stage.setX(x);
                stage.setY(y);
            });
            root.setOnMouseClicked(event -> {
                complete = true;
                Platform.exit();
            });
            stage.setScene(new Scene(root, 400, 300, Color.TRANSPARENT));
            stage.setTitle("WindowDrag ready");
            // Park the stage away from the physical cursor instead of moving the
            // cursor: a stationary cursor inside the drag path would emit
            // button-less MOUSE_MOVED events as the window moves under it, ending
            // JavaFX's press-drag-release gesture. Reading the cursor position is
            // passive; only the stage is placed. The drag runs 240 px upward, so
            // the path extends 320 px above the stage top.
            var robot = com.sun.glass.ui.Application.GetApplication().createRobot();
            robot.create();
            double mx, my;
            try {
                mx = robot.getMouseX();
                my = robot.getMouseY();
            } finally {
                robot.destroy();
            }
            var vb = Screen.getPrimary().getVisualBounds();
            double stageX = mx < vb.getMinX() + vb.getWidth() / 2 ? vb.getMaxX() - 440 : vb.getMinX() + 40;
            double stageY = Math.min(vb.getMinY() + 400, vb.getMaxY() - 340);
            if (mx >= stageX - 20 && mx <= stageX + 420 && my >= stageY - 320 && my <= stageY + 320) {
                // Unusually narrow screen still overlapping: separate vertically,
                // putting the cursor below the drag path while keeping the 240 px
                // upward travel on screen.
                stageY = Math.max(vb.getMinY() + 260, Math.min(my - 340, vb.getMaxY() - 340));
            }
            stage.setX(stageX);
            stage.setY(stageY);
            stage.show();
        } catch (Throwable error) { failure = error; Platform.exit(); }
    }
    public static void main(String[] args) {
        launch(args);
        if (failure != null) throw new AssertionError(failure);
        if (!complete) throw new AssertionError("Window drag interaction incomplete");
        System.out.println("WINDOW_DRAG_PROBE_PASS");
    }
}
