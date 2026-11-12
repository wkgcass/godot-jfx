import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.layout.Pane;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import javafx.stage.Modality;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class InputCancelProbe {
    private static Stage main;
    private static int cycle=1, actions, drags;
    private static boolean cancelScheduled, canceled;
    private static final CountDownLatch done=new CountDownLatch(1);
    private static final AtomicReference<Throwable> failure=new AtomicReference<>();
    private static void check(boolean value,String text) { if(!value) throw new AssertionError(text); }
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> {
            try {
                Platform.setImplicitExit(false); main=new Stage();
                Button target=new Button("Hold / release"); target.setPrefSize(120,40); target.relocate(20,20);
                target.setOnMouseDragged(event -> {
                    ++drags;
                    System.out.println("CANCEL_UNEXPECTED_DRAG cycle="+cycle+" event="+event);
                });
                target.addEventFilter(javafx.scene.input.MouseEvent.MOUSE_MOVED, event -> {
                    if (canceled && cycle == 1 && event.isPrimaryButtonDown()) {
                        failure.compareAndSet(null, new AssertionError("Focus-return motion retained canceled primary button"));
                        done.countDown();
                    }
                });
                target.armedProperty().addListener((o,old,armed) -> {
                    if(!armed || canceled || cancelScheduled) return;
                    cancelScheduled=true;
                    Platform.runLater(() -> {
                        try {
                            Stage modal=new Stage(StageStyle.UNDECORATED); modal.initOwner(main); modal.initModality(Modality.WINDOW_MODAL);
                            Button close=new Button("Close"); close.setPrefSize(80,30); close.relocate(10,10); close.setOnAction(event -> modal.close());
                            modal.setScene(new Scene(new Pane(close),110,80)); modal.setX(main.getX()+160); modal.setY(main.getY()+80);
                            main.setTitle("Cancel modal "+cycle); modal.showAndWait();
                            check(!target.isArmed(),"Canceled Button remained armed");
                            check(actions==cycle-1,"Cancellation activated Button");
                            check(drags==0,"Cancellation generated a drag gesture");
                            canceled=true; target.requestFocus(); main.setTitle("Cancel returned "+cycle);
                        } catch(Throwable t) { failure.set(t); done.countDown(); }
                    });
                });
                target.setOnAction(event -> {
                    try {
                        check(canceled,"Canceled input activated Button");
                        ++actions; check(actions==cycle,"Duplicate action");
                        main.setTitle("Cancel action "+cycle);
                        ++cycle; canceled=false; cancelScheduled=false;
                        if(actions==3) done.countDown();
                    } catch(Throwable t) { failure.set(t); done.countDown(); }
                });
                main.setScene(new Scene(new Pane(target),320,220)); main.setTitle("Cancel ready"); main.show(); target.requestFocus();
            } catch (Throwable error) {
                failure.compareAndSet(null, error);
                done.countDown();
            }
        });
        boolean complete;
        try {
            complete=done.await(30,TimeUnit.SECONDS);
        } finally {
            Platform.exit();
        }
        if(failure.get()!=null) throw new AssertionError(failure.get());
        check(complete,"Input cancellation timeout");
        System.out.println("INPUT_CANCEL_PROBE_PASS");
    }
}
