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

public final class PopupProbe {
    private static Stage stage;
    private static ComboBox<String> combo;
    private static ContextMenu menu;
    private static int opens, actions;
    private static final CountDownLatch done=new CountDownLatch(1);
    private static final AtomicReference<Throwable> failure=new AtomicReference<>();
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> {
            Platform.setImplicitExit(false);
            stage=new Stage();
            combo=new ComboBox<>(); combo.getItems().addAll("One","Two","Three");
            combo.setValue("One"); combo.setPrefSize(160,30); combo.relocate(20,20);
            combo.setOnShown(event -> ++opens);
            combo.setOnHidden(event -> stage.setTitle("Combo closed "+opens+" "+combo.getValue()));
            Button button=new Button("Context menu"); button.setPrefSize(150,30); button.relocate(20,140);
            MenuItem action=new MenuItem("Action"); MenuItem cancel=new MenuItem("Cancel");
            menu=new ContextMenu(action,cancel); button.setContextMenu(menu);
            action.setOnAction(event -> {
                ++actions;
                if(opens!=3 || !"Two".equals(combo.getValue()) || actions>3) failure.set(new AssertionError("Popup actions/selection differ"));
                Platform.runLater(() -> {
                    if(actions<3) { button.requestFocus(); stage.setTitle("Menu action "+actions); }
                    else { stage.setTitle("Popup done"); done.countDown(); }
                });
            });
            stage.setScene(new Scene(new Pane(combo,button),360,260)); stage.setTitle("Popup ready"); stage.show();
            new AnimationTimer() {
                @Override public void handle(long now) {
                    if(!combo.isShowing() && !menu.isShowing()) return;
                    for(Window popup : Window.getWindows()) {
                        if(!(popup instanceof PopupWindow) || !popup.isShowing() || popup.getScene()==null) continue;
                        String selector=combo.isShowing()?".list-cell":".label";
                        String text=combo.isShowing()?"Two":"Action";
                        for(Node node:popup.getScene().getRoot().lookupAll(selector)) {
                            if(!(node instanceof Labeled labeled) || !text.equals(labeled.getText()) || !node.isVisible()) continue;
                            Bounds bounds=node.localToScreen(node.getBoundsInLocal());
                            if(bounds==null) continue;
                            int x=(int)Math.round((bounds.getMinX()+bounds.getMaxX())/2-popup.getX());
                            int y=(int)Math.round((bounds.getMinY()+bounds.getMaxY())/2-popup.getY());
                            long id=WindowHelper.getPeer(popup).getRawHandle();
                            stage.setTitle((combo.isShowing()?"Combo target "+opens:"Menu target")+" "+x+" "+y+" "+id);
                            return;
                        }
                    }
                }
            }.start();
        });
        boolean complete=done.await(30,TimeUnit.SECONDS);
        Platform.exit();
        if(!complete) throw new AssertionError("Popup interactions timed out");
        if(failure.get()!=null) throw new AssertionError(failure.get());
        System.out.println("POPUP_PROBE_PASS");
    }
}
