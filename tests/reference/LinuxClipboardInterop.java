package com.sun.javafx.tk.godot;

import com.sun.glass.ui.godot.GodotHtmlCodec;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

public final class LinuxClipboardInterop {
    private static final String CUSTOM = "application/x-godot-custom-linux-test";
    private static final String TEXT = "Linux 中文🙂";
    private static final String URL = "https://example.org/example";
    private static final String FILE = "/tmp/a Linux 文档.txt";

    private static void check(boolean ok, String message) {
        if (!ok) throw new AssertionError(message);
    }
    static void publish() {
        String[] files = {FILE};
        int[] pixels = {0xff428844, 0x80201008};
        byte[] custom = {42, 0};
        LinuxClipboard.write(TEXT, GodotHtmlCodec.encode("<b>中文</b>\0".getBytes(StandardCharsets.UTF_8)),
                "{\\rtf1 test}\0".getBytes(StandardCharsets.US_ASCII), URL, files,
                pixels, 2, 1, new String[]{CUSTOM}, new byte[][]{custom});
        // The peer must receive the original bytes even after the writer mutates its arrays.
        files[0] = "/tmp/changed";
        Arrays.fill(pixels, 0);
        custom[0] = 0;
    }
    static void verifyPublication() {
        check(TEXT.equals(LinuxClipboard.text()), "text");
        check(URL.equals(LinuxClipboard.url()), "URL");
        check(Arrays.equals(new String[]{FILE}, LinuxClipboard.files()), "files");
        check((LinuxClipboard.formats() & 63) == 63, "format bits: " + LinuxClipboard.formats());
        check(Arrays.asList(LinuxClipboard.customNames()).contains(CUSTOM), "custom MIME list");
        check(Arrays.equals(new byte[]{42, 0}, LinuxClipboard.customData(CUSTOM)), "custom MIME bytes");
        check(new String(GodotHtmlCodec.decode(LinuxClipboard.rich(0)), StandardCharsets.UTF_8).equals("<b>中文</b>"), "html");
        check(new String(LinuxClipboard.rich(1), StandardCharsets.US_ASCII).equals("{\\rtf1 test}\0"), "rtf");
        check(Arrays.equals(new int[]{2, 1, 0xff428844, 0x80201008}, LinuxClipboard.image()), "image");
        try {
            LinuxClipboard.write("invalid", null, null, "bad\0url", null, null, 0, 0, null, null);
            throw new AssertionError("NUL accepted");
        } catch (IllegalArgumentException expected) {
            check(TEXT.equals(LinuxClipboard.text()), "failed write changed ownership");
        }
    }
}
