import io.vproxy.vfx.intro.IntroFXMain;
import io.vproxy.vfx.intro.IntroTheme;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.scene.*;
import io.vproxy.vfx.ui.button.FusionImageButton;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import javafx.animation.AnimationTimer;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.stage.Stage;

/** Maximize, browse six pages and request a host-synthesized menu click. */
public final class MenuClickProbe extends IntroFXMain {
    private static Throwable failure;
    private static boolean complete;
    private AnimationTimer driver;
    private int menuActions;
    private void fail(Throwable error) { failure = error; Platform.exit(); }

    @Override public void start(Stage stage) {
        try {
            super.start(stage);
            var sf = IntroFXMain.class.getDeclaredField("sceneGroup"); sf.setAccessible(true);
            var group = (VSceneGroup) sf.get(this);
            var mf = IntroFXMain.class.getDeclaredField("mainScenes"); mf.setAccessible(true);
            var scenes = (java.util.List<?>) mf.get(this);
            driver = new AnimationTimer() {
                final long started = System.nanoTime();
                long next = started + 3_000_000_000L;
                int step;
                @Override public void handle(long now) {
                    try {
                        if (now-started > 45_000_000_000L) throw new AssertionError("Menu probe timeout");
                        if (now < next) return;
                        if (step == 0) {
                            stage.setMaximized(true);
                            next = now + 2_000_000_000L;
                        } else if (step <= 6) {
                            group.show((VScene) scenes.get(step+1), VSceneShowMethod.FROM_RIGHT);
                            next = now + (step == 6 ? 2_700_000_000L : 700_000_000L);
                        } else if (step == 7) {
                            int found = 0;
                            for (var node : stage.getScene().getRoot().lookupAll("*")) {
                                if (!(node instanceof FusionImageButton button)) continue;
                                var bounds = button.localToScene(button.getBoundsInLocal());
                                if (bounds == null || !bounds.contains(25, 20)) continue;
                                var original = button.getOnAction();
                                if (original == null) throw new AssertionError("Menu has no action");
                                // FusionButton invokes its handler directly with null;
                                // it does not dispatch a bubbling JavaFX ActionEvent.
                                button.setOnAction(event -> {
                                    try { original.handle(null); menuActions++; }
                                    catch (Throwable error) { fail(error); }
                                });
                                found++;
                            }
                            if (found != 1) throw new AssertionError("Menu button matches: " + found);
                            stage.setTitle("MenuClick CLICK");
                            next = now + 6_000_000_000L;
                        } else {
                            if (menuActions != 1) throw new AssertionError("Menu action count: " + menuActions);
                            complete = true;
                            stop();
                            Platform.exit();
                        }
                        step++;
                    } catch (Throwable error) { stop(); fail(error); }
                }
            };
            driver.start();
        } catch (Throwable error) { fail(error); }
    }
    @Override public void stop() { if (driver != null) driver.stop(); }
    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme());
        try { Application.launch(MenuClickProbe.class, args); }
        finally { try { TaskManager.get().terminate(); } finally { GlobalScreenUtils.unregister(); } }
        if (failure != null) throw new AssertionError("Menu click failed", failure);
        if (!complete) throw new AssertionError("Menu click incomplete");
        System.out.println("MENU_CLICK_PASS");
    }
}
