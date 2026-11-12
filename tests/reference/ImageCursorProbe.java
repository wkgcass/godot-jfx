import javafx.application.*;
import javafx.scene.*;
import javafx.scene.image.WritableImage;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.stage.Stage;
import com.sun.javafx.tk.godot.GodotBridge;

public final class ImageCursorProbe extends Application {
    private static Throwable failure;
    private static boolean complete;
    private int step;
    private Stage child;
    private Scene childScene;
    private static ImageCursor cursor(int w,int h,int x,int y,Color color) {
        var image=new WritableImage(w,h);
        for(int j=0;j<h;j++) for(int i=0;i<w;i++) image.getPixelWriter().setColor(i,j,color);
        return new ImageCursor(image,x,y);
    }
    @Override public void start(Stage stage) {
        try {
            var size=ImageCursor.getBestSize(48,40);
            if(size.getWidth()!=48 || size.getHeight()!=40) throw new AssertionError("Cursor size was forced to 16x16");
            try {GodotBridge.customCursor(257,1,0,0,new byte[1028]); throw new AssertionError("Oversize cursor accepted");}
            catch(IllegalArgumentException expected) {}
            var first=cursor(32,24,5,7,new Color(1,0,0,.5));
            var second=cursor(48,40,11,13,Color.LIME);
            var transparent=cursor(16,16,0,0,Color.TRANSPARENT);
            var root=new Pane(); var scene=new Scene(root,180,120,Color.LIGHTGRAY);
            scene.setCursor(first);
            javafx.event.EventHandler<javafx.scene.input.MouseEvent> click=event->{
                try {
                    if(step==0) {
                        child=new Stage(); child.initOwner(stage);
                        var pane=new Pane(); childScene=new Scene(pane,180,120,Color.LIGHTBLUE);
                        childScene.setCursor(second); child.setScene(childScene); child.setTitle("Cursor child");
                        pane.setOnMouseClicked(root.getOnMouseClicked()); child.show();
                    } else if(step==1) childScene.setCursor(Cursor.DEFAULT);
                    else if(step==2) childScene.setCursor(first);
                    else if(step==3) {com.sun.glass.ui.Cursor.setVisible(false); childScene.setCursor(Cursor.CROSSHAIR);}
                    else if(step==4) childScene.setCursor(second);
                    else if(step==5) com.sun.glass.ui.Cursor.setVisible(true);
                    else if(step==6) childScene.setCursor(Cursor.NONE);
                    else if(step==7) childScene.setCursor(first);
                    else if(step==8) com.sun.glass.ui.Cursor.setVisible(false);
                    else if(step==9) {com.sun.glass.ui.Cursor.setVisible(true); childScene.setCursor(transparent);}
                    else if(step==10) childScene.setCursor(Cursor.DEFAULT);
                    else if(step==11) com.sun.glass.ui.Cursor.setVisible(false);
                    else {complete=true; child.close(); Platform.exit(); return;}
                    stage.setTitle("ImageCursor "+(++step));
                } catch(Throwable error) {failure=error; Platform.exit();}
            };
            root.setOnMouseClicked(click); stage.setScene(scene); stage.setTitle("ImageCursor 0"); stage.show();
        } catch(Throwable error) {failure=error; Platform.exit();}
    }
    public static void main(String[] args) {
        launch(args);
        if(failure!=null) throw new AssertionError(failure);
        if(!complete) throw new AssertionError("Cursor interaction incomplete");
        System.out.println("IMAGE_CURSOR_PROBE_PASS");
    }
}
