package com.sun.javafx.tk.godot;

import java.nio.file.Files;
import java.nio.file.Path;
import javafx.animation.AnimationTimer;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.StackPane;
import javafx.stage.Stage;

public final class WaylandClipboardInterop extends Application {
    private static final String RESPONSE = "Wayland clipboard ownership transferred";
    private static volatile Throwable failure;

    @Override public void start(Stage stage) {
        boolean owner = getParameters().getRaw().get(0).equals("owner");
        Path ready = Path.of(getParameters().getRaw().get(1));
        stage.setTitle("JavaFX Wayland clipboard " + (owner ? "owner" : "reader"));
        stage.setScene(new Scene(new StackPane(), 240, 80));
        Platform.setImplicitExit(false);
        stage.show();
        new AnimationTimer() {
            private boolean published;
            private Stage responseWindow;
            private final long deadline = System.nanoTime() + 25_000_000_000L;

            @Override public void handle(long now) {
                try {
                    if (System.nanoTime() > deadline) throw new AssertionError("Timed out waiting for clipboard exchange");
                    // A compositor can return focus to an unrelated window when the
                    // reader hides. Map a receiver once the second offer is ready.
                    if (owner && published && responseWindow == null && Files.exists(Path.of(ready + ".reply"))) {
                        responseWindow = new Stage();
                        responseWindow.setTitle("JavaFX Wayland clipboard response");
                        responseWindow.setScene(new Scene(new StackPane(), 240, 80));
                        responseWindow.show();
                    }
                    if (!(responseWindow == null ? stage : responseWindow).isFocused()) return;
                    if (owner) {
                        if (!published) {
                            LinuxClipboardInterop.publish();
                            Files.createFile(ready);
                            published = true;
                        } else if (responseWindow != null && RESPONSE.equals(LinuxClipboard.text())) {
                            System.out.println("WAYLAND_CLIPBOARD_OWNER_PASS");
                            stop();
                            Platform.exit();
                        }
                    } else if (!published) {
                        LinuxClipboardInterop.verifyPublication();
                        LinuxClipboard.write(RESPONSE, null, null, null, null, null, 0, 0, null, null);
                        published = true;
                        stage.hide();
                        Files.createFile(Path.of(ready + ".reply"));
                        // Keep serving data until the other JVM confirms ownership changed.
                    }
                } catch (Throwable error) {
                    failure = error;
                    stop();
                    Platform.exit();
                }
            }
        }.start();
        if (!owner) {
            Thread.ofPlatform().daemon().start(() -> {
                try {
                    for (int i = 0; i < 250; i++) {
                        if (Files.exists(Path.of(ready + ".ack"))) {
                            System.out.println("WAYLAND_CLIPBOARD_READER_PASS");
                            Platform.exit();
                            return;
                        }
                        Thread.sleep(100);
                    }
                    throw new AssertionError("Owner did not acknowledge the reader");
                } catch (Throwable error) {
                    failure = error;
                    Platform.exit();
                }
            });
        }
    }

    public static void main(String[] args) throws Exception {
        launch(args);
        if (failure != null) throw new AssertionError("Wayland clipboard interop", failure);
        if (args[0].equals("owner")) Files.createFile(Path.of(args[1] + ".ack"));
    }
}
