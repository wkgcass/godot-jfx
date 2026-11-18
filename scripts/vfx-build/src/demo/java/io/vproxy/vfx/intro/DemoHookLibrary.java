package io.vproxy.vfx.intro;

import com.github.kwhat.jnativehook.NativeLibraryLocator;
import com.github.kwhat.jnativehook.NativeSystem;
import java.io.File;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;

/** Keeps JNativeHook's keyboard-shortcut library out of the application directory. */
public final class DemoHookLibrary implements NativeLibraryLocator {
    @Override public Iterator<File> getLibraries() {
        String name = System.mapLibraryName("JNativeHook");
        String resource = "/com/github/kwhat/jnativehook/lib/" + NativeSystem.getFamily().toString().toLowerCase(Locale.ROOT)
                + "/" + NativeSystem.getArchitecture().toString().toLowerCase(Locale.ROOT) + "/" + name;
        try (var input = DemoHookLibrary.class.getResourceAsStream(resource)) {
            if (input == null) throw new IOException("Missing " + resource);
            byte[] bytes = input.readAllBytes();
            String id = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
            String override = System.getProperty("javafx.cachedir", "");
            Path cache = override.isEmpty() ? Path.of(System.getProperty("user.home"), ".openjfx", "cache") : Path.of(override);
            Path dir = Files.createDirectories(cache.resolve("jnativehook").resolve(id));
            Path target = dir.resolve(name);
            try (var channel = FileChannel.open(dir.resolve(".lock"), StandardOpenOption.CREATE, StandardOpenOption.WRITE);
                 var lock = channel.lock()) {
                if (!Files.isRegularFile(target) || Files.size(target) != bytes.length || !Arrays.equals(bytes, Files.readAllBytes(target))) {
                    Path temp = Files.createTempFile(dir, "native-", ".tmp");
                    try {
                        Files.write(temp, bytes);
                        Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING);
                    } finally {
                        Files.deleteIfExists(temp);
                    }
                }
            }
            return List.of(target.toAbsolutePath().toFile()).iterator();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        } catch (NoSuchAlgorithmException e) {
            throw new AssertionError(e);
        }
    }
}
