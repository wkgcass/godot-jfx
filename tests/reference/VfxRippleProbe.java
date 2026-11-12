package io.vproxy.vfx.intro;

import io.vproxy.vfx.ui.button.FusionButton;
import javafx.animation.PauseTransition;
import javafx.application.Platform;
import javafx.embed.swing.SwingFXUtils;
import javafx.event.Event;
import javafx.scene.SnapshotParameters;
import javafx.scene.control.CheckBox;
import javafx.scene.effect.ColorAdjust;
import javafx.scene.image.WritableImage;
import javafx.scene.input.MouseButton;
import javafx.scene.input.MouseEvent;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.stage.Stage;
import javafx.util.Duration;
import javax.imageio.ImageIO;
import java.nio.file.Files;
import java.nio.file.Path;

public final class VfxRippleProbe extends IntroFXMain {
    private static Throwable failure;
    private static boolean complete;
    private final Path output = Path.of(System.getenv("GODOT_JFX_RIPPLE_OUTPUT"));
    private RippleEffectControl ripples;
    @Override public void start(Stage stage) {
        super.start(stage);
        later(900, () -> {
            Files.createDirectories(output);
            ((FusionButton) stage.getScene().lookup("#intro-menu-button")).getOnAction().handle(null);
            later(700, () -> checkMenu(stage));
        });
    }

    private void checkMenu(Stage stage) throws Exception {
        CheckBox toggle = (CheckBox) stage.getScene().lookup("#ripple-effect-toggle");
        CheckBox blackhole = (CheckBox) stage.getScene().lookup("#blackhole-effect-toggle");
        if (!"Godot".equals(System.getProperty("glass.platform"))) {
            require(toggle == null && blackhole == null, "Native backend exposes shader controls");
            complete = true;
            Platform.exit();
            return;
        }
        require(toggle != null && !toggle.isSelected(), "Ripple checkbox missing or initially enabled");
        require(toggle.getText().equals("Ripple Effect"), "Unexpected checkbox label");
        var menu = toggle.getParent().getChildrenUnmodifiable();
        require(menu.indexOf(toggle) == menu.size() - 2, "Ripple checkbox must end the menu");
        var root = stage.getScene().getRoot();
        var original = root.getEffect();
        toggle.fire();
        var rootEffect = root.getEffect();
        require(rootEffect != null && rootEffect != original, "Ripple effect is not attached to the Scene root");
        blackhole.fire();
        Event.fireEvent(stage.getScene(), new MouseEvent(MouseEvent.MOUSE_MOVED, 600, 350, 600, 350,
            MouseButton.NONE, 0, false, false, false, false, false, false, false, false, false, false, null));
        require(root.getEffect() == rootEffect && blackhole.isSelected(), "Blackhole displaced root ripple effect");
        blackhole.fire();
        toggle.fire();
        require(root.getEffect() == original, "Ripple toggle did not restore root effect");
        checkAnimation(stage);
    }

    private void checkAnimation(Stage stage) throws Exception {
        Pane pattern = new Pane();
        pattern.setPrefSize(640, 480);
        for (int y = 0; y < 480; y += 16) for (int x = 0; x < 640; x += 16) {
            Rectangle cell = new Rectangle(x, y, 16, 16);
            cell.setFill(((x + y) / 16 % 2) == 0 ? Color.CORNFLOWERBLUE : Color.WHITESMOKE);
            pattern.getChildren().add(cell);
        }
        Rectangle clip = new Rectangle(640, 480);
        clip.setArcWidth(24); clip.setArcHeight(24);
        pattern.setClip(clip);
        stage.getScene().setRoot(pattern);
        stage.setWidth(640); stage.setHeight(480);
        ColorAdjust previous = new ColorAdjust();
        pattern.setEffect(previous);
        ripples = new RippleEffectControl(pattern);
        stage.addEventHandler(javafx.stage.WindowEvent.WINDOW_HIDDEN, event -> ripples.close());
        final int[] delivered = {0};
        pattern.addEventHandler(MouseEvent.MOUSE_PRESSED, event -> delivered[0]++);
        later(300, () -> {
            WritableImage baseline = capture(pattern, "off");
            ripples.getControl().fire();
            later(1100, () -> {
                require(changed(baseline, capture(pattern, "idle")) < 10, "Ripples appeared without a click");
                press(pattern, 320, 240, MouseButton.SECONDARY);
                press(pattern, 320, 240, MouseButton.MIDDLE);
                later(400, () -> {
                    require(changed(baseline, capture(pattern, "right-middle")) < 10, "Non-left button spawned a ripple");
                    int before = delivered[0];
                    press(pattern, 160, 160, MouseButton.PRIMARY);
                    require(delivered[0] == before + 1, "Ripple filter consumed the click");
                    later(400, () -> {
                        WritableImage first = capture(pattern, "first-click");
                        require(changed(baseline, first, 0, 320) > 100, "Ripple did not appear near the first click");
                        require(changed(baseline, first, 400, 640) < 10, "First ripple appeared on the wrong side");
                        press(pattern, 480, 300, MouseButton.PRIMARY);
                        later(400, () -> {
                            WritableImage overlap = capture(pattern, "overlap");
                            require(changed(baseline, overlap, 0, 320) > 100, "First ripple disappeared when the second spawned");
                            require(changed(baseline, overlap, 400, 640) > 100, "Second ripple did not appear at the second click");
                            require(changed(first, overlap) > 1000, "Ripples did not expand over time");
                            require(overlap.getPixelReader().getArgb(0, 0) == baseline.getPixelReader().getArgb(0, 0), "Transparent corner changed");
                            later(3200, () -> {
                                require(changed(baseline, capture(pattern, "expired")) < 10, "Expired ripples did not restore the image");
                                press(pattern, 160, 160, MouseButton.PRIMARY);
                                ripples.getControl().fire();
                                require(pattern.getEffect() == previous, "Previous effect was not restored");
                                press(pattern, 480, 300, MouseButton.PRIMARY);
                                later(400, () -> {
                                    require(changed(baseline, capture(pattern, "disabled")) < 10, "Click while disabled changed pixels");
                                    ripples.getControl().fire();
                                    stage.setWidth(800); stage.setHeight(550);
                                    later(300, () -> {
                                        WritableImage resized = capture(pattern, "resized-off");
                                        press(pattern, 480, 300, MouseButton.PRIMARY);
                                        later(400, () -> {
                                            require(changed(resized, capture(pattern, "resized-on")) > 100, "Resized click did not produce a ripple");
                                            stage.hide();
                                            require(!ripples.getControl().isSelected() && pattern.getEffect() == previous, "Window hide did not clean up");
                                            complete = true;
                                            Platform.exit();
                                        });
                                    });
                                });
                            });
                        });
                    });
                });
            });
        });
    }

    private static void press(Pane target, double x, double y, MouseButton button) {
        Event.fireEvent(target, new MouseEvent(MouseEvent.MOUSE_PRESSED, x, y, x, y,
            button, 1, false, false, false, false, button == MouseButton.PRIMARY,
            button == MouseButton.MIDDLE, button == MouseButton.SECONDARY, false, false, true,
            new javafx.scene.input.PickResult(target, x, y)));
    }

    private WritableImage capture(Pane root, String name) throws Exception {
        SnapshotParameters parameters = new SnapshotParameters();
        parameters.setFill(Color.TRANSPARENT);
        WritableImage image = root.snapshot(parameters, null);
        ImageIO.write(SwingFXUtils.fromFXImage(image, null), "png", output.resolve(name + ".png").toFile());
        return image;
    }
    private static int changed(WritableImage a, WritableImage b) {
        return changed(a, b, 0, (int) a.getWidth());
    }
    private static int changed(WritableImage a, WritableImage b, int x0, int x1) {
        int result = 0;
        require(a.getWidth() == b.getWidth() && a.getHeight() == b.getHeight(), "Snapshot sizes changed");
        for (int y = 0; y < a.getHeight(); ++y) for (int x = x0; x < x1; ++x) {
            var c = a.getPixelReader().getColor(x, y); var d = b.getPixelReader().getColor(x, y);
            if (Math.abs(c.getRed()-d.getRed()) + Math.abs(c.getGreen()-d.getGreen()) + Math.abs(c.getBlue()-d.getBlue()) > 0.08) ++result;
        }
        return result;
    }
    private static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    private interface Action { void run() throws Exception; }
    private void later(int millis, Action action) {
        PauseTransition pause = new PauseTransition(Duration.millis(millis));
        pause.setOnFinished(event -> {
            try { action.run(); } catch (Throwable error) { failure = error; error.printStackTrace(); if (ripples != null) ripples.close(); Platform.exit(); }
        });
        pause.play();
    }
    public static void main(String[] args) {
        launch(args);
        if (failure != null || !complete) throw new AssertionError("Ripple probe incomplete", failure);
        System.out.println("VFX_RIPPLE_PROBE_PASS");
    }
}
