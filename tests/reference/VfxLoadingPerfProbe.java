package io.vproxy.vfx.intro;

import io.vproxy.base.util.callback.Callback;
import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.button.FusionButton;
import io.vproxy.vfx.ui.scene.VScene;
import io.vproxy.vfx.ui.scene.VSceneGroup;
import io.vproxy.vfx.ui.scene.VSceneShowMethod;
import javafx.animation.AnimationTimer;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.event.Event;
import javafx.scene.Group;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.control.CheckBox;
import javafx.scene.control.Label;
import javafx.scene.input.MouseButton;
import javafx.scene.input.MouseEvent;
import javafx.stage.Stage;
import javafx.stage.Window;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/**
 * Measures pulse cadence while a LoadingStage runs on top of the ripple effect.
 * All input is synthetic: actions are invoked directly and ripples come from
 * scene-level MOUSE_PRESSED events, so the probe never touches physical input.
 */
public final class VfxLoadingPerfProbe extends IntroFXMain {
    private static boolean complete;
    private static Throwable failure;
    private static final String[] PHASES = {"baseline", "ripple", "loading", "alert", "dismissed", "ripple-off"};

    private static List<Node> nodes(Window window) {
        var result = new ArrayList<Node>();
        collect(window.getScene().getRoot(), result);
        return result;
    }

    private static void collect(Node node, List<Node> nodes) {
        if (!node.isVisible()) return;
        nodes.add(node);
        if (node instanceof Parent parent) for (Node child : parent.getChildrenUnmodifiable()) collect(child, nodes);
    }

    private static FusionButton button(Window window, String text) {
        return nodes(window).stream().filter(n -> n instanceof FusionButton b && text.equals(b.getTextNode().getText()))
            .map(n -> (FusionButton) n).findFirst().orElse(null);
    }

    private static boolean text(Window window, String text) {
        return nodes(window).stream().anyMatch(n -> n instanceof Label l && text.equals(l.getText()));
    }

    @Override public void start(Stage stage) {
        super.start(stage);
        stage.toFront();
        stage.requestFocus();
        try {
            Field scenesField = IntroFXMain.class.getDeclaredField("mainScenes");
            scenesField.setAccessible(true);
            Field groupField = IntroFXMain.class.getDeclaredField("sceneGroup");
            groupField.setAccessible(true);
            var scenes = (List<?>) scenesField.get(this);
            var page = (VScene) scenes.stream().filter(s -> s.getClass().getSimpleName().equals("_08bLoadingStageDemoScene")).findFirst().orElseThrow();
            var group = (VSceneGroup) groupField.get(this);
            group.show(page, VSceneShowMethod.FROM_RIGHT);
            ((FusionButton) stage.getScene().lookup("#intro-menu-button")).getOnAction().handle(null);
        } catch (Throwable error) {
            failure = error;
            Platform.exit();
            return;
        }
        new AnimationTimer() {
            final long start = System.nanoTime();
            final List<Long> gaps = new ArrayList<>();
            long previous, lastClick;
            int phase = -1;
            CheckBox toggle;
            Runnable closeMenu;

            @Override public void handle(long ignored) {
                try {
                    tick();
                } catch (Throwable error) {
                    failure = error;
                    stop();
                    Platform.exit();
                }
            }

            private void tick() throws Exception {
                long now = System.nanoTime();
                int next = (int) ((now - start) / 4_000_000_000L);
                if (next != phase) {
                    report();
                    phase = next;
                    gaps.clear();
                    previous = 0;
                    enter(phase);
                }
                if (phase >= 1 && phase <= 4 && now - lastClick > 400_000_000L) {
                    lastClick = now;
                    Event.fireEvent(stage.getScene(), new MouseEvent(MouseEvent.MOUSE_PRESSED,
                        1100, 550, 1100, 550, MouseButton.PRIMARY, 1,
                        false, false, false, false, true, false, false, false, false, true, null));
                }
                if (previous != 0) gaps.add(now - previous);
                previous = now;
            }

            private void enter(int next) throws Exception {
                if (next == 1) {
                    toggle = (CheckBox) stage.getScene().lookup("#ripple-effect-toggle");
                    if (toggle == null) throw new AssertionError("Ripple checkbox missing");
                    for (Node node = toggle; node != null; node = node.getParent()) {
                        if (node instanceof Group group && group.getChildren().size() == 2
                            && group.getChildren().get(0).getOnMouseClicked() != null) {
                            Node cover = group.getChildren().get(0);
                            closeMenu = () -> cover.getOnMouseClicked().handle(null);
                            break;
                        }
                    }
                    if (closeMenu == null) throw new AssertionError("Menu cover missing");
                    toggle.fire();
                    closeMenu.run();
                } else if (next == 2) {
                    FusionButton open = button(stage, "Open LoadingStage");
                    if (open == null) throw new AssertionError("Open LoadingStage button missing");
                    open.getOnAction().handle(null);
                } else if (next == 4) {
                    Window alert = Window.getWindows().stream()
                        .filter(w -> w != stage && w.isShowing() && text(w, "loading complete"))
                        .findFirst().orElse(null);
                    if (alert != null) {
                        FusionButton ok = button(alert, "Ok");
                        if (ok != null) ok.getOnAction().handle(null);
                    }
                    ((FusionButton) stage.getScene().lookup("#intro-menu-button")).getOnAction().handle(null);
                } else if (next == 5) {
                    toggle = (CheckBox) stage.getScene().lookup("#ripple-effect-toggle");
                    if (toggle == null) throw new AssertionError("Ripple checkbox missing");
                    toggle.fire();
                    closeMenu.run();
                } else if (next >= PHASES.length) {
                    complete = true;
                    stop();
                    Platform.exit();
                }
            }

            void report() {
                if (phase < 0 || gaps.isEmpty()) return;
                long sum = gaps.stream().mapToLong(Long::longValue).sum();
                Collections.sort(gaps);
                long windows = Window.getWindows().stream().filter(Window::isShowing).count();
                System.out.printf(Locale.ROOT,
                    "LOADING_PERF phase=%s intervals=%d pulse_fps=%.3f p95_ms=%.3f max_ms=%.3f windows=%d%n",
                    PHASES[phase], gaps.size(), gaps.size() * 1e9 / sum,
                    gaps.get((int) Math.ceil(gaps.size() * .95) - 1) / 1e6,
                    gaps.get(gaps.size() - 1) / 1e6, windows);
            }
        }.start();
    }

    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme());
        Application.launch(VfxLoadingPerfProbe.class, args);
        TaskManager.get().terminate();
        GlobalScreenUtils.unregister();
        if (failure != null) throw new AssertionError(failure);
        if (!complete) throw new AssertionError("Incomplete loading performance profile");
        System.out.println("VFX_LOADING_PERF_PASS");
    }
}
