import javafx.animation.AnimationTimer;
import javafx.animation.PauseTransition;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Label;
import javafx.scene.layout.StackPane;
import javafx.stage.Stage;
import javafx.stage.FileChooser;
import javafx.stage.DirectoryChooser;
import javafx.util.Duration;
import java.io.File;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;

public final class FileDialogProbe {
    static final CountDownLatch done=new CountDownLatch(1);
    static final AtomicReference<Throwable> failure=new AtomicReference<>();
    static int pulses;
    static final boolean stopping="1".equals(System.getenv("GODOT_JFX_DIALOG_STOP"));
    static void check(boolean value,String text) { if(!value) throw new AssertionError(text); }
    public static void main(String[] args) throws Exception {
        String token=System.getenv("GODOT_JFX_DIALOG_TOKEN");
        Path base=Path.of(FileDialogProbe.class.getProtectionDomain().getCodeSource().getLocation().toURI()).resolve("dialog-fixtures").toAbsolutePath();
        Files.createDirectories(base);
        Files.writeString(base.resolve("a.txt"),"dialog fixture a"); Files.writeString(base.resolve("b.txt"),"dialog fixture b");
        Platform.startup(() -> {
            Platform.setImplicitExit(false);
            Stage root=new Stage(), child=new Stage(); child.initOwner(root);
            root.setTitle(token+" root"); root.setScene(new Scene(new StackPane(new Label("Dialog owner")),320,180)); root.setAlwaysOnTop(true); root.show();
            child.setTitle(token+" child"); child.setScene(new Scene(new StackPane(new Label("Child owner")),240,140)); child.show();
            AnimationTimer timer=new AnimationTimer(){public void handle(long now){++pulses;}}; timer.start();
            Platform.runLater(() -> {
                try {
                    FileChooser chooser=new FileChooser(); chooser.setInitialDirectory(base.toFile());
                    var all=new FileChooser.ExtensionFilter("All files","*.*");
                    var text=new FileChooser.ExtensionFilter("Text; files", "*.txt");
                    chooser.getExtensionFilters().setAll(all,text); chooser.setSelectedExtensionFilter(text);
                    chooser.setInitialFileName("a.txt"); chooser.setTitle(token+" case 0");
                    if (stopping) {
                        check(chooser.showOpenDialog(root)==null,"Host-stop chooser did not cancel");
                        System.out.println("FILE_DIALOG_PROBE_PASS host-stop");
                        return;
                    }
                    int before=pulses;
                    File selected=chooser.showOpenDialog(root);
                    check(selected!=null && selected.toPath().equals(base.resolve("a.txt")),"Single open result differs: "+selected);
                    check(chooser.getSelectedExtensionFilter()==text,"Default/returned filter identity differs");
                    check(pulses-before>=2,"FX pulses stopped during native chooser");
                    chooser.setInitialFileName("\"a.txt\" \"b.txt\""); chooser.setTitle(token+" case 1");
                    List<File> multiple=chooser.showOpenMultipleDialog(child);
                    check(multiple!=null && new HashSet<>(multiple).equals(Set.of(base.resolve("a.txt").toFile(),base.resolve("b.txt").toFile())),"Multiple results differ: "+multiple);
                    chooser.setInitialFileName("chosen.new"); chooser.setTitle(token+" case 2");
                    selected=chooser.showSaveDialog(root);
                    check(selected!=null && selected.toPath().equals(base.resolve("chosen.new")),"Save path differs: "+selected);
                    check(!Files.exists(selected.toPath()),"Chooser wrote a file");
                    DirectoryChooser directory=new DirectoryChooser(); directory.setInitialDirectory(base.toFile()); directory.setTitle(token+" case 3");
                    selected=directory.showDialog(child);
                    check(selected!=null && selected.toPath().equals(base),"Directory result differs: "+selected);
                    chooser.setInitialFileName("a.txt"); chooser.setTitle(token+" case 4");
                    check(chooser.showOpenDialog(null)==null,"Cancel did not return null");
                    chooser.setTitle(token+" case 5");
                    PauseTransition close=new PauseTransition(Duration.seconds(2)); close.setOnFinished(e -> child.close()); close.play();
                    check(chooser.showOpenDialog(child)==null,"Owner-close did not cancel chooser");
                    check(!child.isShowing(),"Owner still showing after close");
                    System.out.println("FILE_DIALOG_PROBE_PASS cases=6 pulses="+pulses);
                } catch(Throwable error) { failure.set(error); }
                finally { try { if (Platform.isFxApplicationThread()) { timer.stop(); if (!stopping) { child.close(); root.close(); } Platform.exit(); } } finally { done.countDown(); } }
            });
        });
        if(!done.await(50,TimeUnit.SECONDS)) throw new AssertionError("Native chooser timeout");
        if(failure.get()!=null) throw new AssertionError(failure.get());
    }
}
