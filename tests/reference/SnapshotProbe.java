import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.SnapshotParameters;
import javafx.scene.image.WritableImage;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.stage.Stage;

public final class SnapshotProbe extends Application {
    private static Throwable failure;
    private static boolean complete;
    private static void pixel(WritableImage image,int x,int y,Color expected) {
        Color actual=image.getPixelReader().getColor(x,y);
        if(Math.abs(actual.getRed()-expected.getRed())>.02 || Math.abs(actual.getGreen()-expected.getGreen())>.02 ||
                Math.abs(actual.getBlue()-expected.getBlue())>.02 || Math.abs(actual.getOpacity()-expected.getOpacity())>.02)
            throw new AssertionError("Snapshot pixel "+x+","+y+" "+actual+" != "+expected);
    }
    @Override public void start(Stage stage) {
        var red=new Rectangle(4,4,20,20); red.setFill(new Color(1,0,0,.5));
        var blue=new Rectangle(30,10,12,12); blue.setFill(Color.BLUE);
        var root=new Pane(red,blue);
        root.setPrefSize(64,48);
        var scene=new Scene(root,64,48,Color.TRANSPARENT);
        stage.setScene(scene); stage.show();
        Platform.runLater(()->{
            try {
                var params=new SnapshotParameters(); params.setFill(Color.TRANSPARENT);
                var first=root.snapshot(params,null);
                pixel(first,10,10,new Color(1,0,0,.5)); pixel(first,34,14,Color.BLUE); pixel(first,55,35,Color.TRANSPARENT);
                red.setFill(Color.LIME);
                var second=scene.snapshot(new WritableImage(64,48));
                pixel(second,10,10,Color.LIME); pixel(second,34,14,Color.BLUE);
                red.setFill(Color.YELLOW);
                if (scene.snapshot(second) != second) throw new AssertionError("Snapshot target identity");
                pixel(second,10,10,Color.YELLOW);
                pixel(first,10,10,new Color(1,0,0,.5));
                root.snapshot(result->{
                    try {
                        if(!Platform.isFxApplicationThread()) throw new AssertionError("Snapshot callback thread");
                        pixel(result.getImage(),10,10,Color.YELLOW);
                        pixel(result.getImage(),55,35,Color.TRANSPARENT);
                        if ("1".equals(System.getenv("GODOT_JFX_SNAPSHOT_STRESS"))) {
                            stress(stage,root,red,blue);
                            return null;
                        }
                        complete=true;
                    } catch(Throwable error) { failure=error; }
                    Platform.exit(); return null;
                },params,null);
            } catch(Throwable error) { failure=error; Platform.exit(); }
        });
    }
    private void stress(Stage stage,Pane root,Rectangle red,Rectangle blue) {
        blue.setEffect(new javafx.scene.effect.GaussianBlur(2));
        class Loop {
            int count;
            boolean checkpoint;
            void next() {
                try {
                    int width=64+(count%3)*8;
                    Color color=count%2==0 ? Color.LIME : Color.YELLOW;
                    red.setFill(color);
                    var params=new SnapshotParameters(); params.setFill(Color.TRANSPARENT);
                    params.setViewport(new javafx.geometry.Rectangle2D(0,0,width,48));
                    root.snapshot(result->{
                        try {
                            if(!Platform.isFxApplicationThread()) throw new AssertionError("Stress callback thread");
                            if(result.getImage().getWidth()!=width || result.getImage().getHeight()!=48) throw new AssertionError("Stress image dimensions");
                            pixel(result.getImage(),10,10,color);
                            pixel(result.getImage(),35,15,Color.BLUE);
                            pixel(result.getImage(),width-2,40,Color.TRANSPARENT);
                            if(++count%20==0) {
                                // Sample outside the callback's strong result reference.
                                Platform.runLater(()->{
                                    System.gc();
                                    // A normal dirty frame runs Prism disposer
                                    // cleanup and submits its resource releases.
                                    blue.setTranslateX(count%40==0 ? 0 : .001);
                                    checkpoint=true; stage.setTitle("SnapshotStress "+count);
                                    System.out.println("SNAPSHOT_STRESS_CHECKPOINT "+count+" after_gc_request");
                                });
                            } else Platform.runLater(this::next);
                        } catch(Throwable error) {failure=error; Platform.exit();}
                        return null;
                    },params,null);
                } catch(Throwable error) {failure=error; Platform.exit();}
            }
        }
        var loop=new Loop();
        root.setOnMouseClicked(event->{
            if(!loop.checkpoint) return;
            loop.checkpoint=false;
            if(loop.count==200) {complete=true; Platform.exit();}
            else Platform.runLater(loop::next);
        });
        loop.next();
    }
    public static void main(String[] args) {
        launch(args);
        if(failure!=null) throw new AssertionError(failure);
        if(!complete) throw new AssertionError("Snapshot callback incomplete");
        System.out.println("READBACK_PROBE_PASS JavaFX synchronous Node/Scene and asynchronous Node snapshots");
    }
}
