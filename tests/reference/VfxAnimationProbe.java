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
import com.sun.javafx.tk.Toolkit;
import com.sun.javafx.tk.RenderJob;

/** Reads the original graph state; all selection/play/stop actions are host clicks. */
public class VfxAnimationProbe extends IntroFXMain {
    static Throwable failure;
    static boolean complete;
    static volatile long lastPulse;
    static volatile boolean observingAnimation;
    static void collect(Node node,List<Node> result) {
        result.add(node);
        if(node instanceof Parent p) for(Node child:p.getChildrenUnmodifiable()) collect(child,result);
    }
    static Object field(Node node,String name) throws Exception {
        var f=node.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(node);
    }
    @Override public void start(Stage stage) {
        super.start(stage);
        Thread watchdog=new Thread(()->{
            boolean captured=false;
            while(!captured) {
                try { Thread.sleep(250); } catch(InterruptedException ignored){return;}
                if(observingAnimation && System.nanoTime()-lastPulse>500_000_000L) {
                    captured=true;
                    System.out.println("VFX_ANIMATION_PULSE_STALL_MS "+(System.nanoTime()-lastPulse)/1_000_000);
                    Thread.getAllStackTraces().forEach((thread,stack)->{
                        if(thread.getName().contains("Quantum") || thread.getName().contains("JavaFX") || thread.getName().contains("Godot")) {
                            System.out.println("VFX_ANIMATION_THREAD "+thread.getName()+" "+thread.getState());
                            for(int i=0;i<Math.min(12,stack.length);i++)System.out.println("  "+stack[i]);
                        }
                    });
                }
            }
        },"VFX animation diagnostic");watchdog.setDaemon(true);watchdog.start();
        try {
            var sf=IntroFXMain.class.getDeclaredField("mainScenes");sf.setAccessible(true);
            var gf=IntroFXMain.class.getDeclaredField("sceneGroup");gf.setAccessible(true);
            var page=(VScene)((List<?>)sf.get(this)).stream().filter(s->s.getClass().getSimpleName().equals("_07bAnimationSystemDemoScene")).findFirst().orElseThrow();
            var group=(VSceneGroup)gf.get(this);group.show(page,VSceneShowMethod.FROM_RIGHT);
            var nodes=new ArrayList<Node>();collect(page.getContentPane(),nodes);
            var circles=new HashMap<String,Node>();
            for(var n:nodes) if(n.getClass().getSimpleName().equals("CircleBtn")) circles.put((String)field(n,"nodeName"),n);
            var buttons=new HashMap<String,FusionButton>();
            for(var n:nodes) if(n instanceof FusionButton b) buttons.put(b.getTextNode().getText(),b);
            var point=(Circle)nodes.stream().filter(n->n instanceof Circle c && c.getRadius()==10 && Color.RED.equals(c.getFill())).findFirst().orElseThrow();
            new AnimationTimer() {
                int step,stable;
                boolean moved;
                double startX,startY;
                double observedX=Double.NaN,observedY;
                long animationStart,lastAnimationPulse,maxPulseGap;
                int animationPulses;
                String previous="";
                final long deadline=System.nanoTime()+120_000_000_000L;
                void resetCheck() throws Exception {
                    if(point.isVisible() || buttons.get("play").isDisabled() || buttons.get("reset").isDisabled() || !buttons.get("soft stop").isDisabled()) throw new AssertionError("Animation controls did not reset");
                    for(var n:circles.values()) if((int)field(n,"index")!=0) throw new AssertionError("Selection did not reset");
                }
                @Override public void handle(long now) {
                    lastPulse=System.nanoTime();
                    try {
                        if(System.nanoTime()>deadline) throw new AssertionError("Animation timeout step="+step);
                        if(group.getCurrentMainScene()!=page) return;
                        if((step==0 || step==4) && (int)field(circles.get("a"),"index")==1) step++;
                        if(step==1 && (int)field(circles.get("b"),"index")==2) step=2;
                        if(step==5 && (int)field(circles.get("d"),"index")==2) step=6;
                        if((step==2 || step==6) && point.isVisible()) {
                            if(!buttons.get("play").isDisabled() || !buttons.get("reset").isDisabled() || buttons.get("soft stop").isDisabled()) throw new AssertionError("Playing controls differ");
                            startX=point.getLayoutX();startY=point.getLayoutY();moved=false;step++;
                            observingAnimation=true;
                            animationStart=lastAnimationPulse=System.nanoTime();maxPulseGap=0;animationPulses=0;
                        }
                        if(step==3 || step==7) {
                            long pulse=System.nanoTime();maxPulseGap=Math.max(maxPulseGap,pulse-lastAnimationPulse);lastAnimationPulse=pulse;animationPulses++;
                            if(point.isVisible() && (Double.isNaN(observedX) || Math.hypot(point.getLayoutX()-observedX,point.getLayoutY()-observedY)>10)) {
                                observedX=point.getLayoutX();observedY=point.getLayoutY();
                                System.out.println("VFX_ANIMATION_MODEL x="+observedX+" y="+observedY);
                            }
                            if(Math.hypot(point.getLayoutX()-startX,point.getLayoutY()-startY)>5) moved=true;
                            if(!point.isVisible()) {
                                observingAnimation=false;
                                double elapsedMs=(pulse-animationStart)/1_000_000.0;
                                System.out.println("VFX_ANIMATION_PULSE_METRICS step="+step+" callbacks="+animationPulses+" elapsed_ms="+elapsedMs+" max_gap_ms="+maxPulseGap/1_000_000.0);
                                if(!moved) throw new AssertionError("Animation point did not move");
                                resetCheck();
                                if(step==7) {
                                    var end=circles.get("d");
                                    if(Math.hypot(point.getLayoutX()-end.getLayoutX(),point.getLayoutY()-end.getLayoutY())<5) throw new AssertionError("Soft stop reached the original destination");
                                    complete=true;stop();Platform.exit();return;
                                }
                                var end=circles.get("b");
                                if(Math.hypot(point.getLayoutX()-end.getLayoutX(),point.getLayoutY()-end.getLayoutY())>0.01) throw new AssertionError("Animation did not reach selected destination");
                                System.out.println("VFX_ANIMATION_COMPLETED");step=4;
                            } else if(!moved) return;
                        }
                        Node target=switch(step) {
                            case 0,4->circles.get("a");case 1->circles.get("b");case 5->circles.get("d");
                            case 2,6->buttons.get("play");case 7->buttons.get("soft stop");default->null;
                        };
                        int x=0,y=0;
                        if(target!=null) {
                            var bounds=target.localToScreen(target.getBoundsInLocal());if(bounds==null) return;
                            x=(int)Math.round(bounds.getCenterX()-stage.getX());y=(int)Math.round(bounds.getCenterY()-stage.getY());
                        }
                        String title="VfxAnimation "+step+" "+x+" "+y;
                        if(!title.equals(previous)){previous=title;stable=0;}
                        if(++stable==2) Platform.runLater(()->Toolkit.getToolkit().addRenderJob(new RenderJob(()->Platform.runLater(()->{
                            if(title.equals(previous)&&!complete&&failure==null){stage.setTitle(title);System.out.println(title);}
                        }))));
                    } catch(Throwable e){failure=e;stop();Platform.exit();}
                }
            }.start();
        } catch(Throwable e){failure=e;Platform.exit();}
    }
    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme());Application.launch(VfxAnimationProbe.class,args);
        TaskManager.get().terminate();GlobalScreenUtils.unregister();
        if(failure!=null) throw new AssertionError(failure);
        if(!complete) throw new AssertionError("Animation sequence incomplete");
        System.out.println("VFX_ANIMATION_PROBE_PASS");
    }
}
