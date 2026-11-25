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

public final class ModalProbe {
    private static Stage main, independent;
    private static int round, depth, parentActions, independentActions, innerReturns, outerReturns;
    private static final CountDownLatch done=new CountDownLatch(1);
    private static final AtomicReference<Throwable> failure=new AtomicReference<>();
    private static void check(boolean value,String message) { if(!value) throw new AssertionError(message); }
    private static void guarded(Runnable action) { try { action.run(); } catch(Throwable t) { failure.set(t); done.countDown(); } }
    private static Button button(String text,int y,Runnable action) {
        Button button=new Button(text); button.setPrefSize(100,30); button.relocate(10,y);
        button.setOnAction(event -> guarded(action)); return button;
    }
    private static Stage modal(Stage owner,Modality kind,int x,int y,int width,int height,Pane root) {
        Stage stage=new Stage(StageStyle.UNDECORATED); stage.initOwner(owner); stage.initModality(kind);
        stage.setScene(new Scene(root,width,height)); stage.setX(main.getX()+x); stage.setY(main.getY()+y); return stage;
    }
    private static void openOuter() {
        ++round; depth=1;
        Pane root=new Pane();
        Stage outer=modal(main,round==1?Modality.WINDOW_MODAL:Modality.APPLICATION_MODAL,80,80,130,120,root);
        root.getChildren().add(button("Nested",10,() -> {
            check(round==1,"Unexpected inner app dialog"); depth=2;
            Pane innerRoot=new Pane(); Stage inner=modal(outer,Modality.WINDOW_MODAL,150,150,110,80,innerRoot);
            innerRoot.getChildren().add(button("Close inner",10,inner::close));
            main.setTitle("Inner active"); inner.showAndWait();
            check(outer.isShowing() && parentActions==0,"Inner close released outer/parent too early");
            ++innerReturns; depth=1; main.setTitle("Inner returned");
        }));
        root.getChildren().add(button("Close outer",60,() -> {
            check(depth==1,"Disabled outer received action"); outer.close();
        }));
        main.setTitle(round==1?"Outer window active":"Outer app active"); outer.showAndWait();
        check(main.isFocused(),"Owner focus was not restored after modal close: round="+round+
                " independentFocused="+independent.isFocused()+" ownerShowing="+main.isShowing());
        check(parentActions==(round==1?0:1) && independentActions==1,"Blocked window received an action");
        ++outerReturns; depth=0; main.setTitle(round==1?"Outer window returned":"Outer app returned");
    }
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> guarded(() -> {
            Platform.setImplicitExit(false); main=new Stage();
            Button open=button("Open modal",10,ModalProbe::openOuter);
            Button parent=button("Parent action",60,() -> {
                check(depth==0,"Blocked parent received action"); ++parentActions;
                main.setTitle("Parent action "+parentActions);
                if(parentActions==2) { check(innerReturns==1 && outerReturns==2 && independentActions==1,"Nested loop coverage differs"); done.countDown(); }
            });
            main.setScene(new Scene(new Pane(open,parent),360,260)); main.show();
            independent=new Stage(StageStyle.UNDECORATED);
            Button outside=button("Independent",10,() -> {
                check(round==1 && depth==1,"Application-modal window did not block independent Stage");
                ++independentActions; main.setTitle("Independent action "+independentActions);
            });
            independent.setScene(new Scene(new Pane(outside),120,100));
            independent.setX(main.getX()+220); independent.setY(main.getY()+10); independent.show();
            main.setTitle("Modal ready");
        }));
        boolean complete=done.await(30,TimeUnit.SECONDS);
        Platform.exit();
        if(failure.get()!=null) throw new AssertionError(failure.get());
        check(complete,"Modal interaction timeout");
        System.out.println("MODAL_PROBE_PASS");
    }
}
