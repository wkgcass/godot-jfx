import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.TextField;
import javafx.scene.input.InputMethodEvent;
import javafx.scene.layout.Pane;
import javafx.stage.Stage;
import com.sun.javafx.tk.godot.GodotBridge;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class NativeImeProbe {
    private static final AtomicReference<Throwable> failure = new AtomicReference<>();
    private static final CountDownLatch done = new CountDownLatch(1);
    private static int phase;
    private static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> {
            var field = new TextField(); field.relocate(20,20); field.setPrefSize(260,35);
            var button = new Button("Finish / 完成"); button.relocate(20,100); button.setPrefSize(160,35);
            var rootField = new TextField("ROOT"); rootField.setPrefSize(200,35); rootField.relocate(20,20);
            var rootStage = new Stage(); rootStage.setScene(new Scene(new Pane(rootField),260,180)); rootStage.setX(30); rootStage.setY(60); rootStage.show();
            var stage = new Stage(); stage.initOwner(rootStage); stage.setX(450); stage.setY(100); stage.setScene(new Scene(new Pane(field,button),400,180));
            field.addEventFilter(InputMethodEvent.INPUT_METHOD_TEXT_CHANGED, e -> {
                check(rootField.getText().equals("ROOT"),"Native IME changed root text");
                String composition = e.getComposed().stream().map(r -> r.getText()).reduce("",String::concat);
                if (composition.isEmpty()) return;
                Platform.runLater(() -> {
                    try {
                        if (composition.equals("ni🙂")) {
                            check(e.getCaretPosition() == 4,"UTF-32 to UTF-16 caret mismatch");
                            check(field.getText().equals(composition),"First preedit missing");
                            phase=1; stage.setTitle("IME preedit 1");
                        } else if (composition.equals("你好🙂")) {
                            check(e.getCaretPosition() == 2,"Chinese preedit caret mismatch");
                            check(field.getText().equals(composition),"Preedit replacement mismatch");
                            phase=2; stage.setTitle("IME preedit 2");
                        } else if (composition.equals("取消")) {
                            check(field.getText().equals("你好🙂取消"),"Cancellation preedit missing");
                            phase=4; stage.setTitle("IME cancel ready");
                        } else if (composition.equals("焦点")) {
                            check(field.getText().equals("你好🙂焦点"),"Focus preedit missing");
                            phase=6; stage.setTitle("IME focus ready");
                        }
                    } catch (Throwable error) { failure.set(error); done.countDown(); }
                });
            });
            field.textProperty().addListener((o,a,b) -> {
                if (phase == 2 && b.equals("你好🙂")) { phase=3; stage.setTitle("IME committed"); }
                else if (phase == 4 && b.equals("你好🙂")) { phase=5; stage.setTitle("IME canceled"); }
                else if (phase == 6 && b.equals("你好🙂")) phase=7;
            });
            button.setOnAction(e -> {
                try { check(rootField.getText().equals("ROOT"),"Native commit changed root text"); check(phase == 7 && field.getText().equals("你好🙂"),"Commit/cancel/focus changed final text"); }
                catch (Throwable error) { failure.set(error); }
                stage.setTitle("IME done"); done.countDown();
            });
            stage.setTitle("IME ready"); stage.show(); field.requestFocus();
        });
        boolean complete = done.await(25,TimeUnit.SECONDS);
        long tick=0;
        for (int i=0;i<30;i++) tick=GodotBridge.awaitTick(tick,1000);
        Platform.exit();
        if (failure.get()!=null) throw new AssertionError("IME probe failed",failure.get());
        check(complete,"IME probe timed out");
        System.out.println("NATIVE_IME_PROBE_PASS");
    }
}

