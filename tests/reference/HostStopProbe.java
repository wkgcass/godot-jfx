import javafx.application.Application;
import javafx.scene.Scene;
import javafx.scene.layout.StackPane;
import javafx.scene.control.Label;
import javafx.stage.Stage;

public final class HostStopProbe extends Application {
    private static java.util.List<com.sun.glass.ui.Window> peers;
    private static volatile Thread renderer;
    private static volatile com.sun.prism.godot.GodotResourceFactory factory;
    @Override public void start(Stage primary) {
        show(primary, "Host stop primary");
        Stage child = new Stage(); child.initOwner(primary);
        show(child, "Host stop child");
        Stage grandchild = new Stage(); grandchild.initOwner(child);
        show(grandchild, "Host stop grandchild");
        com.sun.javafx.tk.Toolkit.getToolkit().addRenderJob(new com.sun.javafx.tk.RenderJob(() -> {
            renderer = Thread.currentThread();
            factory = (com.sun.prism.godot.GodotResourceFactory)com.sun.prism.GraphicsPipeline.getDefaultResourceFactory();
            javafx.application.Platform.runLater(() -> primary.setTitle("Host stop ready"));
        }));
    }
    private static void show(Stage stage, String title) {
        stage.setTitle(title);
        stage.setScene(new Scene(new StackPane(new Label(title)), 260, 160));
        stage.show();
    }
    @Override public void stop() {
        peers = java.util.List.copyOf(com.sun.glass.ui.Window.getWindows());
        System.out.println("HOST_STOP_APPLICATION_STOP peers=" + peers.size());
    }
    public static void main(String[] args) throws Exception {
        launch(args);
        System.out.println("HOST_STOP_APPLICATION_RETURNED");
        if (peers == null || peers.size() != 3 || peers.stream().anyMatch(peer -> peer.getRawHandle() != 0))
            throw new AssertionError("Host stop retained Glass peers");
        System.out.println("HOST_STOP_GLASS_PEERS_CLOSED");
        renderer.join(5000);
        requireRendererDisposed();
    }
    private static void requireRendererDisposed() {
        if (renderer.isAlive() || !factory.getContext().isDisposed())
            throw new AssertionError("Renderer pipeline cleanup did not finish");
        long used = factory.getTextureResourcePool().used();
        if (used != 0) throw new AssertionError("Renderer retained texture pool bytes: " + used);
        System.out.println("HOST_STOP_PIPELINE_DISPOSED pool_bytes=" + used);
    }
}
