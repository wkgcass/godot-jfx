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

/** Secondary production Presentable, independent of still-disabled Glass popups. */
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
        run(true,() -> {
            secondary = GraphicsPipeline.getDefaultResourceFactory().createPresentable(presentableState);
            var graphics = secondary.createGraphics(); graphics.clear(com.sun.prism.paint.Color.BLUE);
            if (!secondary.prepare(null) || !secondary.present()) throw new AssertionError("Secondary publication failed");
        });
        phase(0);
        run(false,() -> state.setComposition(120,10,1,1)); phase(1);
        run(false,() -> state.setComposition(60,10,-1,1)); phase(2);
        run(false,() -> { state.setComposition(60,10,1,.5f); state.setVisible(false); }); phase(3);
        run(false,() -> state.setVisible(true)); phase(4);
        run(false,() -> state.close()); phase(5);
        run(true,() -> ((GraphicsResource)secondary).dispose());
        run(false,() -> stage.close()); waitFrames(60);
        Platform.exit();
        System.out.println("WINDOW_COMPOSITION_PROBE_PASS");
    }
}
