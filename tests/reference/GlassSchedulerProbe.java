import com.sun.glass.ui.Application;
import com.sun.glass.ui.EventLoop;
import com.sun.glass.ui.Screen;
import com.sun.glass.ui.Timer;
import com.sun.glass.ui.godot.GodotEventLoop;
import com.sun.javafx.tk.godot.GodotBridge;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

public final class GlassSchedulerProbe {
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    private static void await(CountDownLatch latch) throws InterruptedException {
        require(latch.await(5, TimeUnit.SECONDS), "Glass callback timed out");
    }

    public static void main(String[] args) throws Exception {
        Thread bootstrap = Thread.currentThread();
        CountDownLatch ready = new CountDownLatch(1);
        Application.run(ready::countDown);
        await(ready);
        try {
            require(GodotBridge.dragTargetHandler != null, "Live application did not register drag callback");
            require(Application.GetApplication().getClass().getName().endsWith("godot.GodotApplication"), "Wrong Glass backend");
            Application.invokeAndWait(() -> {
                require(Application.isEventThread(), "Dispatch lost Glass thread identity");
                require(Thread.currentThread() != bootstrap, "User code ran on JVM bootstrap thread");
                require(Thread.currentThread().getName().equals("JavaFX Application Thread"), "Wrong event-thread name");
                require(Screen.getMainScreen().getPlatformWidth() == GodotBridge.screenInfo()[3], "Screen did not use primary monitor dimensions");
            });
            try {
                Application.invokeAndWait(() -> { throw new IllegalArgumentException("expected-probe-error"); });
                throw new AssertionError("invokeAndWait swallowed exception");
            } catch (IllegalArgumentException expected) {
                require(expected.getMessage().equals("expected-probe-error"), "Wrong propagated error");
            }
            Application.invokeAndWait(() -> {
                EventLoop outer = Application.GetApplication().createEventLoop();
                Application.invokeLater(() -> {
                    EventLoop inner = Application.GetApplication().createEventLoop();
                    Application.invokeLater(() -> {
                        outer.leave("outer"); // Non-innermost leave must defer.
                        inner.leave("inner");
                    });
                    require(inner.enter().equals("inner"), "Inner result changed");
                });
                require(outer.enter().equals("outer"), "Outer result changed");
            });

            AtomicInteger callbacks = new AtomicInteger();
            AtomicReference<Throwable> callbackFailure = new AtomicReference<>();
            AtomicReference<Timer> timer = new AtomicReference<>();
            CountDownLatch first = new CountDownLatch(3);
            Application.invokeAndWait(() -> {
                Timer created = Application.GetApplication().createTimer(() -> {
                    try { require(Application.isEventThread(), "Timer ran outside event thread"); }
                    catch (Throwable failure) { callbackFailure.set(failure); }
                    callbacks.incrementAndGet();
                    first.countDown();
                });
                timer.set(created);
                created.start(10);
            });
            await(first);
            Application.invokeAndWait(() -> timer.get().pause());
            int pausedCount = callbacks.get();
            long tick = 0;
            long pauseUntil = System.nanoTime() + 100_000_000L;
            while (System.nanoTime() < pauseUntil) tick = GodotBridge.awaitTick(tick, 1000);
            require(callbacks.get() == pausedCount, "Paused timer fired");
            Application.invokeAndWait(() -> timer.get().resume());
            long resumeDeadline = System.nanoTime() + 5_000_000_000L;
            while (callbacks.get() == pausedCount && System.nanoTime() < resumeDeadline) tick = GodotBridge.awaitTick(tick, 1000);
            Application.invokeAndWait(() -> timer.get().stop());
            require(callbacks.get() > pausedCount, "Resumed timer did not fire");
            require(callbackFailure.get() == null, "Timer thread assertion failed");
            CountDownLatch vsyncTicks = new CountDownLatch(3);
            Application.invokeAndWait(() -> {
                timer.set(Application.GetApplication().createTimer(vsyncTicks::countDown));
                timer.get().start();
            });
            await(vsyncTicks);
            Application.invokeAndWait(() -> timer.get().stop());

            // A synchronous caller queued behind a blocked task must be
            // released when the dispatcher stops, not stranded forever.
            GodotEventLoop separate = new GodotEventLoop(callbackFailure::set);
            CountDownLatch held = new CountDownLatch(1), release = new CountDownLatch(1);
            CountDownLatch callerDone = new CountDownLatch(1);
            Thread caller = new Thread(() -> {
                try {
                    separate.invokeAndWait(() -> { throw new AssertionError("Cancelled task ran"); });
                    callbackFailure.set(new AssertionError("Cancelled invokeAndWait returned success"));
                } catch (RejectedExecutionException expected) { }
                finally { callerDone.countDown(); }
            });
            try {
                separate.start(() -> {
                    held.countDown();
                    try { release.await(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
                });
                await(held);
                caller.start();
                long enqueueDeadline = System.nanoTime() + 5_000_000_000L;
                while (caller.getState() != Thread.State.WAITING && System.nanoTime() < enqueueDeadline) Thread.sleep(1);
                require(caller.getState() == Thread.State.WAITING, "Synchronous caller never queued and parked");
                separate.stop();
                await(callerDone);
            } finally {
                // Assertions and timeouts must not strand either non-daemon
                // fixture thread and prevent the JVM from reporting failure.
                separate.stop();
                release.countDown();
                separate.thread().join(5000);
                caller.join(5000);
            }
            require(!separate.thread().isAlive(), "Stopped dispatcher remained alive");
            require(!caller.isAlive(), "Synchronous caller remained alive");
            require(callbackFailure.get() == null, "Dispatcher failure: " + callbackFailure.get());
        } finally {
            // Keep the host running while Glass stops: host shutdown must not
            // be what eventually releases its idle native input waiter.
            var receivers = Thread.getAllStackTraces().keySet().stream()
                    .filter(t -> t.getName().equals("Godot input receiver")
                            || t.getName().equals("Godot frame receiver"))
                    .toList();
            require(receivers.size() == 2, "Missing Glass receiver threads");
            Application.invokeAndWait(() -> Application.GetApplication().terminate());
            require(GodotBridge.dragTargetHandler == null, "Static drag callback retained the terminated application");
            for (Thread receiver : receivers) {
                receiver.join(2500);
                require(!receiver.isAlive(), "Receiver survived Glass termination: " + receiver.getName());
            }
        }
        System.out.println("GLASS_SCHEDULER_PASS: thread isolation, nested loops, exceptions, timers, cancellation, receiver termination");
    }
}
