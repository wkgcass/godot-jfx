import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.control.Button;
import javafx.scene.paint.Color;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class LogicalWindowProbe {
    private static Stage main, child;
    private static long tick;
    private static final CountDownLatch actions = new CountDownLatch(3);
    private static int childActions, mainActions;
    private static void waitFrames(int count) {
        for (int i=0;i<count;++i) { tick=GodotBridge.awaitTick(tick,1000); if(tick<0) throw new AssertionError("Logical host stopped"); }
    }
    private static void onFx(Runnable action) throws Exception {
        var done=new CountDownLatch(1); var failure=new AtomicReference<Throwable>();
        Platform.runLater(() -> { try { action.run(); } catch(Throwable t) { failure.set(t); } finally { done.countDown(); } });
        if(!done.await(5,TimeUnit.SECONDS)) throw new AssertionError("FX action timeout");
        if(failure.get()!=null) throw new AssertionError(failure.get());
    }
    public static void main(String[] args) throws Exception {
        var ready=new CountDownLatch(1);
        Platform.startup(() -> {
            Platform.setImplicitExit(false);
            main=new Stage();
            Button first=new Button("Main"); first.resizeRelocate(10,10,80,30); first.setPrefSize(80,30);
            first.setOnAction(event -> { ++mainActions; main.setTitle("Main action "+mainActions); actions.countDown(); });
            Pane mainRoot=new Pane(first); mainRoot.setStyle("-fx-background-color: transparent;");
            main.setScene(new Scene(mainRoot,240,160,Color.RED)); main.show();
            child=new Stage(StageStyle.UNDECORATED); child.initOwner(main);
            Button second=new Button("Child"); second.resizeRelocate(10,10,80,30); second.setPrefSize(80,30);
            second.setOnAction(event -> { ++childActions; main.setTitle("Child action "+childActions); actions.countDown(); });
            Pane childRoot=new Pane(second); childRoot.setStyle("-fx-background-color: transparent;");
            child.setScene(new Scene(childRoot,120,80,Color.BLUE));
            child.setX(main.getX()+100); child.setY(main.getY()+50); child.show();
            System.out.println("LOGICAL_BOUNDS main="+main.getX()+","+main.getY()+" child="+child.getX()+","+child.getY()+" size="+child.getWidth()+","+child.getHeight());
            main.setTitle("Logical ready"); ready.countDown();
        });
        if(!ready.await(10,TimeUnit.SECONDS)) throw new AssertionError("Startup timeout");
        if(!actions.await(20,TimeUnit.SECONDS) || childActions!=2 || mainActions!=1) throw new AssertionError("Logical action routing differs: "+childActions+"/"+mainActions);
        onFx(() -> { main.setTitle("Transition"); child.setX(main.getX()+30); child.setY(main.getY()+60); child.setOpacity(.5); child.toFront(); });
        waitFrames(60); onFx(() -> main.setTitle("Logical moved")); waitFrames(30);
        onFx(() -> { main.setTitle("Transition"); child.hide(); });
        waitFrames(60); onFx(() -> main.setTitle("Logical hidden")); waitFrames(30);
        onFx(() -> { main.setTitle("Transition"); child.show(); }); waitFrames(60);
        onFx(() -> {
            main.setTitle("Logical restored");
            for (var window : com.sun.glass.ui.Window.getWindows()) {
                var lifecycle=com.sun.javafx.tk.godot.GodotWindowLifecycle.get(window.getNativeWindow());
                System.out.println("LOGICAL_RESTORED id="+window.getNativeWindow()+" primary="+lifecycle.isPrimary()+" state="+lifecycle.snapshot()+" bounds="+window.getX()+","+window.getY()+","+window.getWidth()+","+window.getHeight());
            }
        }); waitFrames(30);
        onFx(() -> { main.setTitle("Transition"); main.close(); }); waitFrames(60);
        Platform.exit(); System.out.println("LOGICAL_WINDOW_PROBE_PASS");
    }
}
