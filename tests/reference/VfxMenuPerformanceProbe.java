package io.vproxy.vfx.intro;

import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.button.FusionButton;
import javafx.animation.AnimationTimer;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.event.Event;
import javafx.scene.Group;
import javafx.scene.Node;
import javafx.scene.control.CheckBox;
import javafx.scene.input.MouseButton;
import javafx.scene.input.MouseEvent;
import javafx.stage.Stage;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

public final class VfxMenuPerformanceProbe extends IntroFXMain {
    private static boolean complete;
    private static Throwable failure;
    private static final String[] PHASES = {"closed", "opening", "open-ripples", "closed-ripples", "sliding"};

    @Override public void start(Stage stage) {
        super.start(stage);
        stage.toFront();
        stage.requestFocus();
        new AnimationTimer() {
            final long start = System.nanoTime();
            final List<Long> gaps = new ArrayList<>();
            long previous, lastClick, lastSlide;
            boolean menuOpen;
            CheckBox toggle;
            int phase = -1, unfocused;
            Runnable closeMenu;

            @Override public void handle(long ignored) {
                try {
                    long now = System.nanoTime();
                    int next = (int) ((now - start) / 5_000_000_000L);
                    if (next != phase) {
                        report();
                        phase = next;
                        gaps.clear();
                        previous = 0;
                        unfocused = 0;
                        if (phase == 1) {
                            ((FusionButton) stage.getScene().lookup("#intro-menu-button")).getOnAction().handle(null);
                        } else if (phase == 2) {
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
                        } else if (phase == 3) {
                            closeMenu.run();
                        } else if (phase == 4) {
                            toggle.fire();
                            lastSlide = 0;
                            menuOpen = false;
                        } else if (phase >= PHASES.length) {
                            complete = true;
                            stop();
                            Platform.exit();
                            return;
                        }
                    }
                    if (phase >= 2 && phase <= 3 && now - lastClick > 500_000_000L) {
                        lastClick = now;
                        Event.fireEvent(stage.getScene(), new MouseEvent(MouseEvent.MOUSE_PRESSED,
                            650, 350, 650, 350, MouseButton.PRIMARY, 1,
                            false, false, false, false, true, false, false, false, false, true, null));
                    }
                    if (phase == 4 && now - lastSlide > 700_000_000L) {
                        lastSlide = now;
                        if (menuOpen) closeMenu.run();
                        else ((FusionButton) stage.getScene().lookup("#intro-menu-button")).getOnAction().handle(null);
                        menuOpen = !menuOpen;
                    }
                    if (previous != 0) gaps.add(now - previous);
                    if (!stage.isFocused()) ++unfocused;
                    previous = now;
                } catch (Throwable error) {
                    failure = error;
                    stop();
                    Platform.exit();
                }
            }

            void report() {
                if (phase < 0 || gaps.isEmpty()) return;
                long sum = gaps.stream().mapToLong(Long::longValue).sum();
                Collections.sort(gaps);
                System.out.printf(Locale.ROOT,
                    "MENU_PERF phase=%s intervals=%d pulse_fps=%.3f p95_ms=%.3f max_ms=%.3f unfocused=%d%n",
                    PHASES[phase], gaps.size(), gaps.size() * 1e9 / sum,
                    gaps.get((int) Math.ceil(gaps.size() * .95) - 1) / 1e6,
                    gaps.get(gaps.size() - 1) / 1e6, unfocused);
            }
        }.start();
    }

    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme());
        Application.launch(VfxMenuPerformanceProbe.class, args);
        TaskManager.get().terminate();
        GlobalScreenUtils.unregister();
        if (failure != null) throw new AssertionError(failure);
        if (!complete) throw new AssertionError("Incomplete menu profile");
        System.out.println("VFX_MENU_PERFORMANCE_PASS");
    }
}
