import com.sun.javafx.tk.godot.GodotBridge;
import javafx.application.Application;
import javafx.application.GodotRuntime;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.StackPane;
import javafx.stage.Stage;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

public final class LibraryLifecycle {
    private static GodotRuntime.Options options(String driver) {
        String project = System.getProperty("test.project");
        return new GodotRuntime.Options(project == null ? null : Path.of(project), driver, GodotRuntime.StartupWindow.HIDDEN);
    }

    private static void checkHost() {
        if (GodotRuntime.PRISM_GODOT_ENABLED || GodotBridge.hostInfo()[0] <= 0)
            throw new AssertionError("Host metadata / pre-Prism marker");
        long first = GodotBridge.awaitTick(0, 1000);
        long next = GodotBridge.awaitTick(first, 1000);
        if (first <= 0 || next <= first) throw new AssertionError("Engine loop did not advance");
        System.out.println("HOST_READY ticks=" + first + "," + next);
    }

    private static void concurrent(boolean negative) throws Exception {
        var pool = Executors.newFixedThreadPool(8);
        var gate = new CyclicBarrier(8);
        var callbacks = new AtomicInteger();
        var results = new ArrayList<Future<Throwable>>();
        try {
            for (int n = 0; n < 8; n++) {
                boolean viaToolkit = negative && n % 2 == 0;
                results.add(pool.submit(() -> {
                    gate.await();
                    try {
                        if (viaToolkit) Platform.startup(callbacks::incrementAndGet);
                        else GodotRuntime.init();
                        return null;
                    } catch (IllegalStateException error) { return error; }
                }));
            }
            Throwable first = results.getFirst().get(65, TimeUnit.SECONDS);
            for (var result : results) {
                if (result.get(2, TimeUnit.SECONDS) != first) throw new AssertionError("Waiters received different results");
            }
            if (negative) {
                if (first == null || first.getCause() == null) throw new AssertionError("Missing preserved failure");
                for (Runnable call : new Runnable[]{GodotRuntime::init, () -> Platform.startup(callbacks::incrementAndGet)}) {
                    try { call.run(); throw new AssertionError("Retry initialized"); }
                    catch (IllegalStateException observed) { if (observed != first) throw new AssertionError(observed); }
                }
                if (callbacks.get() != 0) throw new AssertionError("Failed startup ran a callback");
                System.out.println("EXPECTED_FAILURE " + first + " caused by " + first.getCause());
            } else if (first != null) throw new AssertionError(first);
        } finally { pool.shutdownNow(); }
    }

    public static void main(String[] args) throws Exception {
        switch (args[0]) {
            case "auto" -> Application.launch(DirectApplication.class);
            case "opengl" -> {
                var opts = options("opengl");
                GodotRuntime.init(new GodotRuntime.Options(opts.project(),
                        opts.driver(), GodotRuntime.StartupWindow.NORMAL));
                GodotRuntime.init();
                checkHost();
                Application.launch(DirectApplication.class);
            }
            case "race" -> {
                var first = options(null);
                var second = new GodotRuntime.Options(first.project(), first.driver(), GodotRuntime.StartupWindow.NORMAL);
                var pool = Executors.newFixedThreadPool(2);
                var gate = new CyclicBarrier(2);
                var results = new ArrayList<Future<Boolean>>();
                try {
                    for (var request : new GodotRuntime.Options[]{first, second}) {
                        results.add(pool.submit(() -> {
                            gate.await();
                            try {
                                GodotRuntime.init(request);
                                GodotRuntime.init(request);
                                return true;
                            } catch (IllegalStateException ex) {
                                if (!ex.getMessage().contains("already initialized")) throw ex;
                                return false;
                            }
                        }));
                    }
                    if (results.get(0).get(65, TimeUnit.SECONDS).equals(results.get(1).get(2, TimeUnit.SECONDS)))
                        throw new AssertionError("Conflicting startup requests did not select exactly one project");
                    GodotRuntime.init();
                    checkHost();
                } finally { pool.shutdownNow(); }
            }
            case "init", "explicit", "concurrent" -> {
                String before = DirectApplication.nativeWorkingDirectory();
                if (args[0].equals("concurrent")) concurrent(false);
                else GodotRuntime.init(options(null));
                GodotRuntime.init();
                GodotRuntime.init(options(null));
                String platformDefault = System.getProperty("os.name").startsWith("Windows") ? "d3d12" : "metal";
                String current = System.getProperty("javafx.godot.driver", platformDefault);
                String otherDriver = current.equals("opengl") ? platformDefault : "opengl";
                try { GodotRuntime.init(options(otherDriver)); throw new AssertionError("Accepted conflicting driver"); }
                catch (IllegalStateException expected) { System.out.println("CONFIG_CONFLICT " + expected.getMessage()); }
                checkHost();
                if (!before.equals(DirectApplication.nativeWorkingDirectory())) throw new AssertionError("Godot changed cwd");
                System.out.println("NATIVE_CWD " + before);
                if (args[0].equals("explicit")) Application.launch(DirectApplication.class);
            }
            case "failure" -> { concurrent(true); System.exit(31); }
            case "exit", "exit-fx" -> {
                var shown = new CompletableFuture<Void>();
                Platform.startup(() -> {
                    Stage stage = new Stage();
                    stage.setScene(new Scene(new StackPane(), 120, 90));
                    stage.show();
                    shown.complete(null);
                    if (args[0].equals("exit-fx")) {
                        System.out.println("EXPLICIT_FX_EXIT");
                        System.exit(37);
                    }
                });
                if (args[0].equals("exit-fx")) {
                    shown.get(10, TimeUnit.SECONDS);
                    return;
                }
                System.out.println("EXPLICIT_EXIT");
                System.exit(37);
            }
            case "startup" -> {
                var done = new CompletableFuture<Void>();
                Platform.startup(() -> {
                    try {
                        Platform.setImplicitExit(false);
                        Stage stage = new Stage();
                        stage.setScene(new Scene(new StackPane(), 120, 90));
                        stage.show();
                        stage.hide();
                        Platform.runLater(() -> {
                            stage.show();
                            done.complete(null);
                        });
                    } catch (Throwable cause) { done.completeExceptionally(cause); }
                });
                done.get(10, TimeUnit.SECONDS);
                try { Platform.startup(() -> {}); throw new AssertionError("Duplicate Platform.startup succeeded"); }
                catch (IllegalStateException expected) { System.out.println("PLATFORM_RESHOW_PASS"); }
                Platform.exit();
            }
            default -> throw new IllegalArgumentException(args[0]);
        }
    }
}
