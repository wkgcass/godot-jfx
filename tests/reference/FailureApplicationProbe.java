import javafx.application.Application;
import javafx.application.Platform;
import javafx.animation.PauseTransition;
import javafx.util.Duration;
import javafx.scene.Scene;
import javafx.scene.control.Label;
import javafx.scene.layout.Pane;
import javafx.stage.Stage;

/** Mirrors Demo observer failure: exit on FX while nested, then report after launch returns. */
public final class FailureApplicationProbe extends Application {
    @Override public void start(Stage root) {
        root.setScene(new Scene(new Pane(new Label("Application failure owner")),320,180)); root.show();
        Platform.runLater(() -> {
            var outer=new Stage(); outer.initOwner(root);
            outer.setScene(new Scene(new Pane(new Label("Outer showAndWait")),300,160));
            Platform.runLater(() -> {
                var inner=new Stage(); inner.initOwner(outer);
                inner.setScene(new Scene(new Pane(new Label("Inner showAndWait")),280,140));
                var quit=new PauseTransition(Duration.millis(500));
                quit.setOnFinished(event -> Platform.exit()); quit.play();
                inner.showAndWait();
                System.out.println("FAILURE_INNER_LOOP_RETURNED");
            });
            outer.showAndWait();
            System.out.println("FAILURE_NESTED_LOOP_RETURNED");
        });
    }
    public static void main(String[] args) {
        Application.launch(FailureApplicationProbe.class,args);
        throw new IllegalStateException("INJECTED_STAGE_FAILURE");
    }
}
