import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Platform;
import javafx.scene.Group;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.effect.GodotShaderEffect;
import javafx.scene.effect.GaussianBlur;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.scene.transform.Scale;
import javafx.stage.Stage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class NodeShaderProbe {
    private static Rectangle rectangle(double x,double y,double w,double h,Color color) {
        Rectangle rectangle = new Rectangle(x,y,w,h); rectangle.setFill(color); return rectangle;
    }
    private static final String TINT = "shader_type canvas_item; uniform vec3 tint = vec3(1.0); uniform int enabled = 1; void fragment() { COLOR = texture(TEXTURE,UV); if (enabled != 0) { COLOR.rgb *= tint; } }";
    private static GodotShaderEffect tint(float r,float g,float b) {
        GodotShaderEffect effect = new GodotShaderEffect(TINT);
        effect.setFloat("tint",r,g,b); effect.setInt("enabled",1);
        return effect;
    }
    private static void checkIdentityResolution() {
        Group pattern = new Group(rectangle(0, 0, 32, 16, Color.BLACK));
        for (int x = 0; x < 64; x += 2) {
            pattern.getChildren().add(rectangle(x * 0.5, 0, 0.5, 16, Color.WHITE));
        }
        var parameters = new javafx.scene.SnapshotParameters();
        parameters.setTransform(new Scale(2, 2));
        var direct = pattern.snapshot(parameters, null);
        pattern.setEffect(new GodotShaderEffect("shader_type canvas_item; void fragment() { COLOR = texture(TEXTURE, UV); }"));
        var filtered = pattern.snapshot(parameters, null);
        for (int x = 2; x < 62; ++x) {
            int expected = direct.getPixelReader().getArgb(x, 16) & 255;
            int actual = filtered.getPixelReader().getArgb(x, 16) & 255;
            if (Math.abs(expected - actual) > 2) {
                throw new AssertionError("Identity shader lost high-DPI contrast at " + x + ": " + expected + " -> " + actual);
            }
        }
        System.out.println("NODE_SHADER_HIDPI_IDENTITY_PASS");
    }
    public static void main(String[] args) throws Exception {
        var ready = new CountDownLatch(1);
        var action = new CountDownLatch(1);
        var failure = new AtomicReference<Throwable>();
        var dynamic = new AtomicReference<GodotShaderEffect>();
        var window = new AtomicReference<Stage>();
        Platform.startup(() -> {
            try {
                GodotShaderEffect red = tint(1,0,0); dynamic.set(red);
                red.setInput(new GaussianBlur(2));
                Group subtree = new Group(rectangle(20,20,80,80,Color.WHITE));
                subtree.setEffect(red);
                Group clipped = new Group(rectangle(0,0,80,80,Color.WHITE));
                clipped.setEffect(tint(0,1,0)); clipped.setClip(new Rectangle(0,0,40,80));
                clipped.setOpacity(.5); clipped.getTransforms().add(new Scale(1.25,1,0,0));
                clipped.setTranslateX(180); clipped.setTranslateY(20);
                Rectangle sibling = rectangle(300,20,60,80,Color.BLUE);
                Button button = new Button("Shader 中文"); button.relocate(20,145);
                button.setEffect(new GodotShaderEffect("shader_type canvas_item; void fragment() { COLOR.rgb *= vec3(0.4,0.8,0.4); }"));
                Rectangle uv = rectangle(180,140,80,40,Color.WHITE);
                uv.setEffect(new GodotShaderEffect("shader_type canvas_item; void fragment() { COLOR = vec4(UV,0.0,1.0); }"));
                Stage stage = new Stage(); window.set(stage);
                button.setOnAction(event -> { red.setFloat("tint",0,0,1); stage.setTitle("Shader action"); action.countDown(); });
                stage.setScene(new Scene(new Group(subtree,clipped,sibling,button,uv),400,240,Color.WHITE));
                stage.show();
                checkIdentityResolution();
                boolean rejected = false;
                try { red.setFloat("enabled",1); } catch (IllegalArgumentException expected) { rejected = true; }
                if (!rejected) throw new AssertionError("Shader accepted wrong uniform type");
                rejected = false;
                try { red.setInput(red); } catch (IllegalArgumentException expected) { rejected = true; }
                if (!rejected) throw new AssertionError("Effect input cycle accepted");
            } catch (Throwable t) { failure.set(t); }
            finally { ready.countDown(); }
        });
        if (!ready.await(15,TimeUnit.SECONDS) || failure.get() != null) throw new AssertionError("Node shader startup failed",failure.get());
        long tick = 0;
        for (int i = 0; i < 80; ++i) {
            float gain = i % 2 == 0 ? .3f : 1f;
            var changed = new CountDownLatch(1);
            Platform.runLater(() -> { dynamic.get().setFloat("tint",gain,0,0); changed.countDown(); });
            if (!changed.await(5,TimeUnit.SECONDS)) throw new AssertionError("Shader update timeout");
            tick = GodotBridge.awaitTick(tick,1000); tick = GodotBridge.awaitTick(tick,1000);
        }
        Platform.runLater(() -> window.get().setTitle("Shader ready"));
        if (!action.await(15,TimeUnit.SECONDS)) throw new AssertionError("Shader button action missing");
        for (int i = 0; i < 120; ++i) tick = GodotBridge.awaitTick(tick,1000);
        Platform.exit();
        System.out.println("NODE_SHADER_PROBE_PASS");
    }
}
