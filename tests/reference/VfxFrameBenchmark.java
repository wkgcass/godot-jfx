import io.vproxy.vfx.intro.*;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.scene.*;
import io.vproxy.vfx.ui.button.FusionButton;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import javafx.animation.AnimationTimer;
import javafx.application.*;
import javafx.scene.*;
import javafx.scene.shape.Circle;
import javafx.scene.paint.Color;
import javafx.stage.Stage;
import java.util.*;

/** Same original animation and actions on both pipelines. No snapshots/readbacks in timing. */
public class VfxFrameBenchmark extends IntroFXMain {
    static Throwable failure;
    static boolean complete;
    static void collect(Node node,List<Node> result) {
        result.add(node);
        if(node instanceof Parent p) for(Node child:p.getChildrenUnmodifiable()) collect(child,result);
    }
    static Object field(Object object,String name) throws Exception {
        var f=object.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(object);
    }
    @Override public void start(Stage stage) {
        super.start(stage);
        try {
            System.out.println("VFX_FRAME_BACKEND glass="+com.sun.glass.ui.Application.GetApplication().getClass().getName()
                    +" prism="+com.sun.prism.GraphicsPipeline.getPipeline().getClass().getName());
            var sf=IntroFXMain.class.getDeclaredField("mainScenes");sf.setAccessible(true);
            var gf=IntroFXMain.class.getDeclaredField("sceneGroup");gf.setAccessible(true);
            var page=(VScene)((List<?>)sf.get(this)).stream().filter(s->s.getClass().getSimpleName().equals("_07bAnimationSystemDemoScene")).findFirst().orElseThrow();
            var group=(VSceneGroup)gf.get(this);group.show(page,VSceneShowMethod.FROM_RIGHT);
            var nodes=new ArrayList<Node>();collect(page.getContentPane(),nodes);
            var circles=new HashMap<String,Node>();
            for(var n:nodes) if(n.getClass().getSimpleName().equals("CircleBtn")) circles.put((String)field(n,"nodeName"),n);
            var play=(FusionButton)nodes.stream().filter(n->n instanceof FusionButton b && b.getTextNode().getText().equals("play")).findFirst().orElseThrow();
            var point=(Circle)nodes.stream().filter(n->n instanceof Circle c && c.getRadius()==10 && Color.RED.equals(c.getFill())).findFirst().orElseThrow();
            new AnimationTimer() {
                final long started=System.nanoTime();
                final List<Long> gaps=new ArrayList<>();
                final boolean traceEnabled="1".equals(System.getenv("GODOT_JFX_BENCHMARK_TRACE"));
                final List<List<Long>> trace=new ArrayList<>();
                long traceOrigin;
                int rounds,unfocusedIntervals; boolean playing,focusRequested; long previous,finish;
                @Override public void handle(long ignored) {
                    long now=System.nanoTime();
                    try {
                        if(now-started>120_000_000_000L) throw new AssertionError("Benchmark timeout");
                        if(finish!=0) { if(now-finish>500_000_000L){complete=true;stop();Platform.exit();} return; }
                        if(now-started<3_000_000_000L || group.getCurrentMainScene()!=page) return;
                        if(!focusRequested) { stage.toFront();stage.requestFocus();focusRequested=true;return; }
                        if(playing) {
                            if(rounds>=3 && previous!=0) {
                                gaps.add(now-previous);if(!stage.isFocused()) unfocusedIntervals++;
                                if(traceEnabled) trace.add(List.of((now-traceOrigin)/1000,(now-previous)/1000,(long)rounds));
                            }
                            previous=now;
                            if(point.isVisible()) return;
                            if(Math.hypot(point.getLayoutX()-circles.get("b").getLayoutX(),point.getLayoutY()-circles.get("b").getLayoutY())>0.01) throw new AssertionError("Wrong endpoint");
                            playing=false; rounds++;
                        }
                        if(rounds==13) {
                            long sum=gaps.stream().mapToLong(Long::longValue).sum();
                            Collections.sort(gaps);
                            System.out.printf(Locale.ROOT,"VFX_FRAME_BENCHMARK rounds=10 intervals=%d pulse_fps=%.3f p50_ms=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f width=%.1f height=%.1f scale=%.2f%n",gaps.size(),gaps.size()*1e9/sum,quantile(.5),quantile(.95),quantile(.99),quantile(1),stage.getWidth(),stage.getHeight(),stage.getRenderScaleX());
                            System.out.println("VFX_FRAME_FOCUS unfocused_intervals="+unfocusedIntervals+" total_intervals="+gaps.size());
                            if(traceEnabled) System.out.println("VFX_FRAME_TRACE_JAVA "+trace);
                            stage.setTitle("VfxBenchmark END"); finish=now; return;
                        }
                        if(rounds==3) { stage.setTitle("VfxBenchmark START");traceOrigin=now; }
                        circles.get("a").getOnMouseClicked().handle(null);
                        circles.get("b").getOnMouseClicked().handle(null);
                        play.getOnAction().handle(null);
                        playing=true; previous=now;
                    } catch(Throwable e){failure=e;stop();Platform.exit();}
                }
                double quantile(double q){return gaps.get(Math.min(gaps.size()-1,(int)Math.ceil(q*gaps.size())-1))/1e6;}
            }.start();
        } catch(Throwable e){failure=e;Platform.exit();}
    }
    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme());Application.launch(VfxFrameBenchmark.class,args);
        TaskManager.get().terminate();GlobalScreenUtils.unregister();
        if(failure!=null) throw new AssertionError(failure);
        if(!complete) throw new AssertionError("Incomplete benchmark");
        System.out.println("VFX_FRAME_BENCHMARK_PASS");
    }
}
