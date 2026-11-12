import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.TextField;
import javafx.scene.layout.Pane;
import javafx.scene.input.MouseEvent;
import javafx.stage.Stage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class NativeStageInputProbe {
    private static Stage root,child;
    private static int rootActions,childActions,scrolls,closes;
    private static boolean cancelRequested;
    private static final CountDownLatch done=new CountDownLatch(1);
    private static final AtomicReference<Throwable> failure=new AtomicReference<>();
    private static void state(int value) { root.setTitle("Native input "+value); }
    private static void check(boolean value,String text) { if(!value) { failure.set(new AssertionError(text)); done.countDown(); } }
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> {
            Platform.setImplicitExit(false);
            root=new Stage(); child=new Stage(); child.initOwner(root);
            Button a=new Button("Root"); a.setPrefSize(100,40); a.relocate(10,10);
            Button b=new Button("Child"); b.setPrefSize(100,40); b.relocate(10,10);
            TextField text=new TextField(); text.setPrefSize(180,30); text.relocate(10,70);
            a.setOnAction(event -> {
                ++rootActions;
                if(rootActions==1) { check(childActions==1,"Child click reached root"); child.requestFocus(); text.requestFocus(); state(2); }
                else { check(rootActions==2&&childActions==2&&scrolls==1&&closes==2&&text.getText().equals("a")&&!child.isShowing(),"Final input counts differ"); done.countDown(); }
            });
            b.setOnAction(event -> {
                ++childActions;
                if(childActions==1) { check(rootActions==0,"Initial root action occurred"); root.requestFocus(); state(1); }
                else { check(childActions==2&&rootActions==1,"Native touch isolation differs: child="+childActions+" root="+rootActions); state(5); }
            });
            b.addEventHandler(MouseEvent.MOUSE_PRESSED,event -> {
                if(scrolls==1&&!cancelRequested) {
                    cancelRequested=true;
                    root.requestFocus(); state(40);
                }
            });
            text.textProperty().addListener((observable,old,value) -> {
                if(value.equals("a")) {
                    check(child.isFocused()&&!root.isFocused(),"Native focus did not reach the child Stage");
                    state(3);
                }
            });
            Scene scene=new Scene(new Pane(b,text),320,180);
            scene.setOnScroll(event -> {
                ++scrolls; check(event.getDeltaY()>0,"Wheel direction differs");
                check(Math.abs(event.getSceneX()-150)<1 && Math.abs(event.getSceneY()-120)<1,"Wheel logical coordinates differ");
                check(Math.abs(event.getScreenX()-child.getX()-150)<1 && Math.abs(event.getScreenY()-child.getY()-120)<1,"Wheel screen coordinates differ");
                state(4);
            });
            scene.setOnTouchPressed(event -> {
                var point=event.getTouchPoint();
                check(Math.abs(point.getSceneX()-40)<1 && Math.abs(point.getSceneY()-30)<1,"Touch logical coordinates differ");
                check(Math.abs(point.getScreenX()-child.getX()-40)<1 && Math.abs(point.getScreenY()-child.getY()-30)<1,"Touch screen coordinates differ");
            });
            child.setOnCloseRequest(event -> { ++closes; if(closes==1) { event.consume(); state(6); } else state(7); });
            root.setOnCloseRequest(event -> { failure.set(new AssertionError("Child close reached root")); event.consume(); done.countDown(); });
            root.setScene(new Scene(new Pane(a),320,180)); root.setX(30); root.setY(60); root.show();
            child.setScene(scene); child.setX(30); child.setY(60); child.show(); state(0);
        });
        if(!done.await(25,TimeUnit.SECONDS)) throw new AssertionError("Native input timeout");
        if(failure.get()!=null) throw new AssertionError(failure.get());
        var closed=new CountDownLatch(1); Platform.runLater(() -> { root.close(); closed.countDown(); });
        if(!closed.await(5,TimeUnit.SECONDS)) throw new AssertionError("Root close timeout");
        Platform.exit(); System.out.println("NATIVE_STAGE_INPUT_PROBE_PASS");
    }
}
