package geometry;

import io.vproxy.vfx.ui.button.FusionButton;
import io.vproxy.vfx.ui.stage.VStage;
import io.vproxy.vfx.ui.wrapper.ThemeLabel;
import javafx.application.Application;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.Cursor;
import javafx.scene.AccessibleRole;
import javafx.scene.control.Tooltip;
import javafx.scene.input.KeyCode;
import javafx.scene.input.KeyEvent;
import javafx.scene.layout.*;
import javafx.scene.paint.Color;
import javafx.scene.shape.Circle;
import javafx.scene.shape.Rectangle;
import javafx.stage.Stage;

public final class TetrahedronDemo extends Application {
    private static final Color RUNNING = Color.web("#64c878");
    private static final Color PAUSED = Color.web("#edc64d");
    private GodotView view;

    @Override
    public void start(Stage stage) {
        var window = new VStage(stage);
        window.setTitle("彩色三棱锥");
        var page = window.getInitialScene();
        page.enableAutoContentWidthHeight();

        view = new GodotView();
        view.setMinSize(240, 180);
        view.setMaxSize(Double.MAX_VALUE, Double.MAX_VALUE);
        view.setCursor(Cursor.OPEN_HAND);
        view.setOnMousePressed(e -> view.setCursor(Cursor.CLOSED_HAND));
        view.setOnMouseReleased(e -> view.setCursor(Cursor.OPEN_HAND));
        view.loadScene("res://tetrahedron.tscn");

        var dot = new Circle(5, RUNNING);
        dot.setAccessibleRole(AccessibleRole.TEXT);
        dot.setAccessibleText("旋转中");
        var status = new Tooltip();
        status.textProperty().bind(dot.accessibleTextProperty());
        Tooltip.install(dot, status);

        var preview = new StackPane(view);
        preview.getStyleClass().add("preview");
        var clip = new Rectangle();
        clip.widthProperty().bind(preview.widthProperty());
        clip.heightProperty().bind(preview.heightProperty());
        clip.setArcWidth(22);
        clip.setArcHeight(22);
        preview.setClip(clip);
        VBox.setVgrow(preview, Priority.ALWAYS);

        var start = playbackButton("开始", "start", KeyCode.R);
        var pause = playbackButton("暂停", "pause", KeyCode.P);
        var hint = new ThemeLabel("按住左键拖动，旋转视角");
        hint.getStyleClass().add("hint");
        var controls = new HBox(12, dot, hint, spacer(), start, pause);
        controls.setAlignment(Pos.CENTER_LEFT);

        var root = new VBox(16, preview, controls);
        root.getStyleClass().add("workspace");
        root.setPadding(new Insets(10, 18, 16, 18));
        root.getStylesheets().add(getClass().getResource("studio.css").toExternalForm());
        var content = page.getContentPane();
        root.prefWidthProperty().bind(content.widthProperty());
        root.prefHeightProperty().bind(content.heightProperty());
        content.getChildren().add(root);
        // Both real and button-generated R/P presses travel through GodotView's input queue.
        view.addEventFilter(KeyEvent.KEY_PRESSED, e -> {
            if (e.getCode() == KeyCode.R || e.getCode() == KeyCode.P) {
                boolean running = e.getCode() == KeyCode.R;
                dot.setAccessibleText(running ? "旋转中" : "已暂停");
                dot.setFill(running ? RUNNING : PAUSED);
            }
        });
        stage.setWidth(860);
        stage.setHeight(580);
        stage.setMinWidth(540);
        stage.setMinHeight(380);
        window.show();
        view.requestFocus();
    }

    private void sendCommand(KeyCode key) {
        view.requestFocus();
        view.fireEvent(new KeyEvent(KeyEvent.KEY_PRESSED, "", "", key, false, false, false, false));
        view.fireEvent(new KeyEvent(KeyEvent.KEY_RELEASED, "", "", key, false, false, false, false));
    }

    private static Region spacer() {
        var spacer = new Region();
        HBox.setHgrow(spacer, Priority.ALWAYS);
        return spacer;
    }

    private FusionButton playbackButton(String text, String id, KeyCode command) {
        var button = new FusionButton(text);
        button.setPrefSize(88, 40);
        button.setId(id);
        button.setAccessibleRole(AccessibleRole.BUTTON);
        button.setAccessibleText(text);
        button.setFocusTraversable(true);
        button.setOnAction(e -> sendCommand(command));
        button.setOnKeyPressed(e -> {
            if (e.getCode() == KeyCode.SPACE || e.getCode() == KeyCode.ENTER) {
                sendCommand(command);
                e.consume();
            }
        });
        return button;
    }

    @Override
    public void stop() {
        view.close();
    }
}
