import com.sun.glass.ui.godot.GodotInputPacket;

/** Input codec boundaries only; does not change Windows settings or emit input. */
public final class ScrollSettingsProbe {
    public static void main(String[] args) {
        if (GodotInputPacket.STRIDE != 12) throw new AssertionError("Wrong input stride");
        long[] values = {0, 1, 3, 1000, 1024, 2097152, Integer.MAX_VALUE, 0x80000000L, 0xfffffffeL, 0xffffffffL};
        for (long value : values) {
            int decoded = GodotInputPacket.scrollSetting((double)value);
            if (Integer.toUnsignedLong(decoded) != value)
                throw new AssertionError("Scroll setting changed: " + value);
        }
        if (GodotInputPacket.scrollSetting(0xffffffffL) != -1)
            throw new AssertionError("Lost page-scroll sentinel");
        for (double value : new double[]{-1, 0.5, 0x1_0000_0000L, Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY}) {
            try { GodotInputPacket.scrollSetting(value); }
            catch (IllegalArgumentException expected) { continue; }
            throw new AssertionError("Malformed setting accepted: " + value);
        }
        System.out.println("SCROLL_SETTINGS_PASS");
    }
}
