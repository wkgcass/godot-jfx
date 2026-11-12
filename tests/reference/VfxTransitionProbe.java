import io.vproxy.vfx.intro.*;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.scene.*;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import javafx.animation.AnimationTimer;
import javafx.application.*;
import javafx.stage.Stage;
import java.util.*;

/** Drives the Demo's own next/prev transitions and times pulse cadence during each. */
public class VfxTransitionProbe extends IntroFXMain {
    static Throwable failure;
    static boolean complete;
    static ThreadStackSampler sampler;
    static void startSampler() {
        String configured = System.getenv("GODOT_JFX_STACK_SAMPLE");
        if (configured == null || configured.isBlank()) return;
        int period;
        try { period = Integer.parseInt(configured); }
        catch (NumberFormatException invalid) { throw new IllegalArgumentException("Invalid GODOT_JFX_STACK_SAMPLE: " + configured, invalid); }
        sampler = new ThreadStackSampler(period);
        System.out.println("VFX_TRANSITION_SAMPLING period_ms=" + period + " diagnostic_only=true");
    }
    static void stopSamplerAndReport() {
        if (sampler == null) return;
        var entries = sampler.snapshot();
        for (int i = 0; i < Math.min(40, entries.size()); ++i)
            System.out.println("VFX_TRANSITION_SAMPLE " + entries.get(i).count() + " " + entries.get(i).stack());
        System.out.println("VFX_TRANSITION_SAMPLE_DROPPED " + sampler.droppedSamples());
    }
    @Override public void start(Stage stage) {
        super.start(stage);
        try {
            startSampler();
            System.out.println("VFX_TRANSITION_BACKEND glass="+com.sun.glass.ui.Application.GetApplication().getClass().getName()
                    +" prism="+com.sun.prism.GraphicsPipeline.getPipeline().getClass().getName());
            var sf=IntroFXMain.class.getDeclaredField("mainScenes");sf.setAccessible(true);
            var gf=IntroFXMain.class.getDeclaredField("sceneGroup");gf.setAccessible(true);
            var scenes=(List<VScene>)sf.get(this);
            var group=(VSceneGroup)gf.get(this);
            new AnimationTimer() {
                final long started=System.nanoTime();
                final List<int[]> plan=new ArrayList<>();
                final List<List<Long>> transitions=new ArrayList<>();
                final List<String> names=new ArrayList<>();
                final List<Long> all=new ArrayList<>();
                List<Long> current; long transitionStart,previous,finish; int target=-1,unfocused; boolean focusRequested,measuring;
                { for(int i=1;i<scenes.size();++i) plan.add(new int[]{i,1}); for(int i=scenes.size()-2;i>=0;--i) plan.add(new int[]{i,0}); }
                @Override public void handle(long now) {
                    try {
                        if(now-started>240_000_000_000L) throw new AssertionError("Transition benchmark timeout");
                        if(finish!=0) { if(now-finish>500_000_000L){complete=true;stop();Platform.exit();} return; }
                        if(now-started<3_000_000_000L) return;
                        if(!focusRequested) { stage.toFront();stage.requestFocus();focusRequested=true;return; }
                        if(target<0) {
                            if(plan.isEmpty()) { report(stage); stage.setTitle("VfxTransition END"); finish=now; return; }
                            int[] step=plan.remove(0);
                            target=step[0];
                            if(!measuring) { stage.setTitle("VfxTransition START"); measuring=true; }
                            names.add((step[1]==1?"R":"L")+target+":"+scenes.get(target).getClass().getSimpleName());
                            current=new ArrayList<>();
                            group.show(scenes.get(target),step[1]==1?VSceneShowMethod.FROM_RIGHT:VSceneShowMethod.FROM_LEFT);
                            transitionStart=now; previous=now; return;
                        }
                        if(now-transitionStart>15_000_000_000L) throw new AssertionError("Transition stuck: "+names.get(names.size()-1));
                        current.add(now-previous); if(!stage.isFocused()) unfocused++;
                        previous=now;
                        if(group.getCurrentMainScene()==scenes.get(target)) { transitions.add(current); target=-1; }
                    } catch(Throwable e){failure=e;stop();Platform.exit();}
                }
                void report(Stage stage) {
                    double worstFps=Double.MAX_VALUE; String worstName="";
                    for(int i=0;i<transitions.size();++i) {
                        var gaps=new ArrayList<>(transitions.get(i));
                        if(gaps.isEmpty()) { System.out.println("VFX_TRANSITION "+names.get(i)+" pulses=0"); continue; }
                        Collections.sort(gaps);
                        long sum=gaps.stream().mapToLong(Long::longValue).sum();
                        double fps=gaps.size()*1e9/sum;
                        if(fps<worstFps) { worstFps=fps; worstName=names.get(i); }
                        all.addAll(gaps);
                        System.out.printf(Locale.ROOT,"VFX_TRANSITION %s pulses=%d fps=%.3f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f%n",names.get(i),gaps.size(),fps,q(gaps,.5),q(gaps,.95),q(gaps,1));
                    }
                    Collections.sort(all);
                    long sum=all.stream().mapToLong(Long::longValue).sum();
                    System.out.printf(Locale.ROOT,"VFX_TRANSITION_SUMMARY transitions=%d pulse_fps=%.3f p50_ms=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f unfocused=%d worst=%s@%.3f%n",
                            transitions.size(),all.size()*1e9/sum,q(all,.5),q(all,.95),q(all,.99),q(all,1),unfocused,worstName,worstFps);
                }
                double q(List<Long> gaps,double quantile){return gaps.get(Math.min(gaps.size()-1,(int)Math.ceil(quantile*gaps.size())-1))/1e6;}
            }.start();
        } catch(Throwable e){failure=e;Platform.exit();}
    }
    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme());
        try {
            Application.launch(VfxTransitionProbe.class,args);
        } finally {
            try { if (sampler != null) sampler.close(); }
            finally {
                try { TaskManager.get().terminate(); }
                finally { GlobalScreenUtils.unregister(); }
            }
        }
        stopSamplerAndReport();
        if(failure!=null) throw new AssertionError(failure);
        if(!complete) throw new AssertionError("Incomplete transition benchmark");
        try {
            var field = Class.forName("com.sun.prism.impl.ps.BaseShaderContext").getField("TARGET_SWITCHES");
            System.out.println("VFX_TRANSITION_TARGET_SWITCHES " + ((java.util.concurrent.atomic.AtomicLong) field.get(null)).get());
        } catch (ReflectiveOperationException unavailable) { System.out.println("VFX_TRANSITION_TARGET_SWITCHES unavailable"); }
        System.out.println("VFX_TRANSITION_BENCHMARK_PASS");
    }
}
