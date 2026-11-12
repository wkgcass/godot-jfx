import javafx.application.Platform;
import javafx.animation.AnimationTimer;
import javafx.scene.Scene;
import javafx.scene.Node;
import javafx.scene.control.*;
import javafx.scene.layout.Pane;
import javafx.stage.Stage;
import javafx.stage.Window;
import javafx.stage.PopupWindow;
import javafx.geometry.Bounds;
import com.sun.javafx.stage.WindowHelper;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class NestedMenuProbe {
    private static final CountDownLatch done = new CountDownLatch(1);
    private static final AtomicReference<Throwable> failure = new AtomicReference<>();
    private static int opens, actions;
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> {
            Platform.setImplicitExit(false);
            Stage stage = new Stage();
            Button button = new Button("Nested menu"); button.relocate(20, 20); button.setPrefSize(140, 35);
            MenuItem leaf = new MenuItem("Leaf action");
            Menu deeper = new Menu("Deeper"); deeper.getItems().add(leaf);
            Menu branch = new Menu("Branch"); branch.getItems().add(deeper);
            ContextMenu menu = new ContextMenu(branch); button.setContextMenu(menu);
            leaf.setOnAction(event -> {
                if (++actions != opens || actions > 2) failure.set(new AssertionError("Unexpected nested action"));
            });
            menu.setOnShown(event -> ++opens);
            menu.setOnHidden(event -> Platform.runLater(() -> {
                stage.setTitle("Nested hidden " + opens + " " + actions); button.requestFocus();
                if (opens == 3) {
                    if (actions != 2) failure.set(new AssertionError("Outside dismissal activated a menu"));
                    done.countDown();
                }
            }));
            stage.setScene(new Scene(new Pane(button), 640, 360)); stage.setTitle("Nested ready"); stage.show();
            new AnimationTimer() {
                @Override public void handle(long now) {
                    if (!menu.isShowing()) return;
                    for (String text : new String[] {"Leaf action", "Deeper", "Branch"}) {
                        for (Window popup : Window.getWindows()) {
                            if (!(popup instanceof PopupWindow) || !popup.isShowing() || popup.getScene() == null) continue;
                            for (Node node : popup.getScene().getRoot().lookupAll(".label")) {
                                if (!(node instanceof Labeled label) || !text.equals(label.getText()) || !node.isVisible()) continue;
                                Bounds b = node.localToScreen(node.getBoundsInLocal());
                                if (b == null) continue;
                                int x = (int)Math.round((b.getMinX() + b.getMaxX()) / 2 - popup.getX());
                                int y = (int)Math.round((b.getMinY() + b.getMaxY()) / 2 - popup.getY());
                                stage.setTitle("Nested " + opens + " " + text.split(" ")[0] + " " + x + " " + y + " " + WindowHelper.getPeer(popup).getRawHandle());
                                return;
                            }
                        }
                    }
                }
            }.start();
        });
        boolean completed = done.await(30, TimeUnit.SECONDS); Platform.exit();
        if (failure.get() != null) throw new AssertionError(failure.get());
        if (!completed) throw new AssertionError("Nested menu timeout");
        System.out.println("NESTED_MENU_PROBE_PASS");
    }
}
