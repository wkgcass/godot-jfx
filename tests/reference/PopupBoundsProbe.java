import javafx.application.Platform;
import javafx.animation.AnimationTimer;
import javafx.geometry.Bounds;
import javafx.scene.Scene;
import javafx.scene.input.KeyCode;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.stage.Popup;
import javafx.stage.Stage;
import javafx.stage.Screen;
import com.sun.javafx.stage.WindowHelper;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class PopupBoundsProbe {
    private static final CountDownLatch done = new CountDownLatch(1);
    private static final AtomicReference<Throwable> failure = new AtomicReference<>();
    private static Stage stage;
    private static Popup popup;
    private static Rectangle content;
    private static int step, settling;
    private static boolean ready;
    private static double fixedX, fixedY;
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message + " at step " + step);
    }
    private static void advance() {
        if (!ready) return;
        ready = false; settling = 0; ++step; stage.setTitle("Bounds transition");
        switch (step) {
            case 1 -> { stage.setWidth(240); stage.setHeight(160); }
            case 2 -> { stage.setX(stage.getX() + 180); stage.setY(stage.getY() + 130); }
            case 3 -> { stage.setWidth(360); stage.setHeight(260); }
            case 4 -> {
                popup.setAutoFix(false); fixedX = popup.getX(); fixedY = popup.getY();
                stage.setX(stage.getX() + 20); stage.setY(stage.getY() + 20);
            }
            case 5 -> popup.setAutoFix(true);
            case 6 -> {
                popup.hide(); fixedX = popup.getX(); fixedY = popup.getY();
                stage.setX(stage.getX() - 200); stage.setY(stage.getY() - 150);
                stage.setWidth(180); stage.setHeight(120);
            }
            case 7 -> popup.show(stage, fixedX, fixedY);
            case 8 -> {
                stage.close(); check(!popup.isShowing(), "Owner close left popup showing"); done.countDown();
            }
        }
    }
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> {
            Platform.setImplicitExit(false);
            stage = new Stage(); Scene scene = new Scene(new Pane(), 360, 260);
            scene.setOnKeyPressed(event -> {
                if (event.getCode() == KeyCode.F6) {
                    try { advance(); } catch (Throwable error) { failure.set(error); done.countDown(); }
                }
            });
            stage.setScene(scene); stage.setX(80); stage.setY(80); stage.show();
            popup = new Popup(); content = new Rectangle(60, 40, Color.ORANGE); popup.getContent().add(content);
            popup.show(stage, stage.getX() + 300, stage.getY() + 200);
            new AnimationTimer() {
                @Override public void handle(long now) {
                    if (ready || step == 8 || ++settling < 15) return;
                    try {
                        if (step == 4 || step == 6) {
                            check(Math.abs(popup.getX() - fixedX) < .1 && Math.abs(popup.getY() - fixedY) < .1,
                                    "Inactive autoFix changed popup coordinates");
                        } else {
                            Bounds b = content.localToScreen(content.getBoundsInLocal());
                            check(b != null, "Popup has no screen bounds");
                            var work=Screen.getPrimary().getVisualBounds();
                            check(b.getMinX() >= work.getMinX() - .1 && b.getMinY() >= work.getMinY() - .1
                                    && b.getMaxX() <= work.getMaxX() + .1
                                    && b.getMaxY() <= work.getMaxY() + .1, "Popup escaped screen work area");
                            if(step==1) check(b.getMaxX()>stage.getX()+stage.getWidth(),"Popup was constrained to its resized owner");
                        }
                        ready = true;
                        stage.setTitle("Bounds ready " + step + " " + Math.round(popup.getX()) + " "
                                + Math.round(popup.getY()) + " " + Math.round(stage.getWidth()) + " " + Math.round(stage.getHeight())
                                + " " + (popup.isShowing()?WindowHelper.getPeer(popup).getRawHandle():0));
                    } catch (Throwable error) { stop(); failure.set(error); done.countDown(); }
                }
            }.start();
        });
        boolean completed = done.await(30, TimeUnit.SECONDS); Platform.exit();
        if (failure.get() != null) throw new AssertionError(failure.get());
        check(completed, "Popup bounds timeout");
        System.out.println("POPUP_BOUNDS_PROBE_PASS");
    }
}
