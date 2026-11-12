import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.stage.Stage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/** Standard Stage creation/rendering/lifecycle; root button acknowledges GPU checks. */
public final class NativeStageProbe {
    private static Stage root, child;
    private static final AtomicInteger verified = new AtomicInteger();
    private static void fx(Runnable action) throws Exception {
        var done = new CountDownLatch(1); var failure = new AtomicReference<Throwable>();
        Platform.runLater(() -> { try { action.run(); } catch(Throwable t) { failure.set(t); } finally { done.countDown(); } });
        if (!done.await(5,TimeUnit.SECONDS)) throw new AssertionError("FX action timeout");
        if (failure.get()!=null) throw new AssertionError(failure.get());
    }
    private static void verify(int step) throws Exception {
        fx(() -> root.setTitle("Native Stage "+step));
        long deadline=System.nanoTime()+10_000_000_000L, tick=0;
        while(verified.get()<=step) {
            tick=GodotBridge.awaitTick(tick,100);
            if(tick<0 || System.nanoTime()>deadline) throw new AssertionError("Native Stage verification timeout "+step);
        }
    }
    public static void main(String[] args) throws Exception {
        var ready=new CountDownLatch(1);
        Platform.startup(() -> { Platform.setImplicitExit(false); ready.countDown(); });
        if(!ready.await(5,TimeUnit.SECONDS)) throw new AssertionError("FX startup timeout");
        fx(() -> {
            root=new Stage();
            Button next=new Button("Next"); next.resizeRelocate(10,10,80,30); next.setPrefSize(80,30);
            next.setOnAction(event -> verified.incrementAndGet());
            Pane rootPane=new Pane(next); rootPane.setStyle("-fx-background-color: transparent;");
            root.setScene(new Scene(rootPane,320,180,Color.RED)); root.setX(30); root.setY(60); root.show();
            child=new Stage(); child.initOwner(root); child.setTitle("独立 Stage");
            Label label=new Label("Native JavaFX Stage"); label.relocate(10,10);
            Pane childPane=new Pane(label); childPane.setStyle("-fx-background-color: transparent;");
            child.setScene(new Scene(childPane,320,180,Color.BLUE));
            child.setX(450); child.setY(100); child.show();
        });
        verify(0);
        fx(() -> { child.getScene().setFill(Color.LIME); child.setWidth(400); child.setHeight(240); child.setX(470); child.setY(120); });
        verify(1);
        fx(() -> child.hide()); verify(2);
        fx(() -> child.show()); verify(3);
        fx(() -> child.setFullScreen(true)); verify(4);
        fx(() -> child.setFullScreen(false)); verify(5);
        fx(() -> child.setFullScreen(true)); verify(6);
        fx(() -> { if(child.isFullScreen()) throw new AssertionError("Escape did not exit fullscreen"); }); verify(7);
        fx(() -> child.setMaximized(true)); verify(8);
        fx(() -> child.setFullScreen(true)); verify(9);
        fx(() -> child.setFullScreen(false)); verify(10);
        fx(() -> {
            if(!child.isMaximized()) throw new AssertionError("Fullscreen lost maximized state");
            child.setMaximized(false);
        }); verify(11);
        fx(() -> child.close()); verify(12);
        fx(() -> root.close()); Platform.exit();
        System.out.println("NATIVE_STAGE_PROBE_PASS");
    }
}
