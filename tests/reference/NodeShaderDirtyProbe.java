import javafx.animation.AnimationTimer;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.Group;
import javafx.scene.Scene;
import javafx.scene.effect.GodotShaderEffect;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.stage.Stage;

/** Animated input with fixed shader parameters; validated from host frames, not snapshots. */
public final class NodeShaderDirtyProbe extends Application {
    @Override public void start(Stage stage) {
        Rectangle background = new Rectangle(240, 140, Color.WHITE);
        Rectangle mark = new Rectangle(20, 40, 30, 40);
        mark.setFill(Color.RED);
        Group input = new Group(background, mark);
        input.setTranslateX(20);
        input.setTranslateY(20);
        input.setEffect(new GodotShaderEffect("shader_type canvas_item; render_mode unshaded, blend_premul_alpha; void fragment() { COLOR = texture(TEXTURE, vec2(1.0 - UV.x, UV.y)); }"));
        stage.setScene(new Scene(new Group(input), 300, 180, Color.WHITE));
        stage.show();
        new AnimationTimer() {
            private long start;
            @Override public void handle(long now) {
                if (start == 0) start = now;
                double elapsed = (now - start) / 1_000_000_000.0;
                mark.setOpacity(0.45 + 0.1 * Math.sin(elapsed * 8));
                int phase = elapsed < 3 ? 0 : 1;
                mark.setX(phase == 0 ? 20 : 80);
                stage.setTitle("Shader dirty " + phase);
                if (elapsed > 6) {
                    // Let the host stop checking pixels before window teardown.
                    stage.setTitle("Shader dirty done");
                }
                if (elapsed > 6.5) {
                    stop();
                    Platform.exit();
                }
            }
        }.start();
    }
    public static void main(String[] args) {
        launch(args);
        System.out.println("NODE_SHADER_DIRTY_PROBE_PASS");
    }
}
