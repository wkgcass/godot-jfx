import io.vproxy.vfx.intro.*;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.scene.*;
import io.vproxy.vfx.ui.button.FusionButton;
import io.vproxy.vfx.ui.loading.VProgressBar;
import io.vproxy.vfx.ui.stage.CloseButton;
import io.vproxy.vfx.manager.internal_i18n.InternalI18n;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import javafx.animation.AnimationTimer;
import javafx.application.*;
import javafx.scene.*;
import javafx.scene.control.Label;
import javafx.stage.*;
import java.util.*;
import com.sun.javafx.stage.WindowHelper;
import com.sun.javafx.tk.Toolkit;
import com.sun.javafx.tk.RenderJob;

/** Observes the original loading demo; only host mouse input invokes actions. */
public class VfxLoadingProbe extends IntroFXMain {
    private static Throwable failure;
    private static boolean complete;
    private static final boolean CANCEL="1".equals(System.getenv("GODOT_JFX_LOADING_CANCEL"));
    private static void collect(Node node,List<Node> nodes) {
        if(!node.isVisible()) return;
        nodes.add(node);
        if(node instanceof Parent parent) for(Node child:parent.getChildrenUnmodifiable()) collect(child,nodes);
    }
    private static List<Node> nodes(Window window) {
        var result=new ArrayList<Node>();collect(window.getScene().getRoot(),result);return result;
    }
    private static boolean text(Window window,String text) {
        return nodes(window).stream().anyMatch(n->n instanceof Label l && text.equals(l.getText()));
    }
    private static FusionButton button(Window window,String text) {
        return nodes(window).stream().filter(n->n instanceof FusionButton b && text.equals(b.getTextNode().getText()))
            .map(n->(FusionButton)n).findFirst().orElse(null);
    }
    @Override public void start(Stage primary) {
        super.start(primary);
        try {
            var scenesField=IntroFXMain.class.getDeclaredField("mainScenes");scenesField.setAccessible(true);
            var groupField=IntroFXMain.class.getDeclaredField("sceneGroup");groupField.setAccessible(true);
            var scenes=(List<?>)scenesField.get(this);
            var page=(VScene)scenes.stream().filter(s->s.getClass().getSimpleName().equals("_08bLoadingStageDemoScene")).findFirst().orElseThrow();
            var group=(VSceneGroup)groupField.get(this);group.show(page,VSceneShowMethod.FROM_RIGHT);
            new AnimationTimer() {
                int step,stable;
                String previous="";
                Stage loading;
                VProgressBar progressBar;
                double lastProgress=-1;
                int progressChanges;
                long alertSince, dismissedSince;
                double canceledProgress=-1;
                final Set<String> loadingLabels=new HashSet<>();
                final long deadline=System.nanoTime()+120_000_000_000L;
                @Override public void handle(long now) {
                    try {
                        if(System.nanoTime()>deadline) throw new AssertionError("Loading timeout step="+step);
                        var others=Window.getWindows().stream().filter(w->w!=primary && w.isShowing()).toList();
                        for(var window:others) if(window instanceof Stage stage && stage.getTitle().equals("LoadingStage Demo")) {
                            loading=stage;
                            for(var node:nodes(stage)) {
                                if(node instanceof Label label) loadingLabels.add(label.getText());
                                if(node instanceof VProgressBar bar) progressBar=bar;
                            }
                        }
                        if(progressBar!=null) {
                            double value=progressBar.getProgress();
                            if(value<lastProgress || value<0 || value>1) throw new AssertionError("Invalid loading progress "+value);
                            if(value!=lastProgress){progressChanges++;lastProgress=value;}
                        }
                        String resultText=CANCEL?InternalI18n.get().loadingCanceled():"loading complete";
                        if(CANCEL && others.stream().anyMatch(w->text(w,"loading complete"))) throw new AssertionError("Canceled loading completed normally");
                        Window alert=others.stream().filter(w->text(w,resultText)).findFirst().orElse(null);
                        if(step==0 && loading!=null) step=1;
                        if(step==1 && alert!=null) {
                            if(loading.isShowing()) throw new AssertionError("Loading window retained at completion");
                            if(CANCEL) {
                                if(lastProgress<0 || lastProgress>=1) throw new AssertionError("Loading was not canceled before completion");
                            } else if(loadingLabels.size()<3 || progressChanges<3 || lastProgress!=1) throw new AssertionError("Loading progress incomplete");
                            System.out.println("VFX_LOADING_PROGRESS labels="+loadingLabels.size()+" changes="+progressChanges+" final="+lastProgress);step=2;alertSince=System.nanoTime();
                        }
                        if(step==2 && CANCEL && System.nanoTime()-alertSince<500_000_000L) return;
                        if(step==2 && CANCEL && canceledProgress<0) canceledProgress=lastProgress;
                        if(step==2 && alert==null) {
                            if(CANCEL) {
                                if(dismissedSince==0) dismissedSince=System.nanoTime();
                                if(!others.isEmpty() || lastProgress!=canceledProgress) throw new AssertionError("Canceled loading resumed");
                                if(System.nanoTime()-dismissedSince<1_000_000_000L) return;
                                System.out.println("VFX_LOADING_CANCEL_SETTLED progress="+lastProgress);
                            }
                            complete=true;stop();Platform.exit();return;
                        }
                        if(group.getCurrentMainScene()!=page) return;
                        Window target=step==0?primary:step==1?loading:alert;
                        if(target==null || !target.isShowing()) return;
                        int x=0,y=0;
                        if(step!=1 || CANCEL) {
                            Node targetButton=step==1?nodes(target).stream().filter(n->n instanceof CloseButton).findFirst().orElse(null):button(target,step==0?"Open LoadingStage":"Ok");
                            if(targetButton==null) return;
                            var bounds=targetButton.localToScreen(targetButton.getBoundsInLocal());
                            if(bounds==null || bounds.getWidth()<=0) return;
                            x=(int)Math.round(bounds.getCenterX()-target.getX());
                            y=(int)Math.round(bounds.getCenterY()-target.getY());
                        }
                        long id=target==primary?0:WindowHelper.getPeer(target).getRawHandle();
                        String title="VfxLoading "+step+" "+x+" "+y+" "+id;
                        if(!title.equals(previous)){previous=title;stable=0;}
                        if(++stable==2) Platform.runLater(()->Toolkit.getToolkit().addRenderJob(new RenderJob(()->Platform.runLater(()->{
                            if(title.equals(previous)&&!complete&&failure==null){System.out.println(title);primary.setTitle(title);}
                        }))));
                    } catch(Throwable error){failure=error;stop();Platform.exit();}
                }
            }.start();
        } catch(Throwable error){failure=error;Platform.exit();}
    }
    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme());Application.launch(VfxLoadingProbe.class,args);
        TaskManager.get().terminate();GlobalScreenUtils.unregister();
        if(failure!=null) throw new AssertionError(failure);
        if(!complete) throw new AssertionError("Loading flow incomplete");
        System.out.println("VFX_LOADING_PROBE_PASS cancel="+CANCEL);
    }
}
