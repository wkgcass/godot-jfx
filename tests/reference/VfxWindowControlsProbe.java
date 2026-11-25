import io.vproxy.vfx.intro.IntroTheme;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.stage.VStage;
import io.vproxy.vfx.manager.task.TaskManager;
import javafx.application.*;
import javafx.animation.AnimationTimer;
import javafx.scene.*;
import javafx.scene.control.Label;
import javafx.scene.layout.StackPane;
import javafx.stage.Stage;
import com.sun.javafx.stage.WindowHelper;
import com.sun.javafx.tk.Toolkit;
import com.sun.javafx.tk.RenderJob;

public final class VfxWindowControlsProbe extends Application {
    private static Throwable failure;
    private static boolean complete;
    private static Node find(Node node, String type) {
        if (node.getClass().getSimpleName().equals(type)) return node;
        if (node instanceof Parent parent) for (Node child : parent.getChildrenUnmodifiable()) {
            Node result = find(child,type); if (result != null) return result;
        }
        return null;
    }
    private static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    // VFX emulates maximize with manual bounds on macOS (VStage.setMaximized);
    // the underlying Stage property only tracks the native path.
    private static final boolean MAC = System.getProperty("os.name","").startsWith("Mac");
    private static final boolean WAYLAND = System.getProperty("os.name").equals("Linux");
    @Override public void start(Stage root) {
        root.setScene(new Scene(new StackPane(new Label("Independent VFX window controls")),320,180));
        root.show();
        VStage vfx = new VStage(); Stage child = vfx.getStage();
        child.setX(200); child.setY(150); child.setWidth(400); child.setHeight(300); vfx.show();
        new AnimationTimer() {
            int phase, stable; String previous = "";
            final long deadline = System.nanoTime()+45_000_000_000L;
            @Override public void handle(long now) {
                try {
                    require(now < deadline, "Window controls timeout phase="+phase+" bounds="
                            +child.getX()+","+child.getY()+" "+child.getWidth()+"x"+child.getHeight());
                    require(!root.isMaximized() && !root.isIconified(), "Child control changed primary mode");
                    if (phase==0 && (MAC ? vfx.isMaximized() : child.isMaximized())) phase=1;
                    else if (phase==1 && !(MAC ? vfx.isMaximized() : child.isMaximized())) phase=2;
                    else if (phase==2 && child.isIconified()) phase=3;
                    else if (phase==3 && !child.isIconified()) phase=4;
                    else if (phase==4 && !child.isShowing()) {
                        complete=true; stop(); root.close(); Platform.exit(); return;
                    }
                    if (phase==2 || phase==4) {
                        if (Math.abs(child.getWidth()-400)>1 || Math.abs(child.getHeight()-300)>1 ||
                                Math.abs(child.getX()-(WAYLAND ? 0 : 200))>1 ||
                                Math.abs(child.getY()-(WAYLAND ? 0 : 150))>1) return;
                    }
                    int x=0,y=0;
                    if (phase!=3) {
                        Node button=find(child.getScene().getRoot(),phase<2?"MaxResetButton":phase==2?"IconifyButton":"CloseButton");
                        require(button!=null,"Missing VFX window control");
                        var bounds=button.localToScreen(button.getBoundsInLocal()); if(bounds==null) return;
                        x=(int)Math.round((bounds.getMinX()+bounds.getMaxX())/2-child.getX());
                        y=(int)Math.round((bounds.getMinY()+bounds.getMaxY())/2-child.getY());
                    }
                    String title="VfxControls "+phase+" "+x+" "+y+" "+WindowHelper.getPeer(child).getRawHandle();
                    if(!title.equals(previous)) {previous=title;stable=0;}
                    if(++stable==2) Toolkit.getToolkit().addRenderJob(new RenderJob(()->Platform.runLater(()->{
                        if(title.equals(previous) && failure==null && !complete) root.setTitle(title);
                    })));
                } catch(Throwable error) {failure=error;stop();Platform.exit();}
            }
        }.start();
    }
    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme()); launch(args); TaskManager.get().terminate();
        if(failure!=null) throw new AssertionError(failure);
        require(complete,"Window controls incomplete");
        System.out.println("VFX_WINDOW_CONTROLS_PROBE_PASS");
    }
}
