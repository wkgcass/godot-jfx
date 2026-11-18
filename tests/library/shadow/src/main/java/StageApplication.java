import javafx.animation.PauseTransition;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Label;
import javafx.scene.layout.StackPane;
import javafx.scene.paint.Color;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import javafx.util.Duration;

public final class StageApplication extends Application {
    @Override public void start(Stage primary) {
        primary.initStyle(StageStyle.TRANSPARENT);
        primary.setTitle("Shadow Stage");
        primary.setScene(new Scene(new StackPane(new Label("JavaFX")), 300, 185, Color.TRANSPARENT));
        primary.show();
        Stage child = new Stage(StageStyle.UNDECORATED);
        child.initOwner(primary);
        child.setScene(new Scene(new StackPane(new Label("Child")), 120, 80));
        child.show();
        primary.setWidth(312);
        primary.setHeight(208);
        PauseTransition delay = new PauseTransition(Duration.seconds(1));
        delay.setOnFinished(event -> {
            if (primary.getWidth() == 312 && primary.getHeight() == 208 && primary.isShowing()
                    && child.isShowing() && child.getOwner() == primary && Platform.isFxApplicationThread()) {
                System.out.println("SHADOW_STAGE_PASS");
            }
            child.close();
            primary.close();
        });
        delay.play();
    }
}
