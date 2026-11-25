import com.sun.glass.ui.PlatformFactory;
import com.sun.javafx.iio.jpeg.JPEGImageLoaderFactory;
import com.sun.media.jfxmedia.MediaManager;
import com.sun.prism.GraphicsPipeline;
import javafx.application.GodotRuntime;
import javafx.application.Platform;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

public final class BackendProbe {
    public static void main(String[] args) throws Exception {
        switch (args[0]) {
            case "d3d", "mtl", "es2" -> {
                var observed = new CompletableFuture<String>();
                Platform.startup(() -> observed.complete(PlatformFactory.getPlatformFactory().getClass().getName()
                        + " " + GraphicsPipeline.getPipeline().getClass().getName()));
                try {
                    String backend = observed.get(10, TimeUnit.SECONDS);
                    String glass = switch (args[0]) {
                        case "mtl" -> "MacPlatformFactory";
                        case "es2" -> "GtkPlatformFactory";
                        default -> "WinPlatformFactory";
                    };
                    if (GodotRuntime.PRISM_GODOT_ENABLED || !backend.contains(glass)
                            || !backend.contains(args[0].toUpperCase(java.util.Locale.ROOT) + "Pipeline")) throw new AssertionError(backend);
                    System.out.println("NATIVE_CONTROL_PASS " + backend);
                } finally { Platform.exit(); }
            }
            case "media" -> {
                if (MediaManager.getSupportedContentTypes().length == 0) throw new AssertionError("No Media types");
                System.out.println("EARLY_MEDIA_PASS");
            }
            case "image" -> {
                var bytes = new ByteArrayOutputStream();
                ImageIO.write(new BufferedImage(7, 5, BufferedImage.TYPE_INT_RGB), "jpeg", bytes);
                var loader = JPEGImageLoaderFactory.getInstance().createImageLoader(new ByteArrayInputStream(bytes.toByteArray()));
                try {
                    var frame = loader.load(0, 0, 0, true, true, 1, 1);
                    if (frame.getWidth() != 7 || frame.getHeight() != 5) throw new AssertionError("Image size");
                } finally { loader.dispose(); }
                if (GodotRuntime.PRISM_GODOT_ENABLED) throw new AssertionError("Early image load started Prism");
                System.out.println("EARLY_IMAGE_PASS");
                // Keep the process alive until the parent inspects the loaded libraries.
                if (System.in.read() != '1') throw new AssertionError("Missing DLL observation");
            }
            default -> throw new IllegalArgumentException(args[0]);
        }
    }
}
