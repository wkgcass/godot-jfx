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

public final class DragDropProbe {
    // Windows acceptance used C:/drag-test.txt; keep an absolute, non-existent
    // path per OS so put/get round-trip equality stays platform-consistent.
    static final File DRAG_FILE = new File(System.getProperty("os.name","").toLowerCase().contains("win") ? "C:/drag-test.txt" : "/tmp/drag-test.txt");
    static final CountDownLatch done = new CountDownLatch(1);
    static final AtomicReference<Throwable> failure = new AtomicReference<>();
    static final DataFormat CUSTOM = new DataFormat("application/x-godot-dnd-test");
    static Stage root, child;
    static javafx.scene.robot.Robot robot;
    static double oldMouseX, oldMouseY;
    static void startRobotDriver() {
        robot = new javafx.scene.robot.Robot();
        oldMouseX=robot.getMouseX(); oldMouseY=robot.getMouseY();
        new javafx.animation.AnimationTimer() {
            int phase; long next;
            @Override public void handle(long now) {
                if (now<next) return; next=now+250_000_000L;
                if (test==7 || failure.get()!=null) { stop(); return; }
                if (phase==0 && root.getTitle().equals("Drag ready "+test)) {
                    phase=1;
                    robot.mouseRelease(MouseButton.PRIMARY);
                    robot.mouseMove(root.getX()+40,root.getY()+40);
                    robot.mousePress(MouseButton.PRIMARY);
                } else if (phase==1) {
                    phase=2; robot.mouseMove(root.getX()+80,root.getY()+40);
                } else if (phase==2 && root.getTitle().equals("Drag active "+test)) {
                    phase=3;
                    if (test==4) {
                        robot.keyPress(KeyCode.ESCAPE); robot.keyRelease(KeyCode.ESCAPE);
                        robot.mouseRelease(MouseButton.PRIMARY); phase=0;
                    } else {
                        Stage target=test==1 || test==5 ? child : root;
                        robot.mouseMove(target.getX()+(target==child ? 40 : 240),target.getY()+40);
                        if (test>=5) phase=0;
                    }
                } else if (phase==3) {
                    phase=0; robot.mouseRelease(MouseButton.PRIMARY);
                }
            }
        }.start();
    }
    static int test, drops, completed;
    static final TransferMode[] modes = {TransferMode.COPY, TransferMode.MOVE, TransferMode.LINK};
    static void check(boolean ok, String message) {
        if (!ok) { failure.compareAndSet(null, new AssertionError(message)); done.countDown(); }
    }
    static void ready() { root.setTitle("Drag ready " + test); }
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> {
            Platform.setImplicitExit(false);
            root = new Stage(); child = new Stage(); child.initOwner(root);
            Rectangle source = new Rectangle(10,10,130,100); source.setFill(Color.ORANGE);
            Rectangle local = new Rectangle(200,10,130,100); local.setFill(Color.GREEN);
            Rectangle remote = new Rectangle(10,10,130,100); remote.setFill(Color.BLUE);
            for (Rectangle target : List.of(local,remote)) {
                target.setOnDragEntered(e -> { if (test == 5 && target == remote) Platform.runLater(child::hide); if (test == 6 && target == local) Platform.runLater(root::hide); });
                target.setOnDragOver(e -> { if (test != 3) e.acceptTransferModes(test < 3 ? modes[test] : TransferMode.COPY); e.consume(); });
                target.setOnDragDropped(e -> {
                    Dragboard b = e.getDragboard();
                    check(b.getString().equals("拖放 text") && b.getHtml().equals("<b>drag</b>")
                        && b.getRtf().equals("{\\rtf1 drag}") && b.getUrl().equals("https://example.org/drag")
                        && b.getFiles().equals(List.of(DRAG_FILE))
                        && b.getContent(CUSTOM).equals("custom payload"), "Drag data differs");
                    check(e.getTransferMode() == modes[test], "Transfer mode differs");
                    ++drops; e.setDropCompleted(true); e.consume();
                });
            }
            source.setOnMousePressed(e -> System.out.println("DRAG_PRESS " + e.getX() + "," + e.getY()));
            source.setOnMouseDragged(e -> System.out.println("DRAG_MOTION " + e.getX() + "," + e.getY()));
            source.setOnDragDetected(e -> {
                System.out.println("DRAG_DETECTED case="+test);
                Dragboard b = source.startDragAndDrop(test < 3 ? new TransferMode[]{modes[test]} : new TransferMode[]{TransferMode.COPY});
                ClipboardContent data = new ClipboardContent();
                data.putString("拖放 text"); data.putHtml("<b>drag</b>"); data.putRtf("{\\rtf1 drag}");
                data.putUrl("https://example.org/drag"); data.putFiles(List.of(DRAG_FILE)); data.put(CUSTOM,"custom payload");
                b.setContent(data); root.setTitle("Drag active " + test); e.consume();
            });
            source.setOnDragDone(e -> {
                check(e.getTransferMode() == (test < 3 ? modes[test] : null), "Done action differs in case " + test);
                check(++completed == test + 1, "Duplicate completion");
                Platform.runLater(() -> {
                    if (++test == 7) { check(drops == 3 && completed == 7, "Counts differ"); done.countDown(); }
                    else ready();
                });
            });
            root.setScene(new Scene(new Pane(source,local),360,160)); root.setX(40); root.setY(80); root.show();
            child.setScene(new Scene(new Pane(remote),180,160)); child.setX(500); child.setY(80); child.show();
            root.requestFocus(); ready();
            if ("1".equals(System.getenv("GODOT_JFX_ROBOT_DRAG"))) {
                root.setAlwaysOnTop(true);
                var delay=new javafx.animation.PauseTransition(javafx.util.Duration.seconds(1));
                delay.setOnFinished(e -> startRobotDriver()); delay.play();
            }
        });
        try {
            if (!done.await(30,TimeUnit.SECONDS)) throw new AssertionError("Drag timeout case="+test+" drops="+drops+" completed="+completed);
            if (failure.get()!=null) throw new AssertionError(failure.get());
        } finally {
            CountDownLatch closed = new CountDownLatch(1);
            Platform.runLater(() -> {
                try {
                    if (robot!=null) {
                        robot.mouseRelease(MouseButton.PRIMARY); robot.keyRelease(KeyCode.ESCAPE);
                        robot.mouseMove(oldMouseX,oldMouseY);
                    }
                    child.close(); root.close();
                } finally { closed.countDown(); }
            });
            if (!closed.await(5,TimeUnit.SECONDS)) throw new AssertionError("Close timeout");
            Platform.exit();
        }
        System.out.println("DRAG_DROP_PROBE_PASS cases=7 drops=3");
    }
}
