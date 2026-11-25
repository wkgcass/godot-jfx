import io.vproxy.vfx.intro.*;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.scene.*;
import io.vproxy.vfx.ui.button.FusionButton;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import javafx.animation.AnimationTimer;
import javafx.application.*;
import javafx.scene.*;
import javafx.scene.control.Label;
import javafx.stage.*;
import com.sun.javafx.stage.WindowHelper;
import com.sun.javafx.tk.Toolkit;
import com.sun.javafx.tk.RenderJob;
import java.util.*;

/** Observes the original six Stage factory buttons; host input performs every action. */
public class VfxStageProbe extends IntroFXMain {
    private static Throwable failure;
    private static boolean complete;
    private static int observedPhase = -1;
    private static final String[] buttons={"new VStageInitParams()","setIconifyButton(false)",
        "setMaximizeAndResetButton(false)","setCloseButton(false)","setResizable(false)","setInitialScene(...)"};
    private static void collect(Node node,List<Node> out) {
        if(!node.isVisible()) return;
        out.add(node);
        if(node instanceof Parent parent) for(var child:parent.getChildrenUnmodifiable()) collect(child,out);
    }
    private static List<Node> nodes(Window window) {
        var result=new ArrayList<Node>(); collect(window.getScene().getRoot(),result); return result;
    }
    private static Node button(Window window,String text) {
        return nodes(window).stream().filter(n->n instanceof FusionButton b && text.equals(b.getTextNode().getText())).findFirst().orElse(null);
    }
    private static long count(Window window,String type) {
        return nodes(window).stream().filter(n->n.getClass().getSimpleName().equals(type)).count();
    }
    private static void require(boolean value,String message) { if(!value) throw new AssertionError(message); }
    @Override public void start(Stage stage) {
        super.start(stage);
        try {
            var sf=IntroFXMain.class.getDeclaredField("mainScenes"); sf.setAccessible(true);
            var gf=IntroFXMain.class.getDeclaredField("sceneGroup"); gf.setAccessible(true);
            var group=(VSceneGroup)gf.get(this);
            var page=(VScene)((List<?>)sf.get(this)).get(2);
            group.show(page,VSceneShowMethod.FROM_RIGHT);
            new AnimationTimer() {
                int phase,stable; String previous="";
                long deadline=System.nanoTime()+60_000_000_000L;
                final Set<Window> observed=Collections.newSetFromMap(new WeakHashMap<>());
                @Override public void handle(long now) {
                    try {
                        if(System.nanoTime()>deadline) throw new AssertionError("VFX Stage timeout phase="+phase+" target="+previous);
                        if(group.getCurrentMainScene()!=page) return;
                        var others=Window.getWindows().stream().filter(w->w!=stage && w.isShowing()).toList();
                        require(others.size()<=1,"Unexpected extra Stage");
                        if(phase%2==0 && !others.isEmpty() || phase%2==1 && others.isEmpty()) {
                            phase++; stable=0; previous=""; deadline=System.nanoTime()+30_000_000_000L;
                        }
                        if(phase==12) { complete=true; stop(); Platform.exit(); return; }
                        int which=phase/2;
                        Window targetWindow=phase%2==0?stage:others.get(0);
                        if(observed.add(targetWindow)) {
                            targetWindow.getScene().addEventFilter(javafx.scene.input.KeyEvent.KEY_PRESSED,event->{
                                if(event.getCode()==javafx.scene.input.KeyCode.F12) {
                                    failure=new AssertionError("Host requested fixture abort"); stop(); Platform.exit();
                                }
                            });
                            targetWindow.getScene().addEventFilter(javafx.scene.input.MouseEvent.ANY,event->{
                                if(event.getEventType()==javafx.scene.input.MouseEvent.MOUSE_DRAGGED || event.getEventType()==javafx.scene.input.MouseEvent.MOUSE_PRESSED)
                                    System.out.println("VFX_MOUSE phase="+phase+" type="+event.getEventType()+" scene="+event.getSceneX()+","+event.getSceneY()+" target="+event.getTarget());
                            });
                        }
                        Node target;
                        if(phase%2==0) target=button(stage,buttons[which]);
                        else {
                            if(Math.abs(targetWindow.getWidth()-400)>1 || Math.abs(targetWindow.getHeight()-400)>1) return;
                            require(count(targetWindow,"CloseButton")== (which==3?0:1),"Close control differs "+which);
                            require(count(targetWindow,"IconifyButton")== (which==1?0:1),"Iconify control differs "+which);
                            require(count(targetWindow,"MaxResetButton")== (which==2?0:1),"Maximize control differs "+which);
                            if(which==5) require(nodes(targetWindow).stream().anyMatch(n->n instanceof Label l && "Welcome to VFX".equals(l.getText())),"Custom initial scene missing");
                            target=which==3?button(targetWindow,"close"):nodes(targetWindow).stream().filter(n->n.getClass().getSimpleName().equals("CloseButton")).findFirst().orElse(null);
                        }
                        if(target==null) return;
                        var b=target.localToScreen(target.getBoundsInLocal()); if(b==null || b.getWidth()<=0) return;
                        int x=(int)Math.round((b.getMinX()+b.getMaxX())/2-targetWindow.getX());
                        int y=(int)Math.round((b.getMinY()+b.getMaxY())/2-targetWindow.getY());
                        long id=targetWindow==stage?0:WindowHelper.getPeer(targetWindow).getRawHandle();
                        String title="VfxStage "+phase+" "+x+" "+y+" "+id;
                        observedPhase = phase;
                        if(!title.equals(previous)) { previous=title; stable=0; }
                        if(++stable==2) Platform.runLater(()->Toolkit.getToolkit().addRenderJob(new RenderJob(()->Platform.runLater(()->{
                            if(title.equals(previous) && !complete && failure==null) stage.setTitle(title);
                        }))));
                    } catch(Throwable error) { failure=error; stop(); Platform.exit(); }
                }
            }.start();
        } catch(Throwable error) { failure=error; Platform.exit(); }
    }
    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme()); Application.launch(VfxStageProbe.class,args);
        TaskManager.get().terminate(); GlobalScreenUtils.unregister();
        if(failure!=null) throw new AssertionError(failure);
        if ("1".equals(System.getenv("GODOT_JFX_VFX_ABRUPT"))) {
            require(observedPhase == 1, "Abrupt exit did not occur with the first independent Stage open");
            require(com.sun.javafx.tk.godot.GodotBridge.awaitTick(0,1) < 0, "Abrupt exit did not stop the host");
            System.out.println("VFX_STAGE_ABRUPT_RETURNED");
            return;
        }
        if(!complete) throw new AssertionError("VFX Stage sequence incomplete");
        System.out.println("VFX_STAGE_PROBE_PASS");
    }
}


