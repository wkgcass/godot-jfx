import com.sun.glass.ui.godot.GodotTimer;
import java.util.concurrent.atomic.AtomicInteger;

/** Deterministic host timestamps: jitter must not halve the timer frequency. */
public class TimerCadenceProbe {
    static void set(GodotTimer timer,String name,Object value) throws Exception {
        var field=GodotTimer.class.getDeclaredField(name);field.setAccessible(true);field.set(timer,value);
    }
    public static void main(String[] args) throws Exception {
        var count=new AtomicInteger();
        var timer=new GodotTimer(count::incrementAndGet,null);
        set(timer,"active",1L);set(timer,"periodNanos",16_000_000L);
        set(timer,"next",16_000_000L);set(timer,"callback",(Runnable)count::incrementAndGet);
        var fire=GodotTimer.class.getDeclaredMethod("fire",long.class);fire.setAccessible(true);
        for(long millis:new long[]{17,32,49,64}) fire.invoke(timer,millis*1_000_000L);
        if(count.get()!=4) throw new AssertionError("Jitter dropped pulses: "+count);
        fire.invoke(timer,160_000_000L);
        fire.invoke(timer,160_000_000L);
        if(count.get()!=5) throw new AssertionError("Late tick caught up more than once");
        set(timer,"paused",true);fire.invoke(timer,176_000_000L);
        set(timer,"paused",false);set(timer,"active",0L);fire.invoke(timer,192_000_000L);
        if(count.get()!=5) throw new AssertionError("Stopped/paused timer fired");
        System.out.println("TIMER_CADENCE_PROBE_PASS");
    }
}
