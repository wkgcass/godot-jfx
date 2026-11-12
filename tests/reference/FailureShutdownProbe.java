import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Label;
import javafx.scene.layout.Pane;
import javafx.stage.Stage;
import com.sun.javafx.tk.godot.GodotBridge;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Main fails while a real native Stage is inside showAndWait. */
public final class FailureShutdownProbe {
    public static void main(String[] args) throws Exception {
        var nested=new CountDownLatch(1);
        Platform.startup(() -> {
            Platform.setImplicitExit(false);
            var root=new Stage(); root.setScene(new Scene(new Pane(new Label("Failure owner")),320,180)); root.show();
            Platform.runLater(() -> {
                var dialog=new Stage(); dialog.initOwner(root);
                dialog.setScene(new Scene(new Pane(new Label("Failure inside showAndWait")),300,160));
                Platform.runLater(() -> {
                    var inner=new Stage(); inner.initOwner(dialog);
                    inner.setScene(new Scene(new Pane(new Label("Nested failure window")),280,140));
                    Platform.runLater(nested::countDown);
                    inner.showAndWait();
                    System.out.println("FAILURE_INNER_LOOP_RETURNED");
                });
                dialog.showAndWait();
                System.out.println("FAILURE_NESTED_LOOP_RETURNED");
            });
        });
        if(!nested.await(10,TimeUnit.SECONDS)) throw new AssertionError("Nested setup timed out");
        long tick=0;
        for(int i=0;i<20;++i) { tick=GodotBridge.awaitTick(tick,1000); if(tick<0) throw new AssertionError("Host stopped before injection"); }
        throw new IllegalStateException("INJECTED_STAGE_FAILURE");
    }
}
