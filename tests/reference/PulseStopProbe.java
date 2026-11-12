import com.sun.glass.ui.godot.GodotEventLoop;
import com.sun.glass.ui.godot.GodotPulseScheduler;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

public final class PulseStopProbe {
    static void await(CountDownLatch latch) {
        try { if(!latch.await(5,TimeUnit.SECONDS)) throw new AssertionError("Latch timeout"); }
        catch(InterruptedException error) { throw new AssertionError(error); }
    }
    public static void main(String[] args) throws Exception {
        for(int run=0;run<50;run++) {
            var failure=new AtomicReference<Throwable>();
            var loop=new GodotEventLoop(failure::set);
            var held=new CountDownLatch(1); var release=new CountDownLatch(1);
            var stopped=new CountDownLatch(1); var receiverDone=new CountDownLatch(1);
            var frames=new AtomicInteger(); var waits=new AtomicInteger();
            loop.start(()->{held.countDown();await(release);}); await(held);
            // Capture the receiver thread via the source so its termination is
            // observed directly; no sleep or guessed scheduling delay is needed.
            var receiver=new AtomicReference<Thread>();
            var scheduler=new GodotPulseScheduler(loop,()->{stopped.countDown();loop.stop();},frames::incrementAndGet,
                (after,timeout)->{receiver.set(Thread.currentThread()); if(waits.incrementAndGet()==1) return 1; receiverDone.countDown(); return -1;});
            scheduler.start(); await(receiverDone); receiver.get().join(5000);
            if(receiver.get().isAlive()) throw new AssertionError("Receiver did not stop");
            release.countDown(); await(stopped); loop.thread().join(5000); scheduler.close();
            if(loop.thread().isAlive() || failure.get()!=null || frames.get()!=0)
                throw new AssertionError("Queued frame ran after host stop: "+frames+" failure="+failure.get());
        }
        System.out.println("PULSE_STOP_PROBE_PASS iterations=50");
    }
}
