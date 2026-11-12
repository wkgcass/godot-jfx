import javafx.application.Platform;
import javafx.scene.Group;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.scene.transform.Affine;
import javafx.stage.Stage;
import javafx.animation.PauseTransition;
import javafx.util.Duration;
import javafx.embed.swing.SwingFXUtils;
import javax.imageio.ImageIO;
import java.io.File;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicReference;

/** Stock D3D reference for transformed parent clip plus opacity. */
public class TransformClipReference {
    public static void main(String[] args) throws Exception {
        var done=new CountDownLatch(1);
        var failure=new AtomicReference<Throwable>();
        Platform.startup(() -> {
            var red=new Rectangle(8,8,24,24); red.setFill(Color.RED);
            var clipped=new Group(red); clipped.setTranslateX(200); clipped.setTranslateY(20);
            clipped.setClip(new Rectangle(0,0,48,64)); clipped.setOpacity(.5);
            var root=new Pane(clipped); root.setStyle("-fx-background-color: white;");
            root.getTransforms().add(new Affine(.8,-.15,50,.2,.9,10));
            var scene=new Scene(root,400,300,Color.WHITE);
            var stage=new Stage(); stage.setScene(scene); stage.show();
            var wait=new PauseTransition(Duration.millis(500));
            wait.setOnFinished(event -> {
                try {
                    var image=scene.snapshot(null);
                    var color=image.getPixelReader().getColor(220,90);
                    ImageIO.write(SwingFXUtils.fromFXImage(image,null),"png",new File("artifacts/reference/transform-clip-d3d.png"));
                    System.out.println("TRANSFORM_CLIP_D3D color="+color);
                    if(Math.abs(color.getGreen()-.75)>.02) throw new AssertionError("Unexpected native clip opacity: "+color);
                    System.out.println("TRANSFORM_CLIP_REFERENCE_PASS");
                } catch(Throwable error) { failure.set(error); }
                finally { stage.close(); Platform.exit(); done.countDown(); }
            }); wait.play();
        });
        if(!done.await(15,java.util.concurrent.TimeUnit.SECONDS)) throw new AssertionError("Reference timeout");
        if(failure.get()!=null) throw new AssertionError("Reference failed",failure.get());
    }
}
