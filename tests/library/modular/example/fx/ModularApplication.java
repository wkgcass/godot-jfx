package example.fx;

import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Label;
import javafx.stage.Stage;

public class ModularApplication extends Application {
    @Override public void start(Stage stage) {
        stage.setScene(new Scene(new Label("Module-path consumer"), 180, 100));
        stage.show();
        Platform.runLater(stage::close);
    }

    @Override public void stop() {
        System.out.println("APPLICATION_MODULE_PASS " + getClass().getModule().getName());
    }
}
