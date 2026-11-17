import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.TextField;
import javafx.scene.image.WritableImage;
import javafx.scene.input.Clipboard;
import javafx.scene.input.ClipboardContent;
import javafx.scene.input.DataFormat;
import javafx.scene.layout.StackPane;
import javafx.stage.Stage;
import com.sun.javafx.tk.godot.GodotBridge;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

public final class ClipboardProbe {
    private static final DataFormat CUSTOM_FORMAT = new DataFormat("application/x-godot-custom-token");
    private static final String CUSTOM_VALUE = "剪贴板自定义负载 🙂";
    private static final String CUSTOM_EXTERNAL = "外部剪贴板负载 🙂";
    private static final String WRITTEN = "Godot JavaFX 中文 🙂\nsecond line";
    private static final String EXTERNAL = "Godot external 中文 🙂";
    private static final String URL = "https://example.invalid/中文?q=🙂";
    private static final String EXTERNAL_URL = "https://external.invalid/目录#🙂";
    private static final String HTML = "<b>Godot 中文 🙂</b>";
    private static final String RTF = "{\\rtf1\\ansi Godot \\b rich\\b0}";
    private static final String EXTERNAL_HTML = "<i>External 中文 🙂</i>";
    private static final String EXTERNAL_RTF = "{\\rtf1\\ansi External \\i rich\\i0}";
    // QuantumClipboard publishes File.getAbsolutePath(); fixture paths must
    // already be absolute or the roundtrip comparison can never hold. The
    // Windows drive-letter forms are absolute there; macOS gets POSIX forms.
    // macOS additionally requires the paths to exist: the pasteboard server
    // hides file lists of nonexistent paths from other processes, and the
    // external peer validates across the process boundary. The test script
    // materializes these files.
    private static final boolean MAC = System.getProperty("os.name", "").toLowerCase().contains("mac");
    private static final List<java.io.File> FILES = MAC ? List.of(
            new java.io.File("/tmp/godot-jfx-clipboard-fixture/godot-jfx测试/报告 🙂.txt"),
            new java.io.File("/tmp/godot-jfx-clipboard-fixture/README.md")) : List.of(
            new java.io.File("C:\\godot-jfx测试\\报告 🙂.txt"),
            new java.io.File("D:\\godot-jfx-fixture\\README.md"));
    private static final List<java.io.File> EXTERNAL_FILES = MAC ? List.of(
            new java.io.File("/tmp/godot-jfx-clipboard-fixture/外部/文件 甲.txt"),
            new java.io.File("/tmp/godot-jfx-clipboard-fixture/外部/乙🙂.png")) : List.of(
            new java.io.File("D:\\外部\\文件 甲.txt"),
            new java.io.File("C:\\外部\\乙🙂.png"));
    private static final String ANSI_URL = "https://ansi.invalid/中文路径";
    // 3x2, opaque or fully transparent so INT_ARGB_PRE premultiplication stays exact.
    private static final int[] PIXELS = { 0xFF0A141E, 0xFF28323C, 0xFF46505A, 0xFF646E78, 0xFF828C96, 0x00000000 };
    // 2x2 opaque 24bpp from the external peer: red/green over blue/white.
    private static final int[] EXTERNAL_PIXELS = { 0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFFFF };
    private static boolean toolkitStarted;
    private static Stage stage;
    private static TextField field;
    private static final AtomicReference<Throwable> failure = new AtomicReference<>();

    private static void put(String text) {
        if (text == null) Clipboard.getSystemClipboard().clear();
        else { var content = new ClipboardContent(); content.putString(text); Clipboard.getSystemClipboard().setContent(content); }
    }
    private static void check(boolean value, String reason) { if (!value) throw new AssertionError(reason); }
    private static javafx.scene.image.Image probeImage() {
        var image = new WritableImage(3, 2);
        var writer = image.getPixelWriter();
        for (int y = 0; y < 2; ++y) for (int x = 0; x < 3; ++x) writer.setArgb(x, y, PIXELS[y * 3 + x]);
        return image;
    }
    private static void checkPixels(javafx.scene.image.Image image, int width, int height, int[] expected, String why) {
        check(image != null && (int)image.getWidth() == width && (int)image.getHeight() == height, why + " dimensions differ");
        var reader = image.getPixelReader();
        for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x)
            check(reader.getArgb(x, y) == expected[y * width + x], why + " pixel " + x + "," + y + " differs");
    }
    public static void main(String[] args) throws Exception {
        Throwable primary = null;
        try { runProbe(); }
        catch (Exception | Error error) { primary = error; throw error; }
        finally {
            boolean interrupted = Thread.interrupted();
            try {
                if (toolkitStarted) {
                    var close = new java.util.concurrent.FutureTask<Void>(() -> {
                        if (stage != null) stage.close();
                        return null;
                    });
                    Platform.runLater(close);
                    try { close.get(10, TimeUnit.SECONDS); }
                    catch (Exception | Error error) { close.cancel(false); throw error; }
                }
            } catch (Exception | Error error) {
                if (error instanceof InterruptedException) interrupted = true;
                if (primary != null) primary.addSuppressed(error);
                else throw error;
            } finally {
                if (toolkitStarted) Platform.exit();
                if (interrupted) Thread.currentThread().interrupt();
            }
        }
        System.out.println("CLIPBOARD_PROBE_PASS");
    }
    private static void runProbe() throws Exception {
        var started = new CountDownLatch(1);
        Platform.startup(() -> {
            try {
                field = new TextField("prefix 中文🙂 suffix");
                stage = new Stage();
                stage.setScene(new Scene(new StackPane(field), 400, 160));
                stage.show();
                field.selectRange(7,11); field.copy(); field.clear(); field.paste();
                check("中文🙂".equals(field.getText()), "TextField copy/paste Unicode mismatch");
                put("");
                check(Clipboard.getSystemClipboard().hasString() && "".equals(Clipboard.getSystemClipboard().getString()), "Empty string lost");
                put(null);
                check(!Clipboard.getSystemClipboard().hasString(), "Clipboard clear failed");
                put(WRITTEN);
                try { put("bad\0text"); throw new AssertionError("NUL accepted"); }
                catch (IllegalArgumentException expected) { }
                check(WRITTEN.equals(Clipboard.getSystemClipboard().getString()), "Rejected write changed clipboard");
                var filesOnly = new ClipboardContent(); filesOnly.putFiles(FILES);
                Clipboard.getSystemClipboard().setContent(filesOnly);
                check(Clipboard.getSystemClipboard().hasFiles() && Clipboard.getSystemClipboard().getFiles().equals(FILES), "File list roundtrip mismatch");
                check(!Clipboard.getSystemClipboard().hasString(), "Files-only write advertised text");
                var imageOnly = new ClipboardContent(); imageOnly.putImage(probeImage());
                Clipboard.getSystemClipboard().setContent(imageOnly);
                check(Clipboard.getSystemClipboard().hasImage(), "Image write missing");
                checkPixels(Clipboard.getSystemClipboard().getImage(), 3, 2, PIXELS, "Image roundtrip");
                var customOnly = new ClipboardContent(); customOnly.put(CUSTOM_FORMAT, CUSTOM_VALUE);
                Clipboard.getSystemClipboard().setContent(customOnly);
                Object customRead = Clipboard.getSystemClipboard().getContent(CUSTOM_FORMAT);
                check(customRead instanceof byte[] && CUSTOM_VALUE.equals(new String((byte[])customRead, StandardCharsets.UTF_8)), "Custom format roundtrip mismatch");
                check(!Clipboard.getSystemClipboard().hasString(), "Custom-only write advertised text");
                var badCustom = new ClipboardContent(); badCustom.put(CUSTOM_FORMAT, new byte[]{65, 0, 66});
                try { Clipboard.getSystemClipboard().setContent(badCustom); throw new AssertionError("NUL custom data accepted"); }
                catch (IllegalArgumentException expected) { }
                var badFiles = new ClipboardContent(); badFiles.putFiles(List.of(new java.io.File("bad\0path.txt")));
                try { Clipboard.getSystemClipboard().setContent(badFiles); throw new AssertionError("NUL path accepted"); }
                catch (IllegalArgumentException expected) { }
                var urlOnly = new ClipboardContent(); urlOnly.putUrl(URL);
                Clipboard.getSystemClipboard().setContent(urlOnly);
                check(Clipboard.getSystemClipboard().hasUrl() && !Clipboard.getSystemClipboard().hasString(),"URL-only format misreported");
                try { GodotBridge.clipboardWriteUrlFormats("bad",null,null,"bad\0url"); throw new AssertionError("NUL URL accepted"); }
                catch (IllegalArgumentException expected) { }
                check(URL.equals(Clipboard.getSystemClipboard().getUrl()),"Rejected URL write changed clipboard");
                var rich = new ClipboardContent(); rich.putString(WRITTEN); rich.putHtml(HTML); rich.putRtf(RTF); rich.putUrl(URL);
                rich.putFiles(FILES); rich.putImage(probeImage()); rich.put(CUSTOM_FORMAT, CUSTOM_VALUE);
                Clipboard.getSystemClipboard().setContent(rich);
                check(Clipboard.getSystemClipboard().hasUrl() && URL.equals(Clipboard.getSystemClipboard().getUrl()),"URL Unicode roundtrip mismatch");
                check(HTML.equals(Clipboard.getSystemClipboard().getHtml()),"HTML Unicode roundtrip mismatch");
                check(RTF.equals(Clipboard.getSystemClipboard().getRtf()),"RTF roundtrip mismatch");
                check(Clipboard.getSystemClipboard().hasString() && Clipboard.getSystemClipboard().hasHtml() && Clipboard.getSystemClipboard().hasRtf(),"Missing rich clipboard formats");
                check(Clipboard.getSystemClipboard().hasFiles() && Clipboard.getSystemClipboard().getFiles().equals(FILES),"Rich file list roundtrip mismatch");
                check(Clipboard.getSystemClipboard().hasImage(),"Rich image missing");
                checkPixels(Clipboard.getSystemClipboard().getImage(), 3, 2, PIXELS, "Rich image roundtrip");
                Object richCustom = Clipboard.getSystemClipboard().getContent(CUSTOM_FORMAT);
                check(richCustom instanceof byte[] && CUSTOM_VALUE.equals(new String((byte[])richCustom, StandardCharsets.UTF_8)),"Rich custom format roundtrip mismatch");
                try { GodotBridge.clipboardWriteFormats("bad",new byte[]{65},null); throw new AssertionError("Unterminated HTML accepted"); }
                catch(IllegalArgumentException expected) { }
                check(WRITTEN.equals(Clipboard.getSystemClipboard().getString()) && HTML.equals(Clipboard.getSystemClipboard().getHtml()),"Malformed native write changed clipboard");
                Clipboard.getSystemClipboard().clear();
                check(!Clipboard.getSystemClipboard().hasString() && !Clipboard.getSystemClipboard().hasHtml() && !Clipboard.getSystemClipboard().hasRtf() && !Clipboard.getSystemClipboard().hasUrl()
                        && !Clipboard.getSystemClipboard().hasFiles() && !Clipboard.getSystemClipboard().hasImage()
                        && Clipboard.getSystemClipboard().getContent(CUSTOM_FORMAT) == null,"Rich clear left formats behind");
                Clipboard.getSystemClipboard().setContent(rich);
                stage.setTitle("Clipboard written");
            } catch (Throwable error) { failure.set(error); }
            finally { started.countDown(); }
        });
        toolkitStarted = true;
        check(started.await(10,TimeUnit.SECONDS), "Clipboard startup timeout");
        var finished = new CountDownLatch(1);
        long tick = 0;
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(25);
        var syncBase = System.getenv("GODOT_JFX_CLIPBOARD_SYNC");
        var externalReady = java.nio.file.Path.of(syncBase + ".external");
        var externalRaw = java.nio.file.Path.of(syncBase + ".external2");
        var ackPath = java.nio.file.Path.of(syncBase + ".ack");
        var ackSent = new AtomicBoolean();
        while (System.nanoTime() < deadline && failure.get() == null && finished.getCount() != 0) {
            tick = GodotBridge.awaitTick(tick,1000);
            // Do not hold OpenClipboard while the OLE peer is flushing delayed data.
            if (ackSent.get() ? !java.nio.file.Files.exists(externalRaw) : !java.nio.file.Files.exists(externalReady)) continue;
            Platform.runLater(() -> {
                if (finished.getCount() == 0) return;
                try {
                    var clipboard = Clipboard.getSystemClipboard();
                    if (!ackSent.get()) {
                        if (!EXTERNAL.equals(clipboard.getString())) return;
                        field.clear(); field.paste();
                        check(EXTERNAL.equals(field.getText()), "External clipboard paste mismatch");
                        check(EXTERNAL_HTML.equals(clipboard.getHtml()),"External HTML mismatch");
                        check(clipboard.hasUrl() && EXTERNAL_URL.equals(clipboard.getUrl()),"External URL mismatch");
                        check(EXTERNAL_RTF.equals(clipboard.getRtf()),"External RTF mismatch");
                        java.nio.file.Files.writeString(ackPath, "ack");
                        ackSent.set(true);
                        return;
                    }
                    // Raw second set: CF_HDROP + 24bpp CF_DIB + ANSI-only URL + custom format, no text.
                    if (!clipboard.hasFiles() || !clipboard.hasImage() || !clipboard.hasUrl()) return;
                    check(!clipboard.hasString(), "ANSI-only set advertised text");
                    check(clipboard.getFiles().equals(EXTERNAL_FILES), "External file list mismatch");
                    checkPixels(clipboard.getImage(), 2, 2, EXTERNAL_PIXELS, "External image");
                    String actualAnsiUrl = clipboard.getUrl();
                    check(ANSI_URL.equals(actualAnsiUrl), "ANSI URL fallback mismatch: [" + actualAnsiUrl + "]");
                    Object externalCustom = clipboard.getContent(CUSTOM_FORMAT);
                    check(externalCustom instanceof byte[] && CUSTOM_EXTERNAL.equals(new String((byte[])externalCustom, StandardCharsets.UTF_8)), "External custom format mismatch");
                    finished.countDown();
                } catch (Throwable error) { failure.set(error); finished.countDown(); }
            });
        }
        if (failure.get() != null) throw new AssertionError("Clipboard probe failed",failure.get());
        check(finished.getCount() == 0,"No external clipboard update observed");
    }
}
