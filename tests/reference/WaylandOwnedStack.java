import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.image.WritableImage;
import javafx.scene.input.MouseButton;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.robot.Robot;
import javafx.stage.Stage;
import javafx.stage.StageStyle;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.Callable;
import java.util.concurrent.FutureTask;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

public final class WaylandOwnedStack {
    private static Throwable failure;
    private static boolean completed;

    public static void main(String[] args) {
        if (!"1920x1200+490+230".equals(System.getenv("GODOT_JFX_WAYLAND_TEST_LAYOUT"))
                || System.getenv("DISPLAY") != null || Files.exists(Path.of("/mnt/wslg/runtime-dir/wayland-0"))) {
            throw new IllegalStateException("Run on the isolated labwc output with layout 1920x1200+490+230");
        }
        Application.launch(Probe.class);
        if (!completed || failure != null) throw new AssertionError("Wayland owned Stage failed", failure);
    }

    public static final class Probe extends Application {
        private final BlockingQueue<String> presses = new LinkedBlockingQueue<>();
        private Robot robot;
        private WritableImage image;

        @Override
        public void start(Stage owner) {
            Stage child = new Stage(StageStyle.UNDECORATED);
            owner.initStyle(StageStyle.UNDECORATED);
            child.initOwner(owner);
            configure(owner, "Owner overlap fixture", "owner", Color.BLUE, 420, 300);
            configure(child, "Owned overlap fixture", "child", Color.RED, 220, 150);
            owner.show();
            child.show(); // Both requests must occur in the same JavaFX dispatch.
            robot = new Robot();
            new Thread(() -> {
                try {
                    expectSurfaces(true);
                    click(830, 330, "child");
                    click(570, 470, "owner");
                    expectSurfaces(true);
                    click(830, 330, "child");
                    onFx(() -> { child.hide(); return null; });
                    expectSurfaces(false);
                    onFx(() -> { child.show(); return null; });
                    expectSurfaces(true);
                    click(830, 330, "child");
                    completed = true;
                    System.out.println("WAYLAND_OWNED_STACK_PASS");
                } catch (Throwable error) {
                    failure = error;
                } finally {
                    Platform.runLater(() -> { child.close(); owner.close(); Platform.exit(); });
                }
            }, "wayland-owned-stack").start();
        }

        private void configure(Stage stage, String title, String name, Color color, int width, int height) {
            Scene scene = new Scene(new Pane(), width, height, color);
            scene.getRoot().setStyle("-fx-background-color: transparent;");
            scene.setOnMousePressed(event -> presses.add(name));
            stage.setScene(scene);
            stage.setTitle(title);
        }

        private <T> T onFx(Callable<T> action) throws Exception {
            var pending = new FutureTask<>(action);
            Platform.runLater(pending);
            return pending.get(8, TimeUnit.SECONDS);
        }

        private void click(int x, int y, String expected) throws Exception {
            onFx(() -> { robot.mouseMove(x, y); return null; });
            onFx(() -> { robot.mouseClick(MouseButton.PRIMARY); return null; });
            String actual = presses.poll(5, TimeUnit.SECONDS);
            if (!expected.equals(actual)) throw new AssertionError("Click at " + x + "," + y
                    + " expected " + expected + ", received " + actual);
        }

        private void expectSurfaces(boolean childVisible) throws Exception {
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(8);
            String last;
            do {
                last = onFx(() -> {
                    // Capture one frame for all samples. These points lie in the owner-only,
                    // shared and child-only regions, respectively, of the private output.
                    image = robot.getScreenCapture(image, 560, 320, 420, 170, false);
                    var pixels = image.getPixelReader();
                    Color owner = pixels.getColor(10, 150);
                    Color shared = pixels.getColor(270, 10);
                    Color child = pixels.getColor(405, 70);
                    if (Color.BLUE.equals(owner) && (childVisible ? Color.RED : Color.BLUE).equals(shared)
                            && (childVisible ? Color.RED : Color.BLACK).equals(child)) return "";
                    return owner + ", " + shared + ", " + child;
                });
                if (last.isEmpty()) return;
                Thread.sleep(80);
            } while (System.nanoTime() < deadline);
            throw new AssertionError("Unexpected owner, overlap and child pixels: " + last);
        }
    }
}
