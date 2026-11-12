import io.vproxy.vfx.intro.IntroFXMain;
import io.vproxy.vfx.intro.IntroTheme;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.scene.*;
import io.vproxy.vfx.ui.button.FusionButton;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import javafx.animation.AnimationTimer;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.control.Label;
import javafx.stage.Stage;
import javafx.stage.Window;
import java.util.List;
import java.util.ArrayList;
import com.sun.javafx.stage.WindowHelper;
import com.sun.javafx.tk.Toolkit;
import com.sun.javafx.tk.RenderJob;

/** Opens the unchanged Demo component page, then observes actual dialog actions. */
public class VfxDialogProbe extends IntroFXMain {
    private static Throwable failure;
    private static boolean complete;
    private static void collect(Node node, List<Node> nodes) {
        if (!node.isVisible()) return;
        nodes.add(node);
        if (node instanceof Parent parent) for (Node child : parent.getChildrenUnmodifiable()) collect(child,nodes);
    }
    private static List<Node> nodes(Window window) {
        var result = new ArrayList<Node>(); collect(window.getScene().getRoot(),result); return result;
    }
    private static boolean text(Window window, String text) {
        return nodes(window).stream().anyMatch(node -> node instanceof Label label && text.equals(label.getText()));
    }
    private static FusionButton button(Window window, String text) {
        return nodes(window).stream().filter(node -> node instanceof FusionButton b && text.equals(b.getTextNode().getText()))
                .map(node -> (FusionButton)node).findFirst().orElse(null);
    }
    @Override public void start(Stage stage) {
        super.start(stage);
        try {
            var scenesField = IntroFXMain.class.getDeclaredField("mainScenes"); scenesField.setAccessible(true);
            var groupField = IntroFXMain.class.getDeclaredField("sceneGroup"); groupField.setAccessible(true);
            var scenes = (List<?>)scenesField.get(this);
            var components = (VScene)scenes.stream().filter(s -> s.getClass().getSimpleName().equals("_xxbComponentsDemoScene")).findFirst().orElseThrow();
            var group = (VSceneGroup)groupField.get(this);
            group.show(components,VSceneShowMethod.FROM_RIGHT);
            new AnimationTimer() {
                private int step, stable;
                private String previous = "";
                private long deadline = System.nanoTime() + 60_000_000_000L;
                private int observedStep;
                private long diagnostic;
                private int pulses;
                @Override public void handle(long now) {
                    try {
                        ++pulses;
                        if(System.nanoTime()>diagnostic) {
                            diagnostic=System.nanoTime()+10_000_000_000L;
                            System.out.println("VFX_PULSE step="+step+" pulses="+pulses+" stable="+stable+" target="+previous);
                        }
                        var others = Window.getWindows().stream().filter(w -> w != stage && w.isShowing()).toList();
                        Window dialog = others.isEmpty() ? null : others.get(others.size()-1);
                        if (step == 0 && dialog != null && text(dialog,"Choose a number")) step=1;
                        if (step == 1 && dialog != null && text(dialog,"dialog result is Optional[2]")) step=2;
                        if (step == 2 && dialog == null) step=3;
                        if (step == 3 && dialog != null && text(dialog,"call SimpleAlert.showAndWait(...)")) step=4;
                        if (step == 4 && dialog == null) { complete=true; stop(); Platform.exit(); return; }
                        if (step == 4 && "1".equals(System.getenv("GODOT_JFX_VFX_FAILURE")))
                            throw new AssertionError("INJECTED_VFX_FAILURE");
                        if (step != observedStep) { observedStep=step; deadline=System.nanoTime()+60_000_000_000L; }
                        if (System.nanoTime() > deadline) throw new AssertionError("VFX dialog timeout step="+step+" stable="+stable+" target="+previous);
                        // The component nodes exist before FROM_RIGHT starts moving.
                        // VSceneGroup commits currentMainScene only in postShowing,
                        // so unchanged early coordinates alone cannot mean ready.
                        if (group.getCurrentMainScene() != components) {
                            previous=""; stable=0; return;
                        }
                        String targetText = switch(step) { case 0 -> "VDialog"; case 1 -> "2"; case 3 -> "SimpleAlert"; default -> "Ok"; };
                        Window targetWindow = step == 0 || step == 3 ? stage : dialog;
                        if (targetWindow == null) return;
                        FusionButton target = button(targetWindow,targetText);
                        if (target == null) return;
                        var bounds = target.localToScreen(target.getBoundsInLocal());
                        if (bounds == null || bounds.getWidth() <= 0 || bounds.getHeight() <= 0) return;
                        int x=(int)Math.round((bounds.getMinX()+bounds.getMaxX())/2-targetWindow.getX());
                        int y=(int)Math.round((bounds.getMinY()+bounds.getMaxY())/2-targetWindow.getY());
                        long id=targetWindow==stage ? 0 : WindowHelper.getPeer(targetWindow).getRawHandle();
                        String title="VfxDialog "+step+" "+x+" "+y+" "+id;
                        if (!title.equals(previous)) { previous=title; stable=0; }
                        if (++stable==2) {
                            if (x<0 || y<0 || x>=targetWindow.getWidth() || y>=targetWindow.getHeight())
                                throw new AssertionError("VFX dialog target outside its window: "+step+" "+x+","+y);
                            // Two unchanged layout observations plus a render-queue
                            // fence establish readiness without assuming a pulse rate.
                            // Publish only if this target is still current afterward.
                            Platform.runLater(() -> Toolkit.getToolkit().addRenderJob(new RenderJob(() ->
                                Platform.runLater(() -> {
                                    if (title.equals(previous) && !complete && failure==null) {
                                        deadline=System.nanoTime()+30_000_000_000L;
                                        System.out.println(title); stage.setTitle(title);
                                    }
                                }))));
                        }
                    } catch(Throwable error) { failure=error; stop(); Platform.exit(); }
                }
            }.start();
        } catch(Throwable error) { failure=error; Platform.exit(); }
    }
    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme()); Application.launch(VfxDialogProbe.class,args);
        TaskManager.get().terminate(); GlobalScreenUtils.unregister();
        if (failure != null) throw new AssertionError(failure);
        if (!complete) throw new AssertionError("VFX dialog sequence incomplete");
        System.out.println("VFX_DIALOG_PROBE_PASS");
    }
}
