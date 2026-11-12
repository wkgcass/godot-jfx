import javafx.application.*;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.stage.*;
import com.sun.javafx.tk.Toolkit;
import com.sun.javafx.tk.RenderJob;
import com.sun.javafx.stage.WindowHelper;

public final class StageChurnProbe extends Application {
    private static Throwable failure;
    private static boolean complete;
    private int cycle;
    private static final int CYCLES=Integer.parseInt(System.getenv().getOrDefault("GODOT_JFX_CHURN_CYCLES","36"));
    private final java.util.List<java.lang.ref.WeakReference<Stage>> closedCandidates=new java.util.ArrayList<>();
    private Stage root;
    private void publish(String title) {
        Toolkit.getToolkit().addRenderJob(new RenderJob(()->Platform.runLater(()->root.setTitle(title))));
    }
    private void guard(Runnable action) {
        try {action.run();} catch(Throwable error) {failure=error;Platform.exit();}
    }
    @Override public void start(Stage primary) {
        root=primary;
        Button next=new Button("Next");next.resizeRelocate(10,10,90,30);next.setPrefSize(90,30);
        root.setScene(new Scene(new Pane(next),320,180));root.show();
        next.setOnAction(e->guard(()->{
            if(cycle==CYCLES) {complete=true;Platform.exit();return;}
            Stage child=new Stage(StageStyle.UNDECORATED);child.initOwner(root);
            closedCandidates.add(new java.lang.ref.WeakReference<>(child));
            int w=200+(cycle%3)*40,h=120+(cycle%3)*20;
            Button close=new Button("Close");close.resizeRelocate(10,10,90,30);close.setPrefSize(90,30);
            Pane pane=new Pane(close);pane.setStyle("-fx-background-color: transparent;");
            child.setScene(new Scene(pane,w,h,cycle%2==0?Color.RED:Color.BLUE));
            close.setOnAction(event->guard(child::close));
            child.setOnHidden(event->guard(()->{
                cycle++;
                long used=Runtime.getRuntime().totalMemory()-Runtime.getRuntime().freeMemory();
                long collections=java.lang.management.ManagementFactory.getGarbageCollectorMXBeans().stream().mapToLong(gc->Math.max(0,gc.getCollectionCount())).sum();
                long collected=closedCandidates.stream().filter(ref->ref.get()==null).count();
                System.out.println("STAGE_CHURN_JAVA cycle="+cycle+" heap_used="+used+" gc_count="+collections+" collected_stages="+collected);
                root.requestFocus();publish("StageChurn closed "+cycle);
            }));
            child.show();publish("StageChurn open "+cycle+" "+WindowHelper.getPeer(child).getRawHandle());
        }));
        publish("StageChurn closed 0");
    }
    public static void main(String[] args) {
        launch(args);
        if(failure!=null) throw new AssertionError(failure);
        if(!complete) throw new AssertionError("Stage churn incomplete");
        System.out.println("STAGE_CHURN_PROBE_PASS cycles="+CYCLES+" forced_gc=false");
    }
}
