import java.lang.reflect.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.io.*;
import java.util.Arrays;

public final class ClipboardEncodingProbe {
    static Method encode;
    static byte[] bytes(Object value) throws Exception {
        try { return (byte[]) encode.invoke(null, "application/x-godot-custom-probe", value); }
        catch (InvocationTargetException e) {
            if (e.getCause() instanceof Error error) throw error;
            if (e.getCause() instanceof Exception exception) throw exception;
            throw e;
        }
    }
    static void check(boolean ok, String message) { if (!ok) throw new AssertionError(message); }
    public static void main(String[] args) throws Exception {
        var pixelCount = Class.forName("com.sun.glass.ui.godot.GodotSystemClipboard")
                .getDeclaredMethod("imagePixelCount", int.class, int.class);
        pixelCount.setAccessible(true);
        check((int) pixelCount.invoke(null, 1, 1) == 1, "Single pixel rejected");
        check((int) pixelCount.invoke(null, 4095, 4096) == 4095 * 4096, "Image below DIB budget rejected");
        check((int) pixelCount.invoke(null, 16384, 1) == 16384, "Maximum image dimension rejected");
        for (int[] dimensions : new int[][]{{0, 1}, {1, -1}, {16385, 1}, {1, 16385},
                {4096, 4096}, {Integer.MAX_VALUE, Integer.MAX_VALUE}}) {
            try {
                pixelCount.invoke(null, dimensions[0], dimensions[1]);
                throw new AssertionError("Invalid/oversized clipboard image accepted");
            } catch (InvocationTargetException rejected) {
                if (!(rejected.getCause() instanceof IllegalArgumentException)) throw rejected;
            }
        }
        System.out.println("CLIPBOARD_IMAGE_BUDGET_PASS");
        encode = Class.forName("com.sun.glass.ui.godot.GodotSystemClipboard").getDeclaredMethod("customBytes", String.class, Object.class);
        encode.setAccessible(true);
        check(Arrays.equals(bytes("abc"), new byte[]{97,98,99,0}), "UTF-8 terminator");
        ByteBuffer source = ByteBuffer.wrap(new byte[]{7,65,66,8}); source.position(1); source.limit(3);
        check(Arrays.equals(bytes(source), new byte[]{65,66,0}) && source.position()==1 && source.limit()==3, "Buffer slice changed");
        String value = "中文😀".repeat(12000);
        ByteArrayOutputStream serialized = new ByteArrayOutputStream();
        try (ObjectOutputStream out = new ObjectOutputStream(serialized)) { out.writeObject(value); }
        byte[] expected = value.getBytes(StandardCharsets.UTF_8);
        check(Arrays.equals(bytes(ByteBuffer.wrap(serialized.toByteArray())), Arrays.copyOf(expected, expected.length+1)), "Serialized long string changed");
        for (Object invalid : new Object[]{"", "a\0b", new byte[]{1,0,2}}) {
            try { bytes(invalid); throw new AssertionError("Invalid payload accepted"); }
            catch (IllegalArgumentException expectedFailure) { }
        }
        ByteBuffer invalidLength = ByteBuffer.allocate(13).order(ByteOrder.BIG_ENDIAN);
        invalidLength.putInt(0xACED0005).put((byte)0x7c).putLong(Long.MAX_VALUE).flip();
        try { bytes(invalidLength); throw new AssertionError("Forged long-string length accepted"); }
        catch (IllegalArgumentException expectedFailure) { }
        check(invalidLength.position()==0, "Rejected serialization was consumed");
        ByteArrayOutputStream shortString = new ByteArrayOutputStream();
        try (ObjectOutputStream out = new ObjectOutputStream(shortString)) { out.writeObject("short"); }
        check(Arrays.equals(bytes(ByteBuffer.wrap(shortString.toByteArray()).asReadOnlyBuffer()), new byte[]{115,104,111,114,116,0}), "Serialized short string changed");
        // Native memory holds the input, so the old eager heap copy cannot fit
        // under -Xmx32m. Rejection must happen before allocating that copy.
        ByteBuffer oversized = ByteBuffer.allocateDirect(64 * 1024 * 1024);
        try { bytes(oversized); throw new AssertionError("Oversized input accepted"); }
        catch (IllegalArgumentException expectedFailure) { }
        check(oversized.position()==0, "Rejected buffer was consumed");
        System.out.println("CLIPBOARD_ENCODING_PASS");
    }
}
