import io.vproxy.vfx.intro.*;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.util.FXUtils;
import io.vproxy.vfx.ui.button.FusionButton;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import javafx.animation.PauseTransition;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.embed.swing.SwingFXUtils;
import javafx.event.Event;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.SnapshotParameters;
import javafx.scene.control.CheckBox;
import javafx.scene.effect.GodotShaderEffect;
import javafx.scene.image.WritableImage;
import javafx.scene.input.MouseButton;
import javafx.scene.input.MouseEvent;
import javafx.scene.input.PickResult;
import javafx.scene.input.ScrollEvent;
import javafx.stage.Stage;
import javafx.util.Duration;
import javax.imageio.ImageIO;
import java.nio.file.Files;
import java.nio.file.Path;

public final class VfxBlackholeProbe extends IntroFXMain {
    private static Throwable failure;
    private static boolean complete;
    private Stage stage;
    private CheckBox toggle;
    private Node effectTarget;
    private WritableImage baseline;
    private WritableImage unfiltered;
    private final Path output = Path.of(System.getenv("GODOT_JFX_BLACKHOLE_OUTPUT"));

    @Override public void start(Stage primary) {
        super.start(primary);
        stage = primary;
        later(() -> {
            Files.createDirectories(output);
            ((FusionButton) stage.getScene().lookup("#intro-menu-button")).getOnAction().handle(null);
            later(this::menuReady);
        });
    }

    private void menuReady() throws Exception {
        toggle = (CheckBox) stage.getScene().lookup("#blackhole-effect-toggle");
        boolean godot = "Godot".equals(System.getProperty("glass.platform"));
        require(FXUtils.isPrismGodot() == godot, "Prism backend detection differs from test backend");
        if (!godot) {
            require(toggle == null, "Native reference exposes a Godot-only control");
            require(stage.getScene().getRoot().getEffect() == null, "Native reference has a root effect");
            capture("menu");
            complete = true;
            Platform.exit();
            return;
        }
        require(toggle != null && !toggle.isSelected() && !toggle.isDisabled(),
            "Godot toggle unavailable or enabled by default");
        var children = toggle.getParent().getChildrenUnmodifiable();
        require(children.indexOf(toggle) == children.size() - 4, "Blackhole toggle must precede ripple toggle");
        // Bubble a synthetic scroll through the menu viewport; no private state access.
        Event.fireEvent(toggle.getParent(), new ScrollEvent(ScrollEvent.SCROLL,
            0, 0, 0, 0, false, false, false, false, false, false,
            0, -100000, 0, -100000,
            ScrollEvent.HorizontalTextScrollUnits.NONE, 0,
            ScrollEvent.VerticalTextScrollUnits.NONE, 0, 0, null));
        later(() -> {
            var bounds = toggle.localToScene(toggle.getBoundsInLocal());
            require(bounds.getMinY() >= 0 && bounds.getMaxY() <= stage.getScene().getHeight(), "Menu toggle is not visible after scrolling");
            capture("menu");
            // Select a static original Demo page; its action also closes the drawer.
            children.stream().filter(n -> n instanceof FusionButton).skip(1)
                .map(n -> (FusionButton)n).findFirst().orElseThrow().getOnAction().handle(null);
            long deadline = System.nanoTime() + 10_000_000_000L;
            later(() -> baselineReady(deadline));
        });
    }

    private void baselineReady(long deadline) throws Exception {
        // VScene detaches the drawer at the end of its hide animation.
        if (toggle.getScene() != null) {
            require(System.nanoTime() < deadline, "Menu drawer remained attached after page selection");
            later(() -> baselineReady(deadline));
            return;
        }
        freeze(stage.getScene().getRoot());
        unfiltered = capture("off");
        move(30, 60, MouseEvent.MOUSE_MOVED);
        toggle.fire();
        effectTarget = findEffectTarget(stage.getScene().getRoot());
        require(effectTarget != null && effectTarget != stage.getScene().getRoot(), "Effect must belong to the Demo subtree");
        require(stage.getScene().getRoot().getEffect() == null, "Window root must remain unaffected");
        require(toggle.isSelected() && effectTarget.getEffect() instanceof GodotShaderEffect,
            "Toggle did not attach GodotShaderEffect to Demo subtree");
        // Compare unchanged content using the same offscreen compositing path.
        move(-10000, -10000, MouseEvent.MOUSE_MOVED);
        baseline = capture("unwarped");
        if ("1".equals(System.getenv("GODOT_JFX_BLACKHOLE_PROFILE"))) {
            profileMovingLens();
        } else {
            checkMovingLens();
        }
    }

    private void profileMovingLens() {
        new javafx.animation.AnimationTimer() {
            final long[] intervals = new long[90];
            int frame;
            long previous;
            @Override public void handle(long now) {
                if (previous != 0) intervals[frame - 1] = now - previous;
                if (frame == intervals.length) {
                    stop();
                    java.util.Arrays.sort(intervals);
                    long sum = java.util.Arrays.stream(intervals).sum();
                    System.out.printf(java.util.Locale.ROOT,
                            "BLACKHOLE_MOTION intervals=%d pulse_fps=%.3f p95_ms=%.3f%n",
                            intervals.length, intervals.length * 1e9 / sum,
                            intervals[(int)Math.ceil(intervals.length * 0.95) - 1] / 1e6);
                    checkMovingLens();
                    return;
                }
                // Two sweeps across the same static Demo page with its real shader enabled.
                move(420 + 12 * Math.abs(frame % 60 - 30), 350, MouseEvent.MOUSE_MOVED);
                previous = now;
                frame++;
            }
        }.start();
    }

    private void checkMovingLens() {
        move(600, 350, MouseEvent.MOUSE_MOVED);
        later(() -> {
            WritableImage on = capture("on");
            require(changed(baseline, on, 440, 190, 760, 510) > 500, "Shader did not visibly distort the window");
            require(on.getPixelReader().getColor(600,350).getBrightness() > 0.08, "Lens introduced a black core");
            require(changed(baseline, on, 950, 200, 1200, 500) < 20, "Effect changed pixels outside its radius");
            requireSameAlpha(baseline, on);
            var area = effectTarget.localToScene(effectTarget.getLayoutBounds());
            require(changed(baseline, on, 0, 0, (int)on.getWidth(), (int)area.getMinY()) < 20,
                "Effect changed title bar pixels");
            require(changed(baseline, on, 0, (int)Math.ceil(area.getMaxY()), (int)on.getWidth(), (int)on.getHeight()) < 20,
                "Effect changed navigation pixels");
            later(() -> {
                WritableImage stationary = capture("stationary");
                require(changed(on, stationary, 440, 190, 760, 510) < 20,
                    "Static lens changed with a stationary pointer");
                require(changed(on, stationary, 950, 200, 1200, 500) < 20,
                    "Animation changed pixels outside its radius");
                requireSameAlpha(on, stationary);
                move(800, 430, MouseEvent.MOUSE_DRAGGED);
                later(() -> {
                    WritableImage moved = capture("moved");
                    require(changed(baseline, moved, 740, 390, 900, 470) > 100, "Lens did not follow dragged pointer");
                    require(changed(baseline, moved, 500, 330, 550, 370) < 20, "Old pointer position did not recover");
                    var marker = new javafx.scene.shape.Rectangle(40, 50, javafx.scene.paint.Color.CORNFLOWERBLUE);
                    marker.setManaged(false);
                    marker.setMouseTransparent(true);
                    marker.setX(effectTarget.getLayoutBounds().getCenterX() - 20);
                    marker.setY(effectTarget.getLayoutBounds().getMinY() + 30);
                    var targetPane = (javafx.scene.layout.Pane) effectTarget;
                    targetPane.getChildren().add(marker);
                    move(-10000, -10000, MouseEvent.MOUSE_MOVED);
                    WritableImage outsideBaseline = capture("outside-baseline");
                    move(area.getCenterX(), area.getMinY() - 8, MouseEvent.MOUSE_MOVED);
                    WritableImage corner = capture("corner");
                    requireSameAlpha(baseline, corner);
                    require(effectTarget.getEffect() instanceof GodotShaderEffect, "Pointer outside the Demo removed effect");
                    require(changed(baseline, corner, 0, 0, (int)corner.getWidth(), (int)area.getMinY()) < 20,
                        "Pointer outside content changed title bar pixels");
                    require(changed(outsideBaseline, corner, (int)area.getMinX(), (int)Math.ceil(area.getMinY()),
                        (int)area.getMaxX(), (int)area.getMaxY()) > 100,
                        "Lens centered outside content did not distort content");
                    targetPane.getChildren().remove(marker);
                    toggle.fire();
                    require(!toggle.isSelected() && effectTarget.getEffect() == null, "Toggle did not remove effect");
                    later(() -> {
                        WritableImage off = capture("restored");
                        require(changed(unfiltered, off, 0, 0, (int)off.getWidth(), (int)off.getHeight()) < 30, "Disabling did not restore baseline");
                        toggle.fire();
                        stage.setWidth(1000); stage.setHeight(700);
                        later(() -> {
                            toggle.fire();
                            WritableImage resizedOff = capture("resized-off");
                            move(600,350,MouseEvent.MOUSE_MOVED);
                            toggle.fire();
                            later(() -> {
                                WritableImage resized = capture("resized");
                                require(changed(resizedOff, resized, 460, 210, 740, 490) > 100,
                                    "Resized lens did not distort content near pointer");
                                requireSameAlpha(resizedOff, resized);
                                require(resized.getPixelReader().getColor(660,340).getBrightness() > 0.08, "Resized lens introduced a black core");
                                Event.fireEvent(stage.getScene(), new MouseEvent(MouseEvent.MOUSE_EXITED, 0,0,0,0,MouseButton.NONE,0,false,false,false,false,false,false,false,false,false,false,null));
                                require(effectTarget.getEffect() == null, "Pointer exit did not remove the effect");
                                move(500,300,MouseEvent.MOUSE_MOVED);
                                require(effectTarget.getEffect() instanceof GodotShaderEffect, "Reentry did not restore effect");
                                complete = true;
                                Platform.exit();
                            });
                        });
                    });
                });
            });
        });
    }

    private static Node findEffectTarget(Node node) {
        if (node.getEffect() instanceof GodotShaderEffect) return node;
        if (node instanceof Parent parent) for (Node child : parent.getChildrenUnmodifiable()) {
            Node found = findEffectTarget(child);
            if (found != null) return found;
        }
        return null;
    }

    private void move(double x, double y, javafx.event.EventType<MouseEvent> type) {
        Event.fireEvent(stage.getScene(), new MouseEvent(type,x,y,x+stage.getX(),y+stage.getY(),MouseButton.NONE,0,
            false,false,false,false,false,false,false,false,false,false,new PickResult(stage.getScene().getRoot(),x,y)));
    }
    private WritableImage capture(String name) throws Exception {
        var parameters = new SnapshotParameters();
        parameters.setFill(javafx.scene.paint.Color.TRANSPARENT);
        parameters.setViewport(new javafx.geometry.Rectangle2D(0,0,stage.getScene().getWidth(),stage.getScene().getHeight()));
        var image = stage.getScene().getRoot().snapshot(parameters,null);
        ImageIO.write(SwingFXUtils.fromFXImage(image,null),"png",output.resolve(name+".png").toFile());
        return image;
    }
    private static int changed(WritableImage a, WritableImage b, int x0,int y0,int x1,int y1) {
        int count=0;
        for(int y=y0;y<y1;y++) for(int x=x0;x<x1;x++) {
            var c=a.getPixelReader().getColor(x,y); var d=b.getPixelReader().getColor(x,y);
            if(Math.abs(c.getRed()-d.getRed())+Math.abs(c.getGreen()-d.getGreen())+Math.abs(c.getBlue()-d.getBlue()) > 0.08) count++;
        }
        return count;
    }
    private static void requireSameAlpha(WritableImage a, WritableImage b) {
        for(int y=0;y<a.getHeight();y++) for(int x=0;x<a.getWidth();x++) {
            int before = a.getPixelReader().getArgb(x,y) >>> 24;
            int after = b.getPixelReader().getArgb(x,y) >>> 24;
            if (Math.abs(before - after) / 255.0 >= 0.01) {
                throw new AssertionError("Effect changed window alpha at " + x + "," + y + " from " + before + " to " + after);
            }
        }
    }
    private static void freeze(Node node) {
        if(node instanceof FusionButton b) b.setDisableAnimation(true);
        if(node instanceof Parent p) for(Node child:p.getChildrenUnmodifiable()) freeze(child);
    }
    private void later(Action action) {
        var pause = new PauseTransition(Duration.millis(800));
        pause.setOnFinished(event -> { try { action.run(); } catch(Throwable error) { failure=error; error.printStackTrace(); Platform.exit(); } });
        pause.play();
    }
    private interface Action { void run() throws Exception; }
    private static void require(boolean value,String message) { if(!value) throw new AssertionError(message); }
    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme()); Application.launch(VfxBlackholeProbe.class,args);
        TaskManager.get().terminate(); GlobalScreenUtils.unregister();
        if(failure!=null || !complete) throw new AssertionError("Blackhole probe incomplete",failure);
        System.out.println("VFX_BLACKHOLE_PROBE_PASS");
    }
}
