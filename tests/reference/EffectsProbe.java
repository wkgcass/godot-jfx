import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Platform;
import javafx.animation.PauseTransition;
import javafx.util.Duration;
import javafx.scene.Group;
import javafx.scene.Scene;
import javafx.scene.effect.*;
import javafx.scene.paint.Color;
import javafx.scene.shape.Circle;
import javafx.scene.shape.Rectangle;
import javafx.stage.Stage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** Identical standard scene on the source SDK D3D and Godot pipelines. */
public final class EffectsProbe {
    public static void main(String[] args) throws Exception {
        String reference = System.getProperty("effects.reference");
        var ready = new CountDownLatch(1);
        var failure = new AtomicReference<Throwable>();
        Platform.startup(() -> {
            try {
                Effect[] effects = {null, new GaussianBlur(4), new BoxBlur(3,3,2),
                    new DropShadow(5,3,3,Color.BLACK), new InnerShadow(5,2,2,Color.BLACK),
                    new Glow(.6), new Bloom(.3), new ColorAdjust(.2,.3,.1,.2),
                    new Reflection(0,.5,.6,0), new MotionBlur(25,5),
                    new Lighting(new Light.Distant(45,60,Color.WHITE)),
                    new Blend(BlendMode.MULTIPLY,null,new ColorInput(24,20,20,28,Color.color(1,.3,.4,.7))),
                    displacement(false), displacement(true), new SepiaTone(.7),
                    new Shadow(BlurType.GAUSSIAN,Color.color(.2,.1,.3,.7),5),
                    new PerspectiveTransform(24,20,72,12,66,60,20,48), imageInput(),
                    new ColorInput(24,20,40,28,Color.color(.2,.7,.4,.6)), chained()};
                Group root = new Group();
                var cases=new java.util.ArrayList<Effect>(java.util.Arrays.asList(effects));
                for(var mode:BlendMode.values()) {
                    var blend=new Blend(mode,imageInput(),new ColorInput(42,28,30,25,Color.color(.8,.2,.6,.55)));
                    blend.setOpacity(.65); cases.add(blend);
                }
                cases.add(new Lighting(new Light.Point(30,15,45,Color.color(.8,.9,1))));
                var spot=new Light.Spot(30,15,45,2,Color.color(1,.9,.7));
                spot.setPointsAtX(50); spot.setPointsAtY(35); spot.setPointsAtZ(0);
                cases.add(new Lighting(spot));
                int height=((cases.size()+3)/4)*80;
                for (int i = 0; i < cases.size(); ++i) {
                    Rectangle rectangle = new Rectangle(24,20,40,28);
                    rectangle.setFill(Color.DODGERBLUE);
                    Circle circle = new Circle(56,34,12,Color.ORANGE);
                    Group content = new Group(rectangle,circle);
                    content.setEffect(cases.get(i));
                    content.setTranslateX((i % 4)*100);
                    content.setTranslateY((i / 4)*80);
                    root.getChildren().add(content);
                }
                Stage stage = new Stage();
                stage.setTitle("Effects ready");
                stage.setScene(new Scene(root,400,height,Color.WHITE));
                stage.show();
                if (reference != null) {
                    PauseTransition settle = new PauseTransition(Duration.seconds(2));
                    settle.setOnFinished(event -> {
                        try {
                            double sx=stage.getOutputScaleX(), sy=stage.getOutputScaleY();
                            var parameters=new javafx.scene.SnapshotParameters();
                            parameters.setFill(stage.getScene().getFill());
                            parameters.setTransform(new javafx.scene.transform.Scale(sx,sy));
                            parameters.setViewport(new javafx.geometry.Rectangle2D(0,0,400*sx,height*sy));
                            var image = root.snapshot(parameters,null);
                            System.out.println("EFFECTS_REFERENCE_SCALE "+sx+","+sy+" pixels="+image.getWidth()+"x"+image.getHeight());
                            javax.imageio.ImageIO.write(javafx.embed.swing.SwingFXUtils.fromFXImage(image,null),"png",new java.io.File(reference));
                            System.out.println("EFFECTS_REFERENCE_PASS");
                        } catch (Throwable t) { failure.set(t); }
                        Platform.exit();
                    });
                    settle.play();
                }
            } catch (Throwable t) { failure.set(t); }
            finally { ready.countDown(); }
        });
        if (!ready.await(15,TimeUnit.SECONDS)) throw new AssertionError("Effects startup timeout");
        if (failure.get() != null) throw new AssertionError(failure.get());
        if (reference == null) {
            long tick = 0;
            for (int i = 0; i < 600; ++i) {
                tick = GodotBridge.awaitTick(tick,1000);
                if (tick < 0) break;
            }
            Platform.exit();
            System.out.println("EFFECTS_PROBE_PASS");
        }
    }

    private static ImageInput imageInput() {
        var image=new javafx.scene.image.WritableImage(40,28);
        for(int y=0;y<28;y++) for(int x=0;x<40;x++)
            image.getPixelWriter().setColor(x,y,Color.color(x/39.0,y/27.0,.4,(x/5+y/4)%2==0?.4:1));
        return new ImageInput(image,24,20);
    }

    private static Effect chained() {
        var sepia=new SepiaTone(.8); sepia.setInput(new GaussianBlur(2));
        var shadow=new DropShadow(4,3,2,Color.color(.1,.2,.4,.65)); shadow.setInput(sepia);
        return shadow;
    }

    private static DisplacementMap displacement(boolean wrap) {
        FloatMap map = new FloatMap(64,32);
        for (int y = 0; y < 32; ++y) for (int x = 0; x < 64; ++x) {
            map.setSamples(x,y,(float)Math.sin(y*.3)*.18f,(float)Math.cos(x*.2)*.13f);
        }
        DisplacementMap effect = new DisplacementMap(map);
        effect.setOffsetX(.05); effect.setOffsetY(-.03); effect.setWrap(wrap);
        return effect;
    }
}
