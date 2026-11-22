package room;

import io.vproxy.vfx.ui.button.FusionButton;
import io.vproxy.vfx.ui.wrapper.ThemeLabel;
import javafx.application.Application;
import javafx.application.GodotRuntime;
import javafx.scene.Group;
import javafx.scene.Scene;
import javafx.scene.control.Label;
import javafx.scene.layout.Pane;
import javafx.scene.transform.Scale;
import javafx.stage.Stage;

public final class WallControls extends Application {
    private boolean lights = true;
    private boolean cooling = false;
    private int temperature = 23;
    private final Label lightStatus = new ThemeLabel();
    private final Label climateStatus = new ThemeLabel();
    private final Label setpoint = new ThemeLabel();
    private final FusionButton lightPower = new FusionButton();
    private final FusionButton climatePower = new FusionButton();
    private final FusionButton cooler = new FusionButton("−");
    private final FusionButton warmer = new FusionButton("+");

    @Override public void start(Stage stage) {
        Pane root = new Pane();
        Scene scene = new Scene(root, 1100, 720);
        stage.setScene(scene);
        stage.setTitle("栖居 · 房间控制");
        Pane light = panel("VFX   /   LIGHTING", "室内照明");
        Pane climate = panel("VFX   /   CLIMATE", "空调温控");
        climate.setLayoutX(400);
        status(light, lightStatus, 30, 114, 30);
        status(climate, climateStatus, 30, 115, 18);
        status(climate, setpoint, 218, 96, 40);
        button(light, lightPower, 30, 332, () -> lights = !lights);
        button(climate, climatePower, 30, 160, () -> cooling = !cooling);
        button(climate, cooler, 206, 70, () -> temperature = Math.max(16, temperature - 1));
        button(climate, warmer, 292, 70, () -> temperature = Math.min(30, temperature + 1));
        // Keep a fixed logical atlas. Glass maps the reprojected window pixels back through this scale.
        Group atlas = new Group(light, climate);
        atlas.setManaged(false);
        Scale scale = new Scale();
        scale.xProperty().bind(scene.widthProperty().divide(800));
        scale.yProperty().bind(scene.heightProperty().divide(260));
        atlas.getTransforms().add(scale);
        root.getChildren().add(atlas);

        refresh();
        stage.show();
    }

    private static Pane panel(String index, String title) {
        Pane panel = new Pane();
        panel.setPrefSize(400, 260);
        panel.setStyle("-fx-background-color: #242d30;");
        Label header = new ThemeLabel(index);
        Label heading = new ThemeLabel(title);
        status(panel, header, 30, 18, 15);
        header.setStyle(header.getStyle() + "-fx-text-fill: #abc7be;");
        status(panel, heading, 30, 45, 34);
        var rule = new javafx.scene.shape.Rectangle(30, 100, 332, 1);
        rule.setFill(javafx.scene.paint.Color.web("#53615f"));
        panel.getChildren().add(rule);
        return panel;
    }

    private static void status(Pane panel, Label label, int x, int y, int size) {
        label.relocate(x, y);
        label.setStyle("-fx-text-fill: #f2f4ec; -fx-font-size: " + size + "px;");
        panel.getChildren().add(label);
    }

    private void button(Pane panel, FusionButton button, int x, int width, Runnable change) {
        button.setPrefSize(width, 58);
        button.getTextNode().setStyle("-fx-font-size: 22px;");
        button.relocate(x, 180);
        button.setOnAction(event -> { change.run(); refresh(); });
        panel.getChildren().add(button);
    }

    private void refresh() {
        lightStatus.setText(lights ? "已点亮" : "已熄灭");
        climateStatus.setText(cooling ? "制冷中" : "待机");
        setpoint.setText(temperature + " °C");
        lightPower.setText(lights ? "关闭照明" : "开启照明");
        climatePower.setText(cooling ? "关闭空调" : "开启空调");
        cooler.setDisable(!cooling || temperature == 16);
        warmer.setDisable(!cooling || temperature == 30);
        // The low two bits are the switches. The remaining bits hold the setpoint offset.
        int state = ((temperature - 16) << 2) | (cooling ? 2 : 0) | (lights ? 1 : 0);
        GodotRuntime.postSceneMessage("room.devices", state);
    }
}
