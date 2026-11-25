import javafx.animation.AnimationTimer;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.TextField;
import javafx.scene.layout.Pane;
import javafx.scene.shape.Rectangle;
import javafx.scene.paint.Color;
import javafx.scene.robot.Robot;
import javafx.scene.input.KeyCode;
import javafx.scene.input.MouseButton;
import javafx.scene.image.WritableImage;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import java.io.File;

public final class RobotProbe {
    static final CountDownLatch done = new CountDownLatch(1);
    static final AtomicReference<Throwable> failure = new AtomicReference<>();
    static void check(boolean ok,String text) { if (!ok) throw new AssertionError(text); }
    static void blue(Color color) { check(color.getBlue()>.9 && color.getRed()<.1 && color.getGreen()<.1,"Desktop pixel differs: "+color); }
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> {
            Stage stage = new Stage(StageStyle.UNDECORATED);
            TextField field = new TextField(); field.resizeRelocate(20,20,140,30); field.setPrefSize(140,30);
            Button button = new Button("Robot click"); button.resizeRelocate(20,80,140,35); button.setPrefSize(140,35);
            int[] clicks={0}, wheels={0}; button.setOnAction(e -> ++clicks[0]);
            Rectangle patch = new Rectangle(200,20,100,100); patch.setFill(Color.BLUE);
            Scene scene = new Scene(new Pane(field,button,patch),360,180);
            scene.setOnScroll(e -> { check(e.getDeltaY()<0,"Wheel direction differs"); ++wheels[0]; });
            stage.setAlwaysOnTop(true); stage.setScene(scene); stage.setX(80); stage.setY(80); stage.show(); stage.requestFocus();
            final Robot robot;
            final double oldX, oldY;
            try {
                robot = new Robot();
                oldX = robot.getMouseX();
                oldY = robot.getMouseY();
            } catch (Throwable error) {
                failure.set(error);
                stage.close();
                Platform.exit();
                done.countDown();
                return;
            }
            new AnimationTimer() {
                int step; long next;
                void click(double x,double y) { robot.mouseMove(x,y); robot.mousePress(MouseButton.PRIMARY); robot.mouseRelease(MouseButton.PRIMARY); }
                void finish(Throwable error) {
                    stop();
                    try { robot.keyRelease(KeyCode.A); robot.keyRelease(KeyCode.SHIFT); robot.mouseRelease(MouseButton.PRIMARY); robot.mouseMove(oldX,oldY); }
                    catch (Throwable cleanup) { if (error == null) error=cleanup; else error.addSuppressed(cleanup); }
                    if (error != null) failure.set(error);
                    stage.close(); Platform.exit(); done.countDown();
                }
                @Override public void handle(long now) {
                    if (next==0) { next=now+1_000_000_000L; return; } if (now<next) return; next=now+1_000_000_000L;
                    try {
                        if (!stage.isFocused()) { if (step==0) { stage.requestFocus(); return; } throw new AssertionError("Robot fixture lost focus"); }
                        var text=field.localToScreen(25,15); var action=button.localToScreen(25,15); var sample=patch.localToScreen(220,40);
                        if (step == 0) System.out.println("ROBOT_TARGET stage=" + stage.getX() + "," + stage.getY()
                                + " sample=" + sample + " field=" + text + " scale=" + stage.getOutputScaleX());
                        switch(step++) {
                            case 0 -> { blue(robot.getPixelColor(sample.getX(),sample.getY())); click(text.getX(),text.getY()); var pos = robot.getMousePosition(); check(Math.abs(pos.getX()-text.getX())<1 && Math.abs(pos.getY()-text.getY())<1,"Mouse position mapping differs: " + pos + " expected " + text); }
                            case 1 -> {
                                blue(robot.getPixelColor(sample.getX(),sample.getY())); check(field.isFocused(),"Robot click did not focus TextField"); robot.keyPress(KeyCode.SHIFT); robot.keyPress(KeyCode.A); robot.keyRelease(KeyCode.A); robot.keyRelease(KeyCode.SHIFT); }
                            case 2 -> { check(field.getText().equals("A"),"Robot key input differs: "+field.getText()); robot.keyPress(KeyCode.ENTER); robot.keyRelease(KeyCode.ENTER); }
                            case 3 -> { check(field.getText().equals("A"),"Robot text not committed"); robot.keyPress(KeyCode.ESCAPE); robot.keyRelease(KeyCode.ESCAPE); }
                            case 4 -> click(action.getX(),action.getY());
                            case 5 -> { check(clicks[0]==1,"Robot click count differs"); robot.mouseMove(sample.getX(),sample.getY()); robot.mouseWheel(1); }
                            case 6 -> {
                                try { robot.mouseMove(Double.NaN,0); throw new AssertionError("NaN position accepted"); }
                                catch (IllegalArgumentException expected) {}
                                try { robot.getScreenCapture(null,0,0,50000,50000,true); throw new AssertionError("Oversized capture accepted"); }
                                catch (IllegalArgumentException expected) {}
                                check(field.getText().equals("A"),"Committed text lost after Escape");
                                check(wheels[0]>0,"Robot wheel absent"); blue(robot.getPixelColor(sample.getX(),sample.getY()));
                                WritableImage image = robot.getScreenCapture(null,sample.getX(),sample.getY(),20,20,true);
                                check(image.getWidth()==20 && image.getHeight()==20,"Scaled capture dimensions differ"); blue(image.getPixelReader().getColor(5,5));
                                check(robot.getScreenCapture(image,sample.getX(),sample.getY(),20,20,true)==image,"WritableImage not reused");
                                WritableImage physical=robot.getScreenCapture(null,sample.getX(),sample.getY(),20,20,false);
                                check(physical.getWidth()==Math.ceil(20*stage.getOutputScaleX()) && physical.getHeight()==Math.ceil(20*stage.getOutputScaleY()),"Physical capture dimensions differ");
                                blue(physical.getPixelReader().getColor(5,5));
                                for(int i=0;i<100;i++) robot.getScreenCapture(image,sample.getX(),sample.getY(),20,20,true);
                                var origin=scene.getRoot().localToScreen(0,0);
                                WritableImage shot=robot.getScreenCapture(null,origin.getX(),origin.getY(),360,180,true);
                                BufferedImage png=new BufferedImage(360,180,BufferedImage.TYPE_INT_ARGB);
                                for(int y=0;y<180;y++) for(int x=0;x<360;x++) png.setRGB(x,y,shot.getPixelReader().getArgb(x,y));
                                ImageIO.write(png,"png",new File(new File(RobotProbe.class.getProtectionDomain().getCodeSource().getLocation().toURI()),"robot-desktop.png"));
                                System.out.println("ROBOT_PROBE_PASS scale="+stage.getOutputScaleX()+" clicks="+clicks[0]+" wheels="+wheels[0]); finish(null);
                            }
                        }
                    } catch(Throwable error) { finish(error); }
                }
            }.start();
        });
        try { new Robot(); throw new AssertionError("Robot allowed off FX thread"); } catch(IllegalStateException expected) {}
        if (!done.await(25,TimeUnit.SECONDS)) throw new AssertionError("Robot timeout");
        if (failure.get()!=null) throw new AssertionError(failure.get());
    }
}
