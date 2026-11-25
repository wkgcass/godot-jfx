import io.vproxy.vfx.intro.IntroFXMain;
import io.vproxy.vfx.intro.IntroTheme;
import io.vproxy.vfx.theme.Theme;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.geometry.Rectangle2D;
import javafx.scene.image.PixelFormat;
import javafx.scene.image.WritableImage;
import javafx.scene.input.MouseButton;
import javafx.scene.robot.Robot;
import javafx.stage.Screen;
import javafx.stage.Stage;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.Callable;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;

public class WaylandVStageGeometry {
    private static volatile Throwable failure;
    private static volatile boolean completed;

    public static void main(String[] args) {
        if (!"1920x1200+60+80".equals(System.getenv("GODOT_JFX_WAYLAND_TEST_LAYOUT"))
                || System.getenv("DISPLAY") != null || Files.exists(Path.of("/mnt/wslg/runtime-dir/wayland-0"))) {
            throw new IllegalStateException("Run on the isolated labwc test output with layout 1920x1200+60+80");
        }
        Theme.setTheme(new IntroTheme());
        Application.launch(Probe.class);
        if (!completed || failure != null) throw new AssertionError("Wayland VStage geometry failed", failure);
    }

    public static class Probe extends IntroFXMain {
        private Robot robot;
        private WritableImage capture;
        private final int[] pixels = new int[1920 * 1200];

        @Override
        public void start(Stage stage) {
            super.start(stage);
            robot = new Robot();
            new Thread(() -> {
                try {
                    expect(new Rectangle2D(60, 80, 1280, 800));
                    // These displacements have exact normalized increments on the test output.
                    drag(262, 94, 180, 75);
                    expect(new Rectangle2D(240, 155, 1280, 800));
                    drag(1512, 947, 180, 75);
                    expect(new Rectangle2D(240, 155, 1460, 875));
                    drag(1692, 1022, -225, -150);
                    expect(new Rectangle2D(240, 155, 1235, 725));
                    completed = true;
                    System.out.println("WAYLAND_VSTAGE_GEOMETRY_PASS");
                } catch (Throwable error) {
                    failure = error;
                } finally {
                    Platform.runLater(() -> { stage.close(); Platform.exit(); });
                }
            }, "vstage-geometry").start();
        }

        private <T> T onFx(Callable<T> action) throws Exception {
            var task = new FutureTask<>(action);
            Platform.runLater(task);
            return task.get(8, TimeUnit.SECONDS);
        }

        private void drag(int x, int y, int dx, int dy) throws Exception {
            onFx(() -> { robot.mouseMove(x, y); return null; });
            Thread.sleep(100);
            onFx(() -> { robot.mousePress(MouseButton.PRIMARY); return null; });
            try {
                Thread.sleep(300);
                for (int i = 1; i <= 12; ++i) {
                    int nextX = x + dx * i / 12;
                    int nextY = y + dy * i / 12;
                    onFx(() -> { robot.mouseMove(nextX, nextY); return null; });
                    Thread.sleep(30);
                }
            } finally {
                onFx(() -> { robot.mouseRelease(MouseButton.PRIMARY); return null; });
            }
        }

        private void expect(Rectangle2D expected) throws Exception {
            var deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(8);
            Rectangle2D actual;
            do {
                Thread.sleep(100);
                actual = onFx(this::visibleBounds);
                if (expected.equals(actual)) {
                    System.out.println("WAYLAND_VSTAGE_BOUNDS " + actual);
                    return;
                }
            } while (System.nanoTime() < deadline);
            throw new AssertionError("Expected " + expected + ", compositor capture shows " + actual);
        }

        private Rectangle2D visibleBounds() {
            var output = Screen.getPrimary().getBounds();
            capture = robot.getScreenCapture(capture, output, false);
            int width = (int) capture.getWidth();
            int height = (int) capture.getHeight();
            if (width != 1920 || height != 1200) throw new AssertionError("Unexpected output " + output);
            capture.getPixelReader().getPixels(0, 0, width, height,
                    PixelFormat.getIntArgbInstance(), pixels, 0, width);
            // This private output contains one window on a solid labwc background.
            int left = width, right = -1, top = height, bottom = -1;
            for (int y = 0; y < height; ++y) {
                for (int x = 0; x < width; ++x) {
                    if (pixels[y * width + x] == pixels[0]) continue;
                    left = Math.min(left, x);
                    right = Math.max(right, x);
                    top = Math.min(top, y);
                    bottom = y;
                }
            }
            return right < left ? Rectangle2D.EMPTY : new Rectangle2D(left, top, right - left + 1, bottom - top + 1);
        }
    }
}
