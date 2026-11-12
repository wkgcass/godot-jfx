import io.vproxy.vfx.intro.*;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.scene.*;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import javafx.application.*;
import javafx.animation.AnimationTimer;
import javafx.scene.*;
import javafx.scene.layout.Region;
import javafx.stage.Stage;
import com.sun.javafx.tk.Toolkit;
import com.sun.javafx.tk.RenderJob;
import com.sun.prism.GraphicsPipeline;
import com.sun.prism.godot.GodotResourceFactory;
import java.util.*;

public final class VfxScrollProbe extends IntroFXMain {
    private static Throwable failure;
    private static boolean complete;
    private static void require(boolean value,String message) {if(!value) throw new AssertionError(message);}
    private static void collect(Node node,List<Node> out) {
        out.add(node);if(node instanceof Parent p) for(Node child:p.getChildrenUnmodifiable()) collect(child,out);
    }
    @Override public void start(Stage stage) {
        super.start(stage);
        try {
            var sf=IntroFXMain.class.getDeclaredField("mainScenes");sf.setAccessible(true);
            var gf=IntroFXMain.class.getDeclaredField("sceneGroup");gf.setAccessible(true);
            var group=(VSceneGroup)gf.get(this);
            var page=(VScene)((List<?>)sf.get(this)).get(19);
            group.show(page,VSceneShowMethod.FROM_RIGHT);
            new AnimationTimer() {
                int phase,stable;String previous="";
                long deadline=System.nanoTime()+120_000_000_000L;
                @Override public void handle(long now) {
                    try {
                        require(now<deadline,"Long table timeout phase="+phase);
                        if(group.getCurrentMainScene()!=page) return;
                        // Original page has its message and the horizontal scroll root.
                        var scroll=(Region)page.getContentPane().getChildren().get(1);
                        if(scroll.getWidth()<990 || scroll.getHeight()<490) return;
                        var nodes=new ArrayList<Node>();collect(scroll,nodes);
                        var groups=nodes.stream().filter(n->n instanceof Group && n.getParent().getClip()!=null).map(n->(Group)n).toList();
                        if(groups.size()!=2) return;
                        Group horizontal=groups.get(0),vertical=groups.get(1);
                        double x=horizontal.getLayoutX(),y=vertical.getLayoutY();
                        require(vertical.getLayoutBounds().getHeight()>scroll.getHeight(),"Table does not overflow vertically");
                        boolean advance=switch(phase) {
                            case 0 -> Math.abs(x+250)<1 && Math.abs(y)<1;
                            case 1 -> Math.abs(x+250)<1 && y < -100 && Math.abs(y+vertical.getLayoutBounds().getHeight()-((Region)vertical.getParent()).getHeight())<1;
                            case 2 -> Math.abs(x+250)<1 && Math.abs(y)<1;
                            case 3 -> Math.abs(x)<1 && Math.abs(y)<1;
                            default -> false;
                        };
                        if(advance) {
                            System.out.println("VFX_SCROLL_ACTION_PASS phase="+phase+" x="+x+" y="+y);
                            phase++;stable=0;previous="";deadline=now+60_000_000_000L;
                        }
                        if(phase==4) {complete=true;stop();Platform.exit();return;}
                        var b=scroll.localToScreen(scroll.getBoundsInLocal());if(b==null) return;
                        String title="VfxScroll "+phase+" "+Math.round(b.getMinX()-stage.getX())+" "+Math.round(b.getMinY()-stage.getY())+" "+Math.round(b.getWidth())+" "+Math.round(b.getHeight());
                        if(!title.equals(previous)) {previous=title;stable=0;}
                        // runLater leaves this pulse before queuing the render-thread fence.
                        // Title commands can overtake the render queue: carry its sequence so
                        // the GPU fixture waits for the actual submission before reading pixels.
                        if(++stable==2) Platform.runLater(()->Toolkit.getToolkit().addRenderJob(new RenderJob(()->{
                            var factory=(GodotResourceFactory)GraphicsPipeline.getDefaultResourceFactory();
                            long sequence=factory.getContext().getCommands().getLastSubmittedSequence();
                            Platform.runLater(()->{
                                if(title.equals(previous) && failure==null && !complete) stage.setTitle(title+" "+sequence);
                            });
                        })));
                    } catch(Throwable error) {failure=error;stop();Platform.exit();}
                }
            }.start();
        } catch(Throwable error) {failure=error;Platform.exit();}
    }
    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme());Application.launch(VfxScrollProbe.class,args);
        TaskManager.get().terminate();GlobalScreenUtils.unregister();
        if(failure!=null) throw new AssertionError(failure);
        require(complete,"Long table scroll incomplete");System.out.println("VFX_SCROLL_PROBE_PASS");
    }
}
