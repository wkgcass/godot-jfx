import io.vproxy.vfx.intro.IntroFXMain;
import io.vproxy.vfx.intro.IntroTheme;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.scene.VSceneGroup;
import javafx.animation.AnimationTimer;
import javafx.application.Application;
import javafx.application.Platform;
import com.sun.javafx.tk.Toolkit;
import com.sun.javafx.tk.RenderJob;
import javafx.stage.Stage;
import java.util.List;

/** Observes navigation without changing VFX scene logic or dispatching actions. */
public class VfxNavigationProbe extends IntroFXMain {
    @Override public void start(Stage stage) {
        super.start(stage);
        try {
            var scenesField = IntroFXMain.class.getDeclaredField("mainScenes");
            scenesField.setAccessible(true);
            var scenes = (List<?>) scenesField.get(this);
            var groupField = IntroFXMain.class.getDeclaredField("sceneGroup");
            groupField.setAccessible(true);
            var group = (VSceneGroup) groupField.get(this);
            new AnimationTimer() {
                private int previous = -1;
                @Override public void handle(long now) {
                    int page = scenes.indexOf(group.getCurrentMainScene());
                    if (page != previous) {
                        previous = page;
                        if ("1".equals(System.getenv("GODOT_JFX_VFX_SOAK"))) {
                            long heap = java.lang.management.ManagementFactory.getMemoryMXBean().getHeapMemoryUsage().getUsed();
                            long gc = java.lang.management.ManagementFactory.getGarbageCollectorMXBeans().stream().mapToLong(bean -> Math.max(0,bean.getCollectionCount())).sum();
                            System.out.println("VFX_SOAK_JAVA page="+page+" heap_used="+heap+" gc_count="+gc);
                        }
                        if ("1".equals(System.getenv("GODOT_JFX_VFX_FREEZE"))) freezeFusion(stage.getScene().getRoot());
                        System.out.println("VFX_ACTIVE_PAGE " + page + " " + group.getCurrentMainScene().getClass().getSimpleName());
                        // Queue after this pulse, then after its rendering work.
                        // A model-side page change alone does not mean its pixels
                        // have been encoded (LCD-heavy tables exposed this).
                        Platform.runLater(() -> Toolkit.getToolkit().addRenderJob(new RenderJob(() ->
                            Platform.runLater(() -> {
                                if (scenes.indexOf(group.getCurrentMainScene()) == page)
                                    stage.setTitle("VFX Intro [page=" + page + "]");
                            }))));
                    }
                }
            }.start();
        } catch (ReflectiveOperationException failure) {
            throw new RuntimeException(failure);
        }
    }
    private static void freezeFusion(javafx.scene.Node node) {
        if(node instanceof io.vproxy.vfx.ui.button.FusionButton button) button.setDisableAnimation(true);
        if(node instanceof javafx.scene.Parent parent) for(var child:parent.getChildrenUnmodifiable()) freezeFusion(child);
    }
    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme());
        Application.launch(VfxNavigationProbe.class, args);
    }
}
