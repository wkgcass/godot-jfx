import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.StackPane;
import javafx.stage.Stage;

public class StartupProbe extends Application {
    public static void main(String[] args) { launch(args); }
    @Override public void start(Stage stage) throws Exception {
        Platform.setImplicitExit(false);
        Thread.sleep(1200);
        stage.setTitle("StartupProbe");
        StackPane pane = new StackPane();
        pane.setStyle("-fx-background-color: #e02030;");
        stage.setScene(new Scene(pane, 480, 320));
        stage.show();
        if ("1".equals(System.getenv("GODOT_JFX_STARTUP_CANCEL"))) {
            Thread.sleep(250);
            stage.hide();
            Thread.sleep(1600);
            stage.show();
        } else {
            Thread.sleep(1600);
        }
        Thread worker = new Thread(() -> {
            try {
                Thread.sleep(3200);
                Platform.runLater(() -> { stage.hide(); stage.show(); });
                Thread.sleep(1000);
                Platform.runLater(() -> {
                    Stage secondary = new Stage();
                    secondary.setTitle("StartupSecondary");
                    secondary.setScene(new Scene(new StackPane(), 200, 100));
                    secondary.show();
                });
                Thread.sleep(1000);
                Platform.runLater(Platform::exit);
            } catch (InterruptedException e) { throw new RuntimeException(e); }
        });
        worker.setDaemon(true);
        worker.start();
    }
}
