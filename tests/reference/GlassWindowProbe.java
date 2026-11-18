import com.sun.glass.ui.*;
import com.sun.javafx.tk.godot.GodotBridge;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/** Exercises Glass window routing without selecting a substitute Prism backend. */
public final class GlassWindowProbe {
    private static final boolean MAC = System.getProperty("os.name", "").toLowerCase().contains("mac");
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    public static void main(String[] args) throws Exception {
        CountDownLatch ready = new CountDownLatch(1);
        Application.run(ready::countDown);
        require(ready.await(5, TimeUnit.SECONDS), "Glass startup timed out");
        AtomicReference<Window> window = new AtomicReference<>();
        AtomicInteger viewEvents = new AtomicInteger();
        AtomicInteger inputIndex = new AtomicInteger();
        AtomicInteger keyIndex = new AtomicInteger();
        CountDownLatch inputDone = new CountDownLatch(1);
        CountDownLatch closeDone = new CountDownLatch(1);
        AtomicInteger boundaries = new AtomicInteger();
        AtomicInteger closeRequests = new AtomicInteger();
        try {
            Application.invokeAndWait(() -> {
                Application app = Application.GetApplication();
                Window created = app.createWindow(null, Screen.getMainScreen(), Window.TITLED);
                window.set(created);
                created.setEventHandler(new Window.EventHandler() {
                    @Override public void handleWindowEvent(Window w, long time, int type) {
                        if (type != 521) return;
                        require(Application.isEventThread(), "Close request on wrong thread");
                        require(boundaries.get() == 3, "Mouse boundary notifications missing");
                        if (closeRequests.incrementAndGet() == 1) {
                            require(!w.isClosed(), "Close request destroyed window before application decision");
                            w.setTitle("Close request vetoed");
                        } else {
                            w.close();
                            closeDone.countDown();
                        }
                    }
                });
                View view = app.createView();
                view.setEventHandler(new View.EventHandler() {
                    @Override public void handleViewEvent(View v, long time, int type) {
                        require(Application.isEventThread(), "View event on wrong thread");
                        viewEvents.incrementAndGet();
                    }
                    @Override public void handleMouseEvent(View v, long time, int type, int button,
                            int x, int y, int sx, int sy, int modifiers, boolean popup, boolean synthetic) {
                        if (type == 225 || type == 226) {
                            require(Application.isEventThread(), "Boundary event on wrong thread");
                            boundaries.getAndUpdate(value -> value | (type == 225 ? 1 : 2));
                            return;
                        }
                        if (x != 73 || y != 91) return;
                        require(Application.isEventThread(), "Mouse event on wrong thread");
                        int index = inputIndex.getAndIncrement();
                        int[] expected = {224, 221, 223, 222};
                        require(index < expected.length && type == expected[index], "Mouse event order differs: " + type);
                        require(button == (index == 0 ? 211 : 212), "Mouse button differs");
                        require(sx == 193 && sy == 191, "Screen coordinates differ");
                        require(modifiers == (index == 1 || index == 2 ? 37 : 5), "Mouse modifiers differ");
                    }
                    @Override public void handleScrollEvent(View v, long time, int x, int y, int sx, int sy,
                            double dx, double dy, int modifiers, int lines, int chars, int dl, int dc, double mx, double my) {
                        if (x != 73 || y != 91) return;
                        require(Application.isEventThread(), "Scroll on wrong thread");
                        // macOS delivers wheel ticks through the native gesture
                        // contract (kind 17); a plain scroll event must not exist.
                        require(!MAC, "macOS must deliver wheel input as a scroll gesture");
                        require(inputIndex.getAndIncrement() == 4, "Scroll order differs");
                        require(dx == 0 && dy == 0.5 && modifiers == 5, "Fractional scroll differs");
                    }
                    @Override public void handleScrollGestureEvent(View v, long time, int type, int modifiers,
                            boolean isDirect, boolean isInertia, int touchCount, int x, int y, int sx, int sy,
                            double dx, double dy, double totaldx, double totaldy, double multiplierX, double multiplierY) {
                        if (!MAC || x != 73 || y != 91) return;
                        require(Application.isEventThread(), "Scroll on wrong thread");
                        require(inputIndex.getAndIncrement() == 4, "Scroll order differs");
                        require(type == 2, "Scroll gesture type differs"); // GestureEvent.GESTURE_PERFORMED
                        require(dx == 0 && dy == 0.5 && modifiers == 5, "Fractional scroll differs");
                        require(multiplierX == 10.0 && multiplierY == 10.0, "Scroll multiplier differs");
                    }
                    @Override public boolean handleKeyEvent(View v, long time, int action, int code, char[] text, int modifiers) {
                        if (inputIndex.get() != 5) return false;
                        require(Application.isEventThread(), "Key event on wrong thread");
                        int index = keyIndex.getAndIncrement();
                        int[] actions = {111, 113, 111, 113, 112, 111, 112};
                        int[] codes = {65, 0, 65, 0, 65, 37, 37};
                        require(index < actions.length && action == actions[index] && code == codes[index], "Key sequence differs");
                        require(new String(text).equals(index < 5 ? "🧪" : ""), "Unicode key text differs");
                        require(modifiers == 0, "Key modifiers differ");
                        if (index == 6) inputDone.countDown();
                        return false;
                    }
                });
                created.setView(view);
                created.setMinimumSize(320, 240);
                created.setMaximumSize(1600, 1200);
                // This fixture checks native pixels, including absolute pointer coordinates.
                created.setPosition(120, 100);
                created.setSize(800, 480);
                created.setResizable(false);
                created.setBackground(0.12f, 0.24f, 0.36f);
                created.setCursor(app.createCursor(Cursor.CURSOR_TEXT));
                created.setVisible(true);
                created.requestFocus();
                // Last command acts as a native-side observation barrier for
                // the Godot fixture checking all previous window properties.
                created.setTitle("Godot Glass 主窗口 🧪");
            });
            long tick = 0, deadline = System.nanoTime() + 5_000_000_000L;
            while (System.nanoTime() < deadline) {
                int[] info = GodotBridge.hostInfo();
                if (info[0] == 800 && info[1] == 480 && info[3] == 120 && info[4] == 100) break;
                tick = GodotBridge.awaitTick(tick, 1000);
            }
            int[] info = GodotBridge.hostInfo();
            require(info[0] == 800 && info[1] == 480, "Godot did not resize");
            require(info[3] == 120 && info[4] == 100, "Godot did not move");
            require(info[5] > 0 && info[6] > 0, "Monitor metrics missing");
            Application.invokeAndWait(() -> {
                require(window.get().getView().getWidth() == 800, "Glass view size differs");
                require(viewEvents.get() > 0, "No Glass view events delivered");
            });
            // Let the Godot-side fixture inspect native state and rendered pixels.
            require(inputDone.await(5, TimeUnit.SECONDS), "Godot pointer/keyboard input was not delivered");
            Application.invokeAndWait(() -> { boundaries.set(0); window.get().setTitle("Input verified"); });
            require(closeDone.await(5, TimeUnit.SECONDS), "Close request callback missing");
            require(closeRequests.get() == 2, "Close veto/retry differs");
            System.out.println("GLASS_WINDOW_PASS: title, bounds, view, background, cursor, input, Unicode, boundaries and close veto/retry");
        } finally {
            Application.invokeAndWait(() -> {
                if (window.get() != null && !window.get().isClosed()) window.get().close();
                Application.GetApplication().terminate();
            });
        }
    }
}
