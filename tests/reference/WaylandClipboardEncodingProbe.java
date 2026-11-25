package com.sun.javafx.tk.godot;

import java.awt.datatransfer.Clipboard;
import java.awt.datatransfer.ClipboardOwner;
import java.awt.datatransfer.DataFlavor;
import java.awt.datatransfer.Transferable;
import java.awt.datatransfer.UnsupportedFlavorException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Map;

public final class WaylandClipboardEncodingProbe {
    private static final class MemoryOffer extends Clipboard {
        private Map<String, byte[]> data = Map.of();

        MemoryOffer() { super("clipboard encoding test"); }

        @Override public void setContents(Transferable value, ClipboardOwner owner) {
            data = WaylandClipboard.encode(value);
        }

        @Override public Transferable getContents(Object requestor) {
            return WaylandClipboard.decode(data.keySet(), data::get);
        }

        void receiveUriList(String lines) {
            data = Map.of("text/uri-list", lines.getBytes(StandardCharsets.UTF_8));
        }
    }

    public static void main(String[] args) throws Exception {
        var offer = new MemoryOffer();
        LinuxClipboard.wayland = offer;
        LinuxClipboardInterop.publish();
        LinuxClipboardInterop.verifyPublication();

        offer.receiveUriList("# files from peer\r\nfile:///tmp/one%20file\r\nhttps://example.org/\r\n"
                + "file:%bad\r\nfile://remote.example/shared\r\nfile://localhost/tmp/%E6%96%87\r\n"
                + "file:relative\r\nfile:///tmp/%00\r\nfile:///tmp/item?query\r\n");
        if (!Arrays.equals(LinuxClipboard.files(), new String[]{"/tmp/one file", "/tmp/文"}))
            throw new AssertionError("Mixed URI list lost a local file or accepted an invalid path");

        offer.receiveUriList("https://example.org/\r\n");
        if (!"https://example.org/".equals(LinuxClipboard.url()) || LinuxClipboard.files() != null ||
                Arrays.asList(offer.getAvailableDataFlavors()).contains(DataFlavor.javaFileListFlavor) ||
                (LinuxClipboard.formats() & 16) != 0)
            throw new AssertionError("URL-only offer advertised a file list");
        try {
            offer.getData(DataFlavor.javaFileListFlavor);
            throw new AssertionError("File list returned from URL-only offer");
        } catch (UnsupportedFlavorException expected) {
            System.out.println("WAYLAND_CLIPBOARD_ENCODING_PASS");
        }
    }
}
