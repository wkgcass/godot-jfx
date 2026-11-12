import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Platform;
import javafx.scene.Group;
import javafx.scene.Scene;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.scene.control.Label;
import javafx.scene.control.Button;
import javafx.scene.effect.GaussianBlur;
import javafx.scene.effect.DropShadow;
import javafx.stage.Stage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.AtomicInteger;

public final class StageProbe {
    public static void main(String[] args) throws Exception {
        var ready = new CountDownLatch(1);
        var failure = new AtomicReference<Throwable>();
        var rectangle = new AtomicReference<Rectangle>();
        var window = new AtomicReference<Stage>();
        var actions = new AtomicInteger();
        var interaction = new CountDownLatch(2);
        Platform.startup(() -> {
            try {
                Platform.setImplicitExit(false);
                Rectangle a = new Rectangle(16,16,80,96); a.setFill(Color.color(.8,.2,.6));
                Rectangle b = new Rectangle(200,16,80,96); b.setFill(Color.LIME);
                Stage stage = new Stage();
                rectangle.set(a); window.set(stage);
                stage.setTitle("Godot JavaFX Stage");
                Label label = new Label("Godot JavaFX 中文");
                label.relocate(16,140);
                Button button = new Button("Click 测试");
                button.relocate(200,140);
                button.setOnAction(event -> {
                    if (!Platform.isFxApplicationThread()) { failure.set(new AssertionError("Button action on wrong thread")); return; }
                    int count = actions.incrementAndGet();
                    label.setText("Action " + count + " 中文");
                    stage.setTitle("Button action " + count);
                    interaction.countDown();
                });
                Rectangle blurred = new Rectangle(20,190,20,20);
                blurred.setFill(Color.RED); blurred.setEffect(new GaussianBlur(4));
                Rectangle shadowed = new Rectangle(120,190,30,20);
                shadowed.setFill(Color.BLUE);
                DropShadow shadow = new DropShadow(6,4,4,Color.BLACK);
                shadowed.setEffect(shadow);
                stage.setScene(new Scene(new Group(a,b,label,button,blurred,shadowed),400,240,Color.WHITE));
                stage.show();
            } catch (Throwable t) { failure.set(t); }
            finally { ready.countDown(); }
        });
        if (!ready.await(15, TimeUnit.SECONDS)) throw new AssertionError("Stage startup timed out");
        if (failure.get() != null) throw new AssertionError(failure.get());
        long tick = 0;
        for (int i = 0; i < 120; ++i) {
            final int frame = i;
            var updated = new CountDownLatch(1);
            Platform.runLater(() -> { rectangle.get().setX(frame % 2 == 0 ? 116 : 16); updated.countDown(); });
            if (!updated.await(5, TimeUnit.SECONDS)) throw new AssertionError("Scene update timed out");
            tick = GodotBridge.awaitTick(tick,1000);
            tick = GodotBridge.awaitTick(tick,1000);
            if (tick < 0) throw new AssertionError("Host stopped");
        }
        Platform.runLater(() -> window.get().setTitle("Stage dynamic complete"));
        if (!interaction.await(15,TimeUnit.SECONDS)) throw new AssertionError("Mouse/keyboard button actions missing: " + actions.get());
        if (failure.get() != null) throw new AssertionError(failure.get());
        for (int i = 0; i < 150; ++i) {
            tick = GodotBridge.awaitTick(tick,1000);
            if (tick < 0) throw new AssertionError("Host stopped before rendered interaction verification");
        }
        Platform.exit();
        System.out.println("STAGE_PROBE_PASS");
    }
}
