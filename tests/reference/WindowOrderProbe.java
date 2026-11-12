import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class WindowOrderProbe {
    private static Stage main,a,b,child;
    private static long tick;
    private static void waitFrames(int count) {
        for(int i=0;i<count;++i) { tick=GodotBridge.awaitTick(tick,1000); if(tick<0) throw new AssertionError("Order host stopped"); }
    }
    private static void onFx(Runnable action) throws Exception {
        var done=new CountDownLatch(1); var failure=new AtomicReference<Throwable>();
        Platform.runLater(() -> { try { action.run(); } catch(Throwable t) { failure.set(t); } finally { done.countDown(); } });
        if(!done.await(5,TimeUnit.SECONDS)) throw new AssertionError("FX action timeout");
        if(failure.get()!=null) throw new AssertionError(failure.get());
    }
    private static Stage create(Stage owner,int x,int y,int width,int height,Color color) {
        Stage stage=new Stage(StageStyle.UNDECORATED); stage.initOwner(owner);
        stage.setScene(new Scene(new Pane(),width,height,color));
        stage.setX(main.getX()+x); stage.setY(main.getY()+y); stage.show(); return stage;
    }
    private static void phase(int index,Runnable action) throws Exception {
        onFx(() -> { main.setTitle("Transition"); action.run(); });
        waitFrames(45); onFx(() -> main.setTitle("Order "+index)); waitFrames(20);
    }
    public static void main(String[] args) throws Exception {
        var ready=new CountDownLatch(1);
        Platform.startup(() -> {
            Platform.setImplicitExit(false); main=new Stage(); main.setScene(new Scene(new Pane(),320,220,Color.RED)); main.show();
            a=create(main,40,40,140,100,Color.BLUE); b=create(main,80,60,140,100,Color.LIME); ready.countDown();
        });
        if(!ready.await(10,TimeUnit.SECONDS)) throw new AssertionError("Startup timeout");
        phase(0,() -> {});
        phase(1,() -> a.setAlwaysOnTop(true));
        phase(2,() -> b.toFront());
        phase(3,() -> a.toBack());
        phase(4,() -> { a.setAlwaysOnTop(false); a.toBack(); });
        phase(5,() -> a.toFront());
        phase(6,() -> child=create(a,100,80,60,50,Color.PURPLE));
        phase(7,() -> a.toFront());
        phase(8,() -> child.close());
        phase(9,() -> a.close());
        onFx(() -> { main.setTitle("Transition"); main.close(); }); waitFrames(60);
        Platform.exit(); System.out.println("WINDOW_ORDER_PROBE_PASS");
    }
}
