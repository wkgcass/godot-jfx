import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.tk.godot.GodotWindowLifecycle;
import com.sun.javafx.tk.Toolkit;
import com.sun.javafx.tk.RenderJob;
import com.sun.prism.GraphicsPipeline;
import com.sun.prism.Presentable;
import com.sun.prism.PresentableState;
import com.sun.prism.GraphicsResource;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.paint.Color;
import javafx.stage.Stage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** Exercises a secondary Prism Presentable with its own native destination. */
public final class WindowCompositionProbe {
    private static Stage stage;
    private static Presentable secondary;
    private static GodotWindowLifecycle state;
    private static State presentableState;
    private static long tick;
    private static final class State extends PresentableState {
        State() {
            nativeWindowHandle = 90001; nativeView = 90002;
            viewWidth = renderWidth = outputWidth = 80;
            viewHeight = renderHeight = outputHeight = 60;
            renderScaleX = renderScaleY = outputScaleX = outputScaleY = 1;
            isWindowVisible = true;
        }
    }
    private static void waitFrames(int frames) {
        for (int i = 0; i < frames; ++i) {
            tick = GodotBridge.awaitTick(tick,1000);
            if (tick < 0) throw new AssertionError("Composition host stopped");
        }
    }
    private static void run(boolean render, Runnable action) throws Exception {
        var done = new CountDownLatch(1); var failure = new AtomicReference<Throwable>();
        Runnable wrapped = () -> { try { action.run(); } catch (Throwable t) { failure.set(t); } finally { done.countDown(); } };
        if (render) Toolkit.getToolkit().addRenderJob(new RenderJob(wrapped)); else Platform.runLater(wrapped);
        if (!done.await(10,TimeUnit.SECONDS)) throw new AssertionError("Composition action timeout");
        if (failure.get() != null) throw new AssertionError(failure.get());
    }
    private static void nativeCommand(int operation, int x, int y, int property, boolean visible) {
        long sequence = GodotBridge.nativeWindowCommand(90001, 0, operation, x, y, 80, 60, property, visible, null);
        long deadline = System.nanoTime() + 5_000_000_000L;
        while (GodotBridge.nativeWindowAck() < sequence) {
            tick = GodotBridge.awaitTick(tick, 100);
            if (tick < 0 || System.nanoTime() > deadline)
                throw new AssertionError("Native composition command timed out: " + operation);
        }
    }
    private static void configure(int offset, boolean visible) {
        int[] root = GodotBridge.hostInfo();
        nativeCommand(2, root[3] + offset, root[4] + 10, 0, visible);
    }
    private static void phase(int index) {
        waitFrames(45); GodotBridge.hostCommand(1,0,0,"Composition " + index); waitFrames(20);
        GodotBridge.hostCommand(1,0,0,"Transition");
    }
    public static void main(String[] args) throws Exception {
        var validation = GodotWindowLifecycle.create(90000,false);
        validation.setComposition(-20,30,-1,.25f);
        var before = validation.snapshot();
        boolean rejected = false;
        try { validation.setComposition(Float.NaN,0,0,1); } catch (IllegalArgumentException expected) { rejected = true; }
        if (!rejected || !validation.snapshot().equals(before)) throw new AssertionError("Invalid geometry changed snapshot");
        validation.close(); var closed = validation.snapshot();
        validation.setComposition(10,20,3,1);
        if (!validation.snapshot().equals(closed)) throw new AssertionError("Closed geometry changed");
        var ready = new CountDownLatch(1);
        Platform.startup(() -> {
            Platform.setImplicitExit(false); stage = new Stage();
            stage.setScene(new Scene(new Pane(),240,160,Color.RED)); stage.show();
            state = GodotWindowLifecycle.create(90001,false);
            presentableState = new State();
            state.setComposition(60,10,1,.5f); state.setVisible(true); ready.countDown();
        });
        if (!ready.await(10,TimeUnit.SECONDS)) throw new AssertionError("Startup timeout");
        waitFrames(60);
        nativeCommand(1, 0, 0, 3, false);
        configure(60, true);
        nativeCommand(4, 0, 0, 23, false);
        run(true,() -> {
            secondary = GraphicsPipeline.getDefaultResourceFactory().createPresentable(presentableState);
            var graphics = secondary.createGraphics(); graphics.clear(com.sun.prism.paint.Color.BLUE);
            if (!secondary.prepare(null) || !secondary.present()) throw new AssertionError("Secondary publication failed");
        });
        phase(0);
        run(false,() -> state.setComposition(120,10,1,1)); configure(120, true); phase(1);
        run(false,() -> state.setComposition(60,10,-1,1)); configure(60, true); nativeCommand(4, 0, 0, 22, false); phase(2);
        run(false,() -> { state.setComposition(60,10,1,.5f); state.setVisible(false); }); configure(60, false); phase(3);
        run(false,() -> state.setVisible(true)); configure(60, true); nativeCommand(4, 0, 0, 23, false); phase(4);
        run(false,() -> state.close()); nativeCommand(3, 0, 0, 0, false); phase(5);
        run(true,() -> ((GraphicsResource)secondary).dispose());
        run(false,() -> stage.close()); waitFrames(60);
        Platform.exit();
        System.out.println("WINDOW_COMPOSITION_PROBE_PASS");
    }
}
