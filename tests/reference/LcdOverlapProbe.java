import javafx.application.Application;
import javafx.application.Platform;
import javafx.animation.AnimationTimer;
import javafx.scene.Group;
import javafx.scene.Scene;
import javafx.scene.text.Text;
import javafx.scene.text.Font;
import javafx.scene.text.FontSmoothingType;
import javafx.scene.paint.Color;
import javafx.stage.Stage;

public class LcdOverlapProbe extends Application {
    static boolean complete;
    static Text text(double x, double y, Color color) {
        Text t = new Text(x,y,"MMMM overlap 中文");
        t.setFont(Font.font("Arial",34)); t.setFill(color);
        t.setFontSmoothingType(FontSmoothingType.LCD); return t;
    }
    @Override public void start(Stage stage) {
        Group root = new Group(text(18,60,Color.BLUE), text(20,61,Color.RED),
                text(18,135,Color.DARKGREEN), text(20,136,Color.BLACK));
        root.setOnMousePressed(event -> { complete=true; Platform.exit(); });
        Scene scene = new Scene(root,420,180,Color.WHITE);
        scene.setOnMousePressed(event -> { complete=true; Platform.exit(); });
        stage.setScene(scene); stage.show();
        new AnimationTimer() {
            int frames;
            public void handle(long now) { if (++frames==30) {stage.setTitle("LCD_OVERLAP_READY"); stop();} }
        }.start();
    }
    public static void main(String[] args) {
        launch(args);
        if(!complete) throw new AssertionError("Missing capture acknowledgement");
        System.out.println("LCD_OVERLAP_JAVA_PASS");
    }
}
