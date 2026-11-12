import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.image.WritableImage;
import javafx.scene.layout.StackPane;
import javafx.scene.paint.Color;
import javafx.stage.Stage;
import com.sun.javafx.stage.WindowHelper;

public final class WindowIconProbe extends Application {
    static Throwable failure;
    static boolean complete;
    Stage root, child;
    int step;
    static WritableImage icon(Color color) {
        var image = new WritableImage(32,32);
        for (int y=4;y<28;y++) for(int x=4;x<28;x++) image.getPixelWriter().setColor(x,y,color);
        return image;
    }
    void publish() {
        root.setTitle("WindowIcon " + step + " " + WindowHelper.getPeer(child).getRawHandle());
    }
    @Override public void start(Stage stage) {
        root=stage; child=new Stage();
        root.getIcons().add(icon(Color.RED)); child.getIcons().add(icon(Color.BLUE));
        Button next=new Button("Next icon state");
        next.setOnAction(e -> {
            try {
                switch(++step) {
                    case 1 -> root.getIcons().setAll(icon(Color.LIME));
                    case 2 -> child.getIcons().clear();
                    case 3 -> child.getIcons().setAll(icon(Color.YELLOW));
                    case 4 -> root.getIcons().clear();
                    case 5 -> { child.hide(); child.getIcons().setAll(icon(Color.MAGENTA)); child.show(); }
                    case 6 -> root.getIcons().setAll(icon(new Color(0,0,1,0.5)));
                    default -> { complete=true; child.close(); root.close(); Platform.exit(); return; }
                }
                publish();
            } catch(Throwable error) { failure=error; Platform.exit(); }
        });
        root.setScene(new Scene(new StackPane(next),240,120)); root.show();
        child.setScene(new Scene(new StackPane(new Label("Independent icon")),160,100)); child.show();
        publish();
    }
    public static void main(String[] args) {
        launch(args);
        if(failure!=null) throw new AssertionError(failure);
        if(!complete) throw new AssertionError("Icon test incomplete");
        System.out.println("WINDOW_ICON_PROBE_PASS");
    }
}
