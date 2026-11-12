import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

public final class ThreadStackSamplerProbe {
    static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    public static void main(String[] args) throws Exception {
        for (int period : new int[] {0, -1}) {
            try { new ThreadStackSampler(period); throw new AssertionError("Invalid period accepted"); }
            catch (IllegalArgumentException expected) {}
        }
        var captured = new CountDownLatch(1);
        var stacks = new HashMap<Thread, StackTraceElement[]>();
        var frames = new StackTraceElement[] {new StackTraceElement("java.lang.Thread", "sleep", "Thread.java", 1), new StackTraceElement("example.Scene", "paint", "Scene.java", 1)};
        for (int i = 0; i < 4200; ++i) stacks.put(new Thread("Quantum test " + i), frames);
        var sampler = new ThreadStackSampler(60_000, () -> { captured.countDown(); return stacks; });
        require(captured.await(5, TimeUnit.SECONDS), "Sampler did not start");
        var snapshot = sampler.snapshot(); // interrupts the long sleep, joins collection
        require(snapshot.size() == 4096, "Unique-stack budget not enforced");
        require(sampler.droppedSamples() == 104, "Overflow samples not reported");
        require(snapshot.stream().allMatch(sample -> sample.count() == 1 && sample.stack().contains("[NEW] <- Thread.sleep") && sample.stack().endsWith(" <- Scene.paint")),
                "Report changed or omitted captured data");
        require(snapshot.equals(sampler.snapshot()), "Stopped snapshot is unstable");
        sampler.close(); // idempotent stop

        var failed = new CountDownLatch(1);
        var broken = new ThreadStackSampler(1, () -> { failed.countDown(); throw new IllegalStateException("capture failed"); });
        require(failed.await(5, TimeUnit.SECONDS), "Failure fixture did not start");
        try { broken.snapshot(); throw new AssertionError("Sampler failure was swallowed"); }
        catch (IllegalStateException expected) {
            require(expected.getCause() != null && expected.getCause().getMessage().equals("capture failed"), "Failure cause lost");
        }
        System.out.println("THREAD_STACK_SAMPLER_PASS");
    }
}
