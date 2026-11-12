import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.stage.Stage;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

public final class RenderScaleProbe {
    private static Stage root,child;
    private static final AtomicInteger verified=new AtomicInteger();
    private static final AtomicReference<Throwable> inputFailure=new AtomicReference<>();
    private static void fx(Runnable action) throws Exception {
        var done=new CountDownLatch(1); var failure=new AtomicReference<Throwable>();
        Platform.runLater(()->{try{action.run();}catch(Throwable error){failure.set(error);}finally{done.countDown();}});
        if(!done.await(10,TimeUnit.SECONDS)) throw new AssertionError("FX timeout");
        if(failure.get()!=null) throw new AssertionError(failure.get());
    }
    private static Scene scene(int width,int height) {
        var red=new Rectangle(20,30,20,20); red.setFill(Color.RED);
        var green=new Rectangle(80,60,30,20); green.setFill(Color.LIME);
        var blue=new Rectangle(width-12,height-12,8,8); blue.setFill(Color.BLUE);
        var pane=new Pane(red,green,blue);
        pane.setOnMouseClicked(event->{
            if(Math.abs(event.getSceneX()-30)>1 || Math.abs(event.getSceneY()-40)>1)
                inputFailure.set(new AssertionError("Scaled mouse coordinates: "+event.getSceneX()+","+event.getSceneY()));
            var window=pane.getScene().getWindow();
            if(Math.abs(event.getScreenX()-window.getX()-30)>1 || Math.abs(event.getScreenY()-window.getY()-40)>1)
                inputFailure.set(new AssertionError("Scaled screen coordinates: "+event.getScreenX()+","+event.getScreenY()+" window "+window.getX()+","+window.getY()));
            if(Math.abs(pane.getScene().getWidth()-width)>.01 || Math.abs(pane.getScene().getHeight()-height)>.01)
                inputFailure.set(new AssertionError("Logical Scene size changed with render scale"));
            verified.incrementAndGet();
        });
        return new Scene(pane,width,height,Color.SILVER);
    }
    public static void main(String[] args) throws Exception {
        var ready=new CountDownLatch(1);
        Platform.startup(()->{Platform.setImplicitExit(false);ready.countDown();});
        if(!ready.await(10,TimeUnit.SECONDS)) throw new AssertionError("Startup timeout");
        try {
            fx(()->{
                root=new Stage(); root.setForceIntegerRenderScale(false); root.setScene(scene(320,240)); root.show();
                child=new Stage(); child.initOwner(root); child.setForceIntegerRenderScale(false); child.setScene(scene(288,192)); child.setX(400); child.setY(100); child.show();
                double expected=GodotBridge.screenInfo()[9]/96.0;
                if(root.getOutputScaleX()!=expected || child.getOutputScaleX()!=expected)
                    throw new AssertionError("System output scale: "+root.getOutputScaleX()+","+child.getOutputScaleX()+" expected "+expected);
                System.out.println("SYSTEM_OUTPUT_SCALE "+expected);
            });
            double[][] scales={{1,1,1,1},{2,2,1,1},{2,2,1.5,2},{.75,1.25,1.5,2},{1,1,2,.75},{1,1,1,1}};
            for(int step=0;step<scales.length;step++) {
                final int phase=step; final double[] s=scales[step];
                fx(()->{
                    root.setRenderScaleX(s[0]); root.setRenderScaleY(s[1]); child.setRenderScaleX(s[2]); child.setRenderScaleY(s[3]);
                    if(root.getRenderScaleX()!=s[0] || root.getRenderScaleY()!=s[1] || child.getRenderScaleX()!=s[2] || child.getRenderScaleY()!=s[3]) throw new AssertionError("Render scale properties");
                    root.setTitle("RenderScale "+phase);
                });
                long deadline=System.nanoTime()+15_000_000_000L,tick=0;
                while(verified.get()<=step) {
                    tick=GodotBridge.awaitTick(tick,100);
                    if(tick<0 || System.nanoTime()>deadline) throw new AssertionError("Scale verification timeout "+step);
                }
                if(inputFailure.get()!=null) throw new AssertionError(inputFailure.get());
            }
            fx(()->{child.close();root.close();});
            System.out.println("RENDER_SCALE_PROBE_PASS");
        } finally {Platform.exit();}
    }
}

