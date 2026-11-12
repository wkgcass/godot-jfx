import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

/** Optional diagnostic sampler. Its worker exclusively owns aggregation state. */
final class ThreadStackSampler implements AutoCloseable {
    private static final int MAX_KEYS = 4096;
    record Sample(String stack, long count) {}
    private final Map<String, Long> samples = new HashMap<>();
    private final Thread worker;
    private volatile boolean running = true;
    private volatile Throwable failure;
    private long dropped;

    ThreadStackSampler(int periodMillis) {
        this(periodMillis, Thread::getAllStackTraces);
    }

    ThreadStackSampler(int periodMillis, Supplier<Map<Thread, StackTraceElement[]>> capture) {
        if (periodMillis <= 0) throw new IllegalArgumentException("GODOT_JFX_STACK_SAMPLE must be a positive millisecond interval");
        worker = new Thread(() -> {
            try {
                while (running) {
                    for (var entry : capture.get().entrySet()) {
                        String name = entry.getKey().getName();
                        if (!name.contains("Quantum") && !name.contains("JavaFX Application") && !name.contains("Godot")) continue;
                        var frames = entry.getValue();
                        if (frames.length == 0) continue;
                        // Capture the current execution end of the stack, not
                        // only shared thread-entry callers. Keep wait/sleep frames:
                        // wall-clock samples must not disguise idle time as CPU work.
                        var key = new StringBuilder(name).append(" [").append(entry.getKey().getState()).append(']');
                        for (int i = 0; i < Math.min(frames.length, 8); ++i) {
                            String type = frames[i].getClassName();
                            key.append(" <- ").append(type, type.lastIndexOf('.') + 1, type.length())
                                    .append('.').append(frames[i].getMethodName());
                        }
                        String stack = key.toString();
                        Long count = samples.get(stack);
                        if (count != null) samples.put(stack, count + 1);
                        else if (samples.size() < MAX_KEYS) samples.put(stack, 1L);
                        else ++dropped;
                    }
                    Thread.sleep(periodMillis);
                }
            } catch (InterruptedException interrupted) {
                if (running) failure = interrupted;
                Thread.currentThread().interrupt();
            } catch (Throwable problem) {
                failure = problem; // stop; never retry a permanent failure in a tight loop
            }
        }, "stack sampler");
        worker.setDaemon(true);
        worker.start();
    }

    @Override public void close() {
        running = false;
        worker.interrupt();
        try {
            worker.join(10_000);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while stopping stack sampler", interrupted);
        }
        if (worker.isAlive()) throw new IllegalStateException("Stack sampler did not stop within 10 seconds");
        if (failure != null) throw new IllegalStateException("Stack sampling failed", failure);
    }

    List<Sample> snapshot() {
        close(); // join establishes visibility; no iteration over a changing map
        var result = new ArrayList<Sample>(samples.size());
        samples.forEach((key, count) -> result.add(new Sample(key, count)));
        result.sort((a, b) -> Long.compare(b.count(), a.count()));
        return List.copyOf(result);
    }

    long droppedSamples() {
        close();
        return dropped;
    }
}
