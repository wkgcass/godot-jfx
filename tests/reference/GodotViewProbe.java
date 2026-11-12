import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Platform;
import javafx.scene.Group;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.layout.GodotView;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.stage.Stage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class GodotViewProbe {
    public static void main(String[] args) throws Exception {
        var ready = new CountDownLatch(1);
        var action = new CountDownLatch(2);
        var actions = new java.util.concurrent.atomic.AtomicInteger();
        var failure = new AtomicReference<Throwable>();
        var cleanup = new AtomicReference<Runnable>();
        Platform.startup(() -> {
            try {
                GodotView view = new GodotView(); view.setPrefSize(96,64); view.relocate(20,20);
                view.loadScene("res://embedded_scene.tscn");
                GodotView second = new GodotView(); second.setPrefSize(96,64);
                second.loadScene("res://embedded_scene.tscn");
                Group clipped = new Group(second); clipped.setTranslateX(200); clipped.setTranslateY(20);
                clipped.setClip(new Rectangle(0,0,48,64)); clipped.setOpacity(.5);
                Label label = new Label("GodotView 中文"); label.relocate(20,140);
                Button button = new Button("Resize / 缩放"); button.relocate(200,140);
                Pane root = new Pane(view,clipped,label,button);
                root.setStyle("-fx-background-color: white;");
                boolean transformed = "1".equals(System.getenv("GODOT_JFX_TEST_VIEW_TRANSFORM"));
                if (transformed) root.getTransforms().add(new javafx.scene.transform.Affine(.8,-.15,50,.2,.9,10));
                Stage stage = new Stage(); stage.setScene(new Scene(root,400,300,Color.WHITE));
                button.setOnAction(event -> { int count = actions.incrementAndGet(); view.setPrefSize(144,96); label.setText("Resized "+count+" 中文"); stage.setTitle(count == 1 ? "GodotView resized" : "GodotView touched"); action.countDown(); });
                cleanup.set(() -> { view.close(); root.getChildren().clear(); });
                stage.setTitle("GodotView ready"); stage.show();
            } catch (Throwable t) { failure.set(t); }
            finally { ready.countDown(); }
        });
        if (!ready.await(15,TimeUnit.SECONDS) || failure.get() != null) throw new AssertionError("GodotView startup failed",failure.get());
        if (!action.await(20,TimeUnit.SECONDS)) throw new AssertionError("GodotView resize action missing");
        long tick = 0;
        for (int i = 0; i < 120; ++i) tick = GodotBridge.awaitTick(tick,1000);
        if (actions.get() != 2) throw new AssertionError("Mouse/touch Button action count differs: "+actions.get());
        Platform.runLater(cleanup.get());
        for (int i = 0; i < 80; ++i) tick = GodotBridge.awaitTick(tick,1000);
        Platform.exit();
        System.out.println("GODOT_VIEW_PROBE_PASS");
    }
}
