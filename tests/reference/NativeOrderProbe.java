import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.stage.WindowHelper;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.stage.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;

public class NativeOrderProbe {
    static Stage main,a,b,c,d;
    static long tick;
    static void frames(int count) {
        for(int i=0;i<count;i++){tick=GodotBridge.awaitTick(tick,1000);if(tick<0)throw new AssertionError("Order host stopped");}
    }
    static void fx(Runnable action) throws Exception {
        var done=new CountDownLatch(1);var error=new AtomicReference<Throwable>();
        Platform.runLater(()->{try{action.run();}catch(Throwable t){error.set(t);}finally{done.countDown();}});
        if(!done.await(10,TimeUnit.SECONDS))throw new AssertionError("FX order timeout");
        if(error.get()!=null)throw new AssertionError(error.get());
    }
    static Stage create(Color color) {
        return create(color,null);
    }
    static Stage create(Color color,Stage owner) {
        var stage=new Stage(StageStyle.UNDECORATED);stage.setScene(new Scene(new Pane(),240,160,color));
        if(owner!=null)stage.initOwner(owner);
        stage.setX(main.getX()+40);stage.setY(main.getY()+40);stage.show();return stage;
    }
    static void phase(int index,Runnable action) throws Exception {
        fx(()->{main.setTitle("Transition");action.run();});frames(30);
        fx(()->main.setTitle("NativeOrder "+index+" "+WindowHelper.getPeer(a).getRawHandle()+" "+WindowHelper.getPeer(b).getRawHandle()
                +(c==null?"":" "+WindowHelper.getPeer(c).getRawHandle()+" "+WindowHelper.getPeer(d).getRawHandle())));frames(20);
    }
    public static void main(String[] args) throws Exception {
        var ready=new CountDownLatch(1);
        Platform.startup(()->{Platform.setImplicitExit(false);main=new Stage();main.setScene(new Scene(new Pane(),320,220,Color.RED));main.show();a=create(Color.BLUE);b=create(Color.LIME);ready.countDown();});
        if(!ready.await(15,TimeUnit.SECONDS))throw new AssertionError("Startup timeout");
        phase(0,()->b.toFront());
        phase(1,()->{main.toFront();main.toBack();});
        phase(2,()->{a.toFront();a.toBack();});
        phase(3,()->a.toFront());
        phase(4,()->b.toFront());
        phase(5,()->b.toBack());
        phase(6,()->main.toFront());
        phase(7,()->{c=create(Color.YELLOW,a);d=create(Color.CYAN,c);});
        phase(8,()->a.toFront());
        phase(9,()->c.toBack());
        phase(10,()->a.toBack());
        phase(11,()->d.toBack());
        phase(12,()->b.toFront());
        fx(()->{main.setTitle("Transition");d.hide();});frames(20);
        phase(13,()->d.show());
        phase(14,()->c.toFront());
        fx(()->{main.setTitle("Transition");a.hide();});frames(30);
        phase(15,()->{a.show();c.show();d.show();});
        phase(16,()->a.toFront());
        fx(()->{main.setTitle("Transition");d.close();c.close();a.close();b.close();main.close();});frames(30);
        Platform.exit();System.out.println("NATIVE_ORDER_PROBE_PASS");
    }
}
