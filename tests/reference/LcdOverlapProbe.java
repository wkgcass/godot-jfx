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
    // A cached, unclipped layer exercises small LCD background copies on Mesa
    // D3D12. Overlapping and clipped glyphs still need the preceding colors.
    private static Group cachedGlyphs() {
        Group layer = new Group(new javafx.scene.shape.Rectangle(405, 165, Color.WHITE));
        Font font = Font.font("Arial", 16);
        for (int i = 0; i < 8; ++i) {
            int x = 4 + i * 50;
            Text first = text(x, 93, Color.BLUE);
            first.setText("A");
            first.setFont(font);
            Text second = text(x + 2, 94, Color.RED);
            second.setText("B");
            second.setFont(font);
            if (i % 2 == 0) {
                second.setClip(new javafx.scene.shape.Rectangle(x + 2, 76, 7, 23));
            }
            layer.getChildren().addAll(first, second);
        }
        layer.setCache(true);
        return layer;
    }
    @Override public void start(Stage stage) {
        Group root = new Group(text(18,60,Color.BLUE), text(20,61,Color.RED),
                text(18,135,Color.DARKGREEN), text(20,136,Color.BLACK));
        if ("Linux".equals(System.getProperty("os.name"))) root.getChildren().add(0, cachedGlyphs());
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
