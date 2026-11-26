import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.shape.Rectangle;
import javafx.scene.paint.Color;
import javafx.scene.input.*;
import javafx.stage.Stage;
import java.util.List;
import java.io.File;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;

/** Cross-application OLE drag/drop probe. Real mouse input comes from the
 * JavaFX Robot (Windows-synthesized); the external endpoints are dnd_helper.exe
 * instances. Env: GODOT_JFX_HELPER_X/Y = drop-target helper window center and
 * GODOT_JFX_HELPER_SRC_X/Y = drag-source helper window center, in
 * logical coordinates (the wrapper scales native helper placement). Phase 0
 * drags text+URL+files out to the target helper; phase 1
 * receives a helper drag-in; phase 2 cancels an outbound drag with Escape. */
public final class ExternalDragProbe {
    // Windows acceptance used C:/drag-test.txt; keep an absolute path per OS
    // so put/get round-trip equality stays platform-consistent. Cocoa drops
    // file items for missing paths in cross-process drags, so the macOS
    // wrapper touches both files (Windows OLE tolerated any C:/ string).
    static final boolean WINDOWS = System.getProperty("os.name","").toLowerCase().contains("win");
    static final boolean MAC = System.getProperty("os.name", "").startsWith("Mac");
    static final File DRAG_FILE = new File(WINDOWS ? "C:/drag-test.txt" : "/tmp/drag-test.txt");
    static final File HELPER_FILE = new File(WINDOWS ? "C:/helper-source.txt" : "/tmp/helper-source.txt");
    static final DataFormat CUSTOM = new DataFormat("application/x-godot-custom-token");
    static final DataFormat OPAQUE = new DataFormat("application/x-drag-fixture-bytes");
    static final byte[] OPAQUE_IN = {(byte) 0xfe, 0, 2, 0};
    static final String CUSTOM_OUT = "出站自定义负载 🙂";
    static final String CUSTOM_IN = "外部自定义负载 🙂";
    static final CountDownLatch done = new CountDownLatch(1);
    static final AtomicReference<Throwable> failure = new AtomicReference<>();
    static final java.util.ArrayList<Thread> drivers = new java.util.ArrayList<>();
    static volatile boolean stopping;
    static javafx.animation.PauseTransition delay;
    static Stage stage;
    static javafx.scene.robot.Robot robot;
    static double oldMouseX, oldMouseY;
    static boolean mouseSaved;
    static volatile int phase, inbound;
    static double targetX, targetY, sourceX, sourceY;

    static void check(boolean ok, String message) {
        if (!ok) throw new AssertionError(message);
    }
    static void fail(Throwable error) {
        failure.compareAndSet(null, error);
        done.countDown();
    }
    static <T extends javafx.event.Event> javafx.event.EventHandler<T> guarded(javafx.event.EventHandler<T> handler) {
        return event -> {
            if (stopping || failure.get() != null) return;
            try { handler.handle(event); } catch (Throwable error) { fail(error); }
        };
    }
    static void ready(String marker) { stage.setTitle(marker); System.out.println(marker); }
    // Source/target rectangle centers in logical screen coordinates. The stage
    // has a decorated native frame; the exact chrome thickness is unknown here,
    // so the probe aims at the centers of its generous rectangles either way.
    // A private labwc test layout positions the undecorated toplevel. Wayland
    // does not report that desktop origin back through Stage.getX/getY.
    static final String layout = System.getenv("GODOT_JFX_WAYLAND_TEST_LAYOUT");
    static final String[] desktop = layout == null ? null : layout.split("[+]");
    static double sceneX(double local) {
        return desktop == null ? stage.getX() + 8 + local : Double.parseDouble(desktop[1]) + local;
    }
    static double sceneY(double local) {
        return desktop == null ? stage.getY() + 31 + local : Double.parseDouble(desktop[2]) + local;
    }

    public static void main(String[] args) throws Exception {
        targetX = Double.parseDouble(System.getenv("GODOT_JFX_HELPER_X"));
        targetY = Double.parseDouble(System.getenv("GODOT_JFX_HELPER_Y"));
        sourceX = Double.parseDouble(System.getenv("GODOT_JFX_HELPER_SRC_X"));
        sourceY = Double.parseDouble(System.getenv("GODOT_JFX_HELPER_SRC_Y"));
        Platform.startup(() -> {
            try {
                Platform.setImplicitExit(false);
                Rectangle source = new Rectangle(20,20,140,120); source.setFill(Color.ORANGE);
                Rectangle target = new Rectangle(220,20,140,100); target.setFill(Color.GREEN);
                source.setOnDragDetected(guarded(e -> {
                    System.out.println("EXTERNAL_DRAG_DETECTED phase=" + phase);
                    Dragboard b = source.startDragAndDrop(TransferMode.COPY);
                    ClipboardContent data = new ClipboardContent();
                    data.putString("外部 OLE 拖放 text"); data.putUrl("https://example.org/ole");
                    data.putFiles(List.of(DRAG_FILE));
                    data.put(CUSTOM, CUSTOM_OUT);
                    if (desktop != null) {
                        var bytes = java.nio.ByteBuffer.wrap(new byte[]{99, 0, (byte) 0xff, 1, 0, 98});
                        bytes.position(1).limit(5);
                        data.put(OPAQUE, bytes.asReadOnlyBuffer());
                    }
                    b.setContent(data);
                    // Drag view carried through the shell drag-image helper. The
                    // helper endpoint asserts the resulting DragImageBits format.
                    var view = new javafx.scene.image.WritableImage(8, 6);
                    byte[] viewPixels = new byte[8 * 6 * 4];
                    java.util.Arrays.fill(viewPixels, (byte) 0x80); // semi-visible BGRA
                    if (MAC) {
                        // Tag the preview so the file icon and the Cocoa item-count badge
                        // can be distinguished from the application's own pixels.
                        for (int i = 0; i < viewPixels.length; i += 4) {
                            viewPixels[i] = (byte) 255;
                            viewPixels[i + 1] = 0;
                            viewPixels[i + 2] = (byte) 255;
                        }
                    }
                    view.getPixelWriter().setPixels(0, 0, 8, 6,
                            javafx.scene.image.PixelFormat.getByteBgraInstance(),
                            viewPixels, 0, 32);
                    b.setDragView(view, 5, 3);
                    e.consume();
                }));
                source.setOnDragDone(guarded(e -> {
                    System.out.println("EXTERNAL_DRAG_DONE phase=" + phase + " tm=" + e.getTransferMode()
                            + " cursor=" + robot.getMouseX() + "," + robot.getMouseY()
                            + " done=" + System.identityHashCode(done) + ":" + done.getCount()
                            + " class=" + System.identityHashCode(ExternalDragProbe.class)
                            + " loader=" + ExternalDragProbe.class.getClassLoader());
                    if (phase == 0) {
                        check(e.getTransferMode() == TransferMode.COPY, "Drag-out action differs: " + e.getTransferMode());
                        phase = 1; ready("EXTERNAL_PHASE_INBOUND"); startInboundDriver();
                    } else if (phase == 2) {
                        check(e.getTransferMode() == null, "Canceled drag-out reported an action");
                        done.countDown();
                    } else check(false, "Unexpected drag-done in phase " + phase);
                }));
                target.setOnDragOver(guarded(e -> { e.acceptTransferModes(TransferMode.COPY); e.consume(); }));
                target.setOnDragDropped(guarded(e -> {
                    Dragboard b = e.getDragboard();
                    check("外部拖入 text".equals(b.getString()), "Inbound text differs: " + b.getString());
                    check("https://example.org/inbound".equals(b.getUrl()), "Inbound URL differs: " + b.getUrl());
                    check(b.getFiles() != null && b.getFiles().equals(List.of(HELPER_FILE)), "Inbound files differ: " + b.getFiles());
                    Object custom = b.getContent(CUSTOM);
                    check(custom instanceof byte[] && CUSTOM_IN.equals(new String((byte[]) custom, java.nio.charset.StandardCharsets.UTF_8)),
                            "Inbound custom payload differs: " + (custom instanceof byte[] ? new String((byte[]) custom, java.nio.charset.StandardCharsets.UTF_8) : custom));
                    if (desktop != null) {
                        Object raw = b.getContent(OPAQUE);
                        check(raw instanceof byte[] value && java.util.Arrays.equals(value, OPAQUE_IN),
                                "Inbound private MIME bytes differ");
                        System.out.println("EXTERNAL_BINARY_IN bytes=" + OPAQUE_IN.length);
                    }
                    ++inbound; e.setDropCompleted(true); e.consume();
                }));
                stage = new Stage();
                stage.setScene(new Scene(new Pane(source,target),400,160));
                stage.setX(300); stage.setY(300);
                stage.setAlwaysOnTop(true);
                stage.show(); stage.requestFocus();
                robot = new javafx.scene.robot.Robot();
                oldMouseX = robot.getMouseX(); oldMouseY = robot.getMouseY();
                mouseSaved = true;
                delay = new javafx.animation.PauseTransition(javafx.util.Duration.seconds(1));
                delay.setOnFinished(guarded(e -> { ready("EXTERNAL_PHASE_OUTBOUND"); startOutboundDriver(); }));
                delay.play();
            } catch (Throwable error) { fail(error); }
        });
        Throwable primary = null;
        try {
            System.out.println("EXTERNAL_AWAIT_START t=" + (System.currentTimeMillis() % 100000));
            if (!done.await(90, TimeUnit.SECONDS)) throw new AssertionError("External drag timeout phase=" + phase + " inbound=" + inbound
                    + " t=" + (System.currentTimeMillis() % 100000)
                    + " done=" + System.identityHashCode(done) + ":" + done.getCount()
                    + " class=" + System.identityHashCode(ExternalDragProbe.class)
                    + " loader=" + ExternalDragProbe.class.getClassLoader());
            if (failure.get() != null) throw new AssertionError(failure.get());
            if (inbound != 1) throw new AssertionError("Inbound drop count " + inbound);
        } catch (Exception | Error error) {
            primary = error;
            throw error;
        } finally {
            boolean interrupted = Thread.interrupted();
            try {
                Throwable driverFailure = null;
                try { stopDrivers(); } catch (Exception | Error error) { driverFailure = error; }
                // A failed join must not prevent input release and window cleanup.
                interrupted |= Thread.interrupted();
                try { fx(() -> {
                    // Try every release/restore/close even if one fails.
                    Throwable cleanup = null;
                    for (Runnable action : List.<Runnable>of(
                            () -> { if (delay != null) delay.stop(); },
                            () -> { if (robot != null) robot.mouseRelease(MouseButton.PRIMARY); },
                            () -> { if (robot != null) robot.keyRelease(KeyCode.ESCAPE); },
                            () -> { if (mouseSaved) robot.mouseMove(oldMouseX, oldMouseY); },
                            () -> { if (stage != null) stage.close(); })) {
                        try { action.run(); } catch (Throwable error) {
                            if (cleanup == null) cleanup = error;
                            else cleanup.addSuppressed(error);
                        }
                    }
                    if (cleanup != null) throw new AssertionError("External drag cleanup failed", cleanup);
                }); } catch (Exception | Error error) {
                    if (driverFailure == null) throw error;
                    driverFailure.addSuppressed(error);
                }
                if (driverFailure != null) throw new AssertionError("Driver shutdown failed", driverFailure);
            } catch (Exception | Error error) {
                if (primary != null) primary.addSuppressed(error);
                else throw error;
            } finally {
                Platform.exit();
                if (interrupted) Thread.currentThread().interrupt();
            }
        }
        if (failure.get() != null) throw new AssertionError(failure.get());
        System.out.println("EXTERNAL_DRAG_PROBE_PASS phases=3 inbound=1");
    }

    /** Pixel/cursor diagnostics: helper windows use a solid RGB(0,90,160) background. */
    static void probe(String tag, double x, double y) {
        try {
            System.out.println("EXTERNAL_PROBE " + tag + " @" + (int) x + "," + (int) y
                    + " color=" + robot.getPixelColor(x, y)
                    + " cursor=" + robot.getMouseX() + "," + robot.getMouseY());
        } catch (Throwable failure) { System.out.println("EXTERNAL_PROBE " + tag + " failed: " + failure); }
    }

    static void fx(Runnable action) throws Exception {
        FutureTask<Void> task = new FutureTask<>(action, null);
        Platform.runLater(task);
        try {
            task.get(10, TimeUnit.SECONDS);
        } catch (TimeoutException | InterruptedException error) {
            task.cancel(false);
            if (error instanceof InterruptedException) Thread.currentThread().interrupt();
            throw error;
        }
    }

    /**
     * 300 ms per step so the native OLE handoff has several host frames to start.
     * Runs on a dedicated thread: FX AnimationTimer pulses are Godot-frame
     * driven, and DoDragDrop blocks the Godot main thread during the OLE
     * handoff, freezing timers mid-drag. Robot calls still route through the FX
     * event queue, which keeps dispatching from the nested drag loop.
     */
    static void drive(String name, java.util.List<Runnable> steps) {
        Thread driver = new Thread(() -> {
            try {
                for (int i = 0; i < steps.size(); ++i) {
                    if (stopping || failure.get() != null || done.getCount() == 0) return;
                    int step = i;
                    fx(() -> {
                        // A queued step must not move the mouse after shutdown.
                        if (stopping || failure.get() != null || done.getCount() == 0) return;
                        System.out.println("EXTERNAL_STEP t=" + (System.currentTimeMillis() % 100000) + " step=" + step
                                + " cursor=" + robot.getMouseX() + "," + robot.getMouseY());
                        steps.get(step).run();
                    });
                    Thread.sleep(300);
                }
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
                if (!stopping) fail(error);
            } catch (Throwable error) { fail(error); }
        }, "ExternalDragDriver-" + name);
        driver.setDaemon(true);
        synchronized (drivers) {
            if (stopping) return;
            drivers.add(driver);
            driver.start();
        }
    }

    static void stopDrivers() throws InterruptedException {
        List<Thread> snapshot;
        synchronized (drivers) {
            stopping = true;
            snapshot = List.copyOf(drivers);
        }
        for (Thread driver : snapshot) driver.interrupt();
        for (Thread driver : snapshot) {
            driver.join(10000);
            if (driver.isAlive()) throw new AssertionError("Driver did not stop: " + driver.getName());
        }
    }

    static void checkCocoaDragPreview() {
        var image = robot.getScreenCapture(null, targetX - 16, targetY - 12, 32, 24, true);
        var reader = image.getPixelReader();
        int minX = 32, minY = 24, maxX = -1, maxY = -1, visible = 0;
        for (int y = 0; y < 24; y++) {
            for (int x = 0; x < 32; x++) {
                var color = reader.getColor(x, y);
                if (color.getRed() - color.getGreen() < 0.15 || color.getBlue() - color.getGreen() < 0.15) continue;
                minX = Math.min(minX, x);
                maxX = Math.max(maxX, x);
                minY = Math.min(minY, y);
                maxY = Math.max(maxY, y);
                visible++;
            }
        }
        check(maxX - minX + 1 == 8 && maxY - minY + 1 == 6 && visible == 48,
                "Expected an 8x6 tagged Cocoa preview over the destination, got bounds "
                        + minX + "," + minY + ".." + maxX + "," + maxY + " with " + visible + " pixels");
        System.out.println("COCOA_DRAG_PREVIEW_PASS visible_pixels=" + visible);
    }

    static void startOutboundDriver() {
        drive("outbound", java.util.List.of(
                () -> { probe("target", targetX, targetY); probe("stage", sceneX(90), sceneY(80)); robot.mouseMove(sceneX(90), sceneY(80)); },
                () -> robot.mousePress(MouseButton.PRIMARY),
                () -> robot.mouseMove(sceneX(120), sceneY(80)), // trigger drag detection
                () -> robot.mouseMove(targetX, targetY),          // leave hosted windows: OLE handoff
                // macOS starts the AppKit dragging session from the first real
                // mouseDragged after the handoff; a warping Robot produces no
                // further drag events without these follow-up moves (Windows
                // OLE owns the pointer already and ignores them).
                () -> robot.mouseMove(targetX + 4, targetY),
                () -> robot.mouseMove(targetX, targetY),
                () -> { if (MAC) checkCocoaDragPreview(); }, // hold while the helper receives DragEnter
                () -> robot.mouseRelease(MouseButton.PRIMARY)     // drop on the helper
        ));
    }

    static void startInboundDriver() {
        var steps = new java.util.ArrayList<Runnable>();
        steps.add(() -> { probe("source", sourceX, sourceY); robot.mouseMove(sourceX, sourceY); });
        steps.add(() -> robot.mousePress(MouseButton.PRIMARY));
        if (desktop != null) {
            // GTK recognizes the drag after motion exceeds its threshold on the
            // source surface. Let it initiate wl_data_device.start_drag there.
            steps.add(() -> robot.mouseMove(sourceX - 24, sourceY));
        }
        steps.add(() -> robot.mouseMove(sceneX(290), sceneY(70)));
        if (desktop != null) steps.add(() -> robot.mouseMove(sceneX(286), sceneY(70)));
        steps.add(() -> robot.mouseRelease(MouseButton.PRIMARY));
        steps.add(() -> {
            check(inbound == 1, "Inbound drop missing");
            if (failure.get() == null) { phase = 2; ready("EXTERNAL_PHASE_CANCEL"); startCancelDriver(); }
        });
        drive("inbound", steps);
    }

    static void startCancelDriver() {
        drive("cancel", java.util.List.of(
                () -> robot.mouseMove(sceneX(90), sceneY(80)),
                () -> robot.mousePress(MouseButton.PRIMARY),
                () -> robot.mouseMove(sceneX(120), sceneY(80)),
                () -> robot.mouseMove(targetX, targetY),           // OLE handoff again
                () -> robot.mouseMove(targetX + 4, targetY),       // see startOutboundDriver
                () -> robot.mouseMove(targetX, targetY),
                () -> { /* hold */ },
                () -> robot.keyPress(KeyCode.ESCAPE),              // OLE cancel
                () -> robot.keyRelease(KeyCode.ESCAPE),
                () -> robot.mouseRelease(MouseButton.PRIMARY)
        ));
    }
}
