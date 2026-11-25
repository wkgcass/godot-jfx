import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.input.DataFormat;
import javafx.scene.input.Dragboard;
import javafx.scene.input.TransferMode;
import javafx.stage.Stage;
import java.io.File;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** In-process OLE drop probe: the host fabricates an IDataObject and feeds it
 * through the real inbound drag delegate (simulate_external_drop), so the OLE
 * payload path is asserted without physical mouse input. */
public final class OleInjectProbe {
    private static final DataFormat CUSTOM = new DataFormat("application/x-godot-custom-token");
    private static final String TEXT = "注入 OLE text 🙂";
    private static final String URL = "https://inject.example/路径 🙂";
    private static final List<File> FILES = System.getProperty("os.name").equals("Linux")
            ? List.of(new File("/tmp/注入-a.txt"), new File("/tmp/inject 乙🙂.txt"))
            : List.of(new File("C:/注入-a.txt"), new File("D:/inject 乙🙂.txt"));
    private static final String CUSTOM_VALUE = "注入自定义负载 🙂";
    private static final boolean TIMEOUT = "1".equals(System.getenv("GODOT_JFX_OLE_TIMEOUT"));

    public static void main(String[] args) throws Exception {
        var dropped = new CountDownLatch(1);
        var closed = new CountDownLatch(1);
        var failure = new AtomicReference<Throwable>();
        var expiredEvents = new java.util.concurrent.atomic.AtomicInteger();
        var stageBox = new Stage[1];
        Platform.startup(() -> {
          try {
            // Close the last temporary DND assistant before the first inbound
            // drag. The next gesture must publish to the newly cached clipboard.
            new com.sun.glass.ui.ClipboardAssistance(com.sun.glass.ui.Clipboard.DND).close();
            Pane root = new Pane();
            Stage stage = new Stage();
            stageBox[0] = stage;
            stage.setScene(new Scene(root, 400, 200));
            stage.setX(300); stage.setY(300);
            root.setOnDragEntered(e -> { if ("expired".equals(e.getDragboard().getString())) expiredEvents.incrementAndGet(); });
            root.setOnDragOver(e -> { e.acceptTransferModes(TransferMode.COPY); e.consume(); });
            root.setOnDragDropped(e -> {
                if ("expired".equals(e.getDragboard().getString())) {
                    expiredEvents.incrementAndGet(); e.setDropCompleted(false); e.consume(); return;
                }
                try {
                    Dragboard board = e.getDragboard();
                    var problems = new StringBuilder();
                    if (!TEXT.equals(board.getString())) problems.append("text=[").append(board.getString()).append("];");
                    if (!URL.equals(board.getUrl())) problems.append("url=[").append(board.getUrl()).append("];");
                    if (System.getenv("GODOT_JFX_WAYLAND_DND_DIR") != null &&
                            (!"<b>外部 HTML</b>".equals(board.getHtml()) || !"{\\rtf1 external}".equals(board.getRtf())))
                        problems.append("external HTML/RTF differs;");
                    if (!FILES.equals(board.getFiles())) problems.append("files=").append(board.getFiles()).append(";");
                    Object custom = board.getContent(CUSTOM);
                    if (!(custom instanceof byte[] bytes) || !CUSTOM_VALUE.equals(new String(bytes, java.nio.charset.StandardCharsets.UTF_8)))
                        problems.append("custom=").append(custom instanceof byte[] b2 ? new String(b2, java.nio.charset.StandardCharsets.UTF_8) : custom).append(";");
                    boolean ok = problems.length() == 0;
                    if (!ok) failure.compareAndSet(null, new AssertionError(problems.toString()));
                    e.setDropCompleted(ok); e.consume();
                    System.out.println("OLE_INJECT_DROP ok=" + ok + (ok ? "" : " problems=" + problems));
                    stage.setTitle(ok ? "OLE_INJECT_PASS" : "OLE_INJECT_FAIL");
                } catch (Throwable error) {
                    failure.compareAndSet(null, error);
                } finally {
                    dropped.countDown();
                }
            });
            stage.show();
            if (TIMEOUT) {
                Platform.runLater(() -> {
                    stage.setTitle("OLE_INJECT_BLOCKED");
                    // Both native Enter and Drop wait 1.5s. Keep FX blocked
                    // until both requests have expired, then inspect the queue.
                    try { Thread.sleep(5000); }
                    catch (InterruptedException e) { Thread.currentThread().interrupt(); failure.compareAndSet(null, e); }
                    Platform.runLater(() -> {
                        if (expiredEvents.get() != 0) {
                            failure.compareAndSet(null, new AssertionError("Expired OLE callbacks executed: " + expiredEvents.get()));
                            stage.setTitle("OLE_INJECT_FAIL"); dropped.countDown();
                        } else {
                            System.out.println("OLE_TIMEOUT_CANCEL_PASS");
                            stage.setTitle("OLE_INJECT_READY");
                        }
                    });
                });
            } else stage.setTitle("OLE_INJECT_READY");
          } catch (Throwable error) {
            failure.compareAndSet(null, error);
            dropped.countDown();
          }
        });
        try {
            if (!dropped.await(30, TimeUnit.SECONDS))
                failure.compareAndSet(null, new AssertionError("OLE inject drop timeout"));
            String directory = System.getenv("GODOT_JFX_WAYLAND_DND_DIR");
            if (directory != null && failure.get() == null) {
                var ack = java.nio.file.Path.of(directory, "title-observed");
                long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
                while (!java.nio.file.Files.exists(ack) && System.nanoTime() < deadline)
                    Thread.sleep(10);
                if (!java.nio.file.Files.exists(ack))
                    failure.compareAndSet(null, new AssertionError("Host did not observe the completed drop title"));
            }
        } catch (InterruptedException error) {
            failure.compareAndSet(null, error);
            Thread.currentThread().interrupt();
        } finally {
            // Cleanup must also run after a payload failure or timeout. Clear
            // interruption only while awaiting cleanup, then restore it.
            boolean interrupted = Thread.interrupted();
            try {
                Platform.runLater(() -> {
                    try { if (stageBox[0] != null) stageBox[0].close(); }
                    catch (Throwable error) { failure.compareAndSet(null, error); }
                    finally {
                        try { Platform.exit(); }
                        catch (Throwable error) { failure.compareAndSet(null, error); }
                        finally { closed.countDown(); }
                    }
                });
                if (!closed.await(10, TimeUnit.SECONDS))
                    failure.compareAndSet(null, new AssertionError("OLE inject close timeout"));
            } catch (InterruptedException error) {
                interrupted = true;
                failure.compareAndSet(null, error);
            } catch (Throwable error) {
                failure.compareAndSet(null, error);
            } finally {
                if (interrupted) Thread.currentThread().interrupt();
            }
        }
        if (failure.get() != null) throw new AssertionError("OLE inject probe failed", failure.get());
        System.out.println("OLE_INJECT_PROBE_PASS");
    }
}
