import javafx.application.Platform;
import javafx.animation.AnimationTimer;
import javafx.geometry.Bounds;
import javafx.geometry.Rectangle2D;
import com.sun.javafx.stage.WindowHelper;
import javafx.scene.Node;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.stage.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class PopupEdgeProbe {
    private static final CountDownLatch done = new CountDownLatch(1);
    private static final AtomicReference<Throwable> failure = new AtomicReference<>();
    private static Stage stage;
    private static Popup custom;
    private static int mode;
    private static Rectangle2D work;
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    private static void contained(Bounds b) {
        check(b.getMinX() >= work.getMinX() - 1 && b.getMinY() >= work.getMinY() - 1
                && b.getMaxX() <= work.getMaxX() + 1
                && b.getMaxY() <= work.getMaxY() + 1,
                "Popup content outside monitor work area: " + b);
    }
    private static void showCustom(boolean autoFix) {
        custom = new Popup(); custom.setAutoFix(autoFix);
        custom.getContent().add(new Rectangle(50, 30, Color.ORANGE));
        custom.show(stage, work.getMaxX() + 20, work.getMaxY() + 20);
    }
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> {
            stage = new Stage(); Platform.setImplicitExit(false);
            work = Screen.getPrimary().getVisualBounds();
            ComboBox<String> combo = new ComboBox<>(); combo.getItems().addAll("One", "Two", "Three");
            combo.setValue("One"); combo.relocate(170, 180); combo.setPrefSize(160, 30);
            combo.setOnHidden(event -> {
                if (!"Two".equals(combo.getValue())) failure.compareAndSet(null, new AssertionError("Edge Combo selection failed"));
                stage.setTitle("Edge selected");
            });
            Button context = new Button("Edge context"); context.relocate(180, 140); context.setPrefSize(150, 30);
            MenuItem leaf = new MenuItem("Run edge action");
            Menu branch = new Menu("More choices"); branch.getItems().add(leaf);
            ContextMenu menu = new ContextMenu(branch); context.setContextMenu(menu);
            leaf.setOnAction(event -> Platform.runLater(() -> { mode = 2; showCustom(true); }));
            Button next = new Button("Next"); next.relocate(10, 10); next.setPrefSize(80, 30);
            next.setOnAction(event -> {
                if (mode == 2) { custom.hide(); mode = 3; showCustom(false); }
                else if (mode == 3) { custom.hide(); done.countDown(); }
            });
            stage.setScene(new Scene(new Pane(combo, context, next), 340, 220)); stage.setX(work.getMaxX()-340); stage.setY(work.getMaxY()-220);
            stage.setTitle("Edge ready "+(int)work.getMinX()+" "+(int)work.getMinY()+" "+(int)work.getWidth()+" "+(int)work.getHeight()); stage.show();
            new AnimationTimer() {
                @Override public void handle(long now) {
                    try {
                        if (mode >= 2) {
                            Bounds b = custom.getContent().get(0).localToScreen(custom.getContent().get(0).getBoundsInLocal());
                            if (b == null) return;
                            if (mode == 2) { contained(b); stage.setTitle("Edge fixed"); }
                            else {
                                check(b.getMinX() > work.getMaxX() && b.getMinY() > work.getMaxY(), "autoFix=false was constrained");
                                stage.setTitle("Edge unfixed");
                            }
                            return;
                        }
                        if (!combo.isShowing() && !menu.isShowing()) return;
                        String[] texts = combo.isShowing() ? new String[]{"Two"} : new String[]{"Run edge action", "More choices"};
                        for (String text : texts) for (Window popup : Window.getWindows()) {
                            if (!(popup instanceof PopupWindow) || !popup.isShowing() || popup.getScene() == null) continue;
                            Node root = popup.getScene().getRoot();
                            Bounds bounds = root.localToScreen(root.getLayoutBounds());
                            if (bounds != null && bounds.getWidth() > 0) contained(bounds);
                            for (Node content : root.lookupAll(combo.isShowing() ? ".list-view" : ".context-menu")) {
                                Bounds area = content.localToScreen(content.getLayoutBounds());
                                if (area != null && area.getWidth() > 0) contained(area);
                            }
                            for (Node node : root.lookupAll(combo.isShowing() ? ".list-cell" : ".label")) {
                                if (!(node instanceof Labeled label) || !text.equals(label.getText()) || !node.isVisible()) continue;
                                Bounds b = node.localToScreen(node.getBoundsInLocal());
                                if (b == null) continue;
                                contained(b);
                                int x = (int)Math.round((b.getMinX() + b.getMaxX()) / 2 - popup.getX());
                                int y = (int)Math.round((b.getMinY() + b.getMaxY()) / 2 - popup.getY());
                                if (text.equals("Run edge action")) check(popup.getX()<menu.getX(), "Edge submenu did not flip left");
                                if (combo.isShowing()) check(popup.getY()<combo.localToScreen(combo.getBoundsInLocal()).getMinY(), "Edge combo did not open upward");
                                stage.setTitle("Edge " + text.split(" ")[0] + " " + x + " " + y + " " + WindowHelper.getPeer(popup).getRawHandle()); return;
                            }
                        }
                    } catch (Throwable error) { stop(); failure.compareAndSet(null, error); done.countDown(); }
                }
            }.start();
        });
        boolean completed = done.await(30, TimeUnit.SECONDS); Platform.exit();
        if (failure.get() != null) throw new AssertionError(failure.get());
        check(completed, "Popup edge timeout");
        System.out.println("POPUP_EDGE_PROBE_PASS");
    }
}
