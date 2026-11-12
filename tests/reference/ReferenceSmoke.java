import javafx.application.Application;
import javafx.geometry.Insets;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.TextField;
import javafx.scene.effect.DropShadow;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
import javafx.scene.paint.Color;
import javafx.scene.paint.CycleMethod;
import javafx.scene.paint.LinearGradient;
import javafx.scene.paint.Stop;
import javafx.scene.shape.Circle;
import javafx.scene.shape.Rectangle;
import javafx.stage.Stage;

/** Same scene to run on the stock source SDK and the future Godot backend. */
public final class ReferenceSmoke extends Application {
    @Override public void start(Stage stage) {
        Label heading = new Label("JavaFX source baseline / 中文排版");
        heading.setStyle("-fx-font-size: 26px;");
        Label status = new Label("Clicks: 0");
        Button button = new Button("Click / 点击");
        button.setOnAction(event -> {
            int count = Integer.parseInt(status.getText().substring(8)) + 1;
            status.setText("Clicks: " + count);
            System.out.println("CLICK " + count + " FX=" + javafx.application.Platform.isFxApplicationThread());
        });
        TextField field = new TextField("English 与中文");
        field.setPrefColumnCount(20);
        field.textProperty().addListener((obs, old, value) -> System.out.println("TEXT " + value));
        Rectangle gradient = new Rectangle(240, 120,
                new LinearGradient(0, 0, 1, 1, true, CycleMethod.NO_CYCLE,
                        new Stop(0, Color.CORNFLOWERBLUE), new Stop(1, Color.MEDIUMPURPLE)));
        gradient.setArcWidth(24);
        gradient.setArcHeight(24);
        gradient.setEffect(new DropShadow(14, Color.color(0, 0, 0, 0.45)));
        Circle clipped = new Circle(65, Color.TOMATO);
        clipped.setOpacity(0.7);
        clipped.setClip(new Rectangle(-50, -40, 100, 80));
        clipped.setRotate(15);
        HBox shapes = new HBox(40, gradient, clipped);
        VBox root = new VBox(24, heading, new HBox(16, button, status), field, shapes);
        root.setPadding(new Insets(32));
        root.setStyle("-fx-background-color: #eef3fa; -fx-font-family: 'Microsoft YaHei'; -fx-font-size: 16px;");
        stage.setScene(new Scene(root, 720, 400));
        stage.setTitle("Godot-JFX M0 source baseline");
        stage.show();
        System.out.println("START FX=" + javafx.application.Platform.isFxApplicationThread()
                + " JavaFX=" + System.getProperty("javafx.runtime.version"));
        String snapshot = System.getProperty("reference.snapshot");
        if (snapshot != null) {
            javafx.animation.PauseTransition settle = new javafx.animation.PauseTransition(javafx.util.Duration.seconds(2));
            settle.setOnFinished(event -> {
                try {
                    var image = root.snapshot(null, null);
                    javax.imageio.ImageIO.write(javafx.embed.swing.SwingFXUtils.fromFXImage(image, null),
                            "png", new java.io.File(snapshot));
                    System.out.println("SNAPSHOT " + snapshot);
                    javafx.application.Platform.exit();
                } catch (Exception failure) {
                    failure.printStackTrace();
                    System.exit(1);
                }
            });
            settle.play();
        }
    }
    public static void main(String[] args) { launch(args); }
}
