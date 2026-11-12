import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.stage.WindowHelper;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.stage.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;

public class TransparentStageProbe {
    static Stage root,child;
    static long tick;
    static void frames(int n) { for(int i=0;i<n;i++) {tick=GodotBridge.awaitTick(tick,1000);if(tick<0)throw new AssertionError("Transparency host stopped");} }
    static void fx(Runnable action) throws Exception {
        var done=new CountDownLatch(1);var failure=new AtomicReference<Throwable>();
        Platform.runLater(()->{try{action.run();}catch(Throwable t){failure.set(t);}finally{done.countDown();}});
        if(!done.await(10,TimeUnit.SECONDS))throw new AssertionError("FX transparency timeout");
        if(failure.get()!=null)throw new AssertionError(failure.get());
    }
    static Scene scene() {
        var solid=new Rectangle(40,40,64,48);solid.setFill(Color.RED);
        var translucent=new Rectangle(140,40,40,48);translucent.setFill(Color.color(0,0,1,0.5));
        var pane=new Pane(solid,translucent);
        pane.setBackground(javafx.scene.layout.Background.EMPTY);
        return new Scene(pane,320,220,Color.TRANSPARENT);
    }
    static void phase(int value,Runnable action) throws Exception {
        fx(()->{root.setTitle("Transition");action.run();});frames(30);
        fx(()->root.setTitle("Transparent "+value+" "+WindowHelper.getPeer(child).getRawHandle()));frames(25);
    }
    public static void main(String[] args) throws Exception {
        var ready=new CountDownLatch(1);Platform.startup(ready::countDown);ready.await();
        fx(()->{Platform.setImplicitExit(false);root=new Stage(StageStyle.TRANSPARENT);root.setScene(scene());root.show();
            child=new Stage(StageStyle.TRANSPARENT);child.initOwner(root);child.setScene(scene());child.setX(root.getX()+350);child.show();});
        phase(0,()->{});
        fx(()->{root.setTitle("Transition");child.hide();});frames(20);
        phase(1,child::show);
        phase(2,()->root.getScene().setFill(Color.WHITE));
        phase(3,()->root.getScene().setFill(Color.TRANSPARENT));
        fx(()->{root.setTitle("Transition");child.close();root.close();});frames(30);
        Platform.exit();System.out.println("TRANSPARENT_STAGE_PROBE_PASS");
    }
}
