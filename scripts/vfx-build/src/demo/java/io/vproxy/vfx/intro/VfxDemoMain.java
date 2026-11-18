package io.vproxy.vfx.intro;

import io.vproxy.vfx.theme.Theme;
import javafx.animation.PauseTransition;
import javafx.application.Application;
import javafx.application.GodotRuntime;
import javafx.stage.Stage;
import javafx.stage.WindowEvent;
import javafx.util.Duration;

/** Class-path launcher for the original VFX Intro application. */
public final class VfxDemoMain {
    private static volatile boolean smokeClosed;

    public static void main(String[] args) {
        boolean smoke = false;
        boolean disableVsync = false;
        int maxFps = 0;
        String renderer = "mobile";
        var startup = GodotRuntime.StartupWindow.LOGO;
        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--renderer" -> renderer = args[++i];
                case "--no-godot-logo" -> startup = GodotRuntime.StartupWindow.HIDDEN;
                case "--disable-vsync" -> disableVsync = true;
                case "--max-fps" -> {
                    maxFps = Integer.parseInt(args[++i]);
                    if (maxFps < 0 || maxFps > 1000) throw new IllegalArgumentException("Expected 0–1000 fps");
                }
                case "--smoke" -> smoke = true;
                default -> throw new IllegalArgumentException("Unknown VFX Demo option " + args[i]);
            }
        }
        if (smoke) {
            Thread.ofPlatform().daemon().name("VFX smoke deadline").start(() -> {
                try { Thread.sleep(60_000); } catch (InterruptedException e) { return; }
                System.err.println("VFX smoke timed out");
                Runtime.getRuntime().halt(1);
            });
        }
        System.setProperty("javafx.godot.disableVsync", Boolean.toString(disableVsync));
        System.setProperty("javafx.godot.maxFps", Integer.toString(disableVsync && maxFps == 0 ? 60 : maxFps));
        if (System.getProperty("jnativehook.lib.locator") == null && System.getProperty("jnativehook.lib.path") == null) {
            System.setProperty("jnativehook.lib.locator", DemoHookLibrary.class.getName());
        }
        GodotRuntime.init(new GodotRuntime.Options(null, renderer, startup));
        if (smoke) {
            Theme.setTheme(new IntroTheme());
            Application.launch(SmokeIntro.class);
            if (!smokeClosed) throw new IllegalStateException("VFX Intro closed before smoke verification");
        } else {
            IntroMain.main(new String[0]);
        }
        System.out.println("VFX_DEMO_CLOSED");
    }

    public static final class SmokeIntro extends IntroFXMain {
        @Override public void start(Stage stage) {
            super.start(stage);
            PauseTransition delay = new PauseTransition(Duration.seconds(10));
            delay.setOnFinished(event -> {
                if (!stage.isShowing() || !stage.getTitle().startsWith("VFX Intro")
                        || stage.getScene().getRoot().lookup("#intro-menu-button") == null) {
                    throw new IllegalStateException("VFX Intro window or navigation missing");
                }
                stage.fireEvent(new WindowEvent(stage, WindowEvent.WINDOW_CLOSE_REQUEST));
                smokeClosed = !stage.isShowing();
            });
            delay.play();
        }
    }
}
