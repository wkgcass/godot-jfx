import javafx.application.Application;
import javafx.application.Platform;
import javafx.animation.AnimationTimer;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.media.Media;
import javafx.scene.media.AudioTrack;
import javafx.scene.media.MediaPlayer;
import javafx.stage.Stage;
import javafx.util.Duration;
import java.nio.file.Path;

/** Muted WAV/MP3/AIFF fixtures exercise the source-built native playback pipeline. */
public final class MediaAudioProbe extends Application {
    private static Throwable failure;
    private static boolean complete;
    private MediaPlayer player;
    private AnimationTimer observer;
    private int phase;
    private long pausedAt;
    private double pauseTime;
    private void fail(Throwable error) {
        recordFailure(error);
        Platform.exit();
    }
    private static void recordFailure(Throwable error) {
        if (error == null) error = new AssertionError("Media error callback without an error");
        if (failure == null) failure = error;
        else if (failure != error) failure.addSuppressed(error);
    }
    private void callback(Runnable action) {
        try { action.run(); } catch (Throwable error) { fail(error); }
    }
    private double currentMillis() {
        double value = player.getCurrentTime().toMillis();
        if (!Double.isFinite(value) || value < 0) throw new AssertionError("Invalid playback clock: " + value);
        return value;
    }
    @Override public void start(Stage stage) {
        try {
            stage.setScene(new Scene(new Pane(),320,160));stage.setTitle("Media audio probe");stage.show();
            var media=new Media(Path.of(System.getenv("GODOT_JFX_MEDIA_FILE")).toUri().toString());
            media.setOnError(() -> fail(media.getError()));
            player=new MediaPlayer(media);player.setMute(true);
            player.setOnError(() -> fail(player.getError()));
            player.setOnReady(() -> {
                try {
                    long expected=Long.parseLong(System.getenv().getOrDefault("GODOT_JFX_MEDIA_EXPECT_MS","2000"));
                    long tolerance=Long.parseLong(System.getenv().getOrDefault("GODOT_JFX_MEDIA_TOLERANCE_MS","50"));
                    double duration = player.getTotalDuration().toMillis();
                    if(expected <= 0 || tolerance < 0) throw new AssertionError("Invalid duration expectation/tolerance");
                    if(!Double.isFinite(duration) || Math.abs(duration-expected)>tolerance) throw new AssertionError("Media duration differs: "+duration);
                    if(media.getTracks().stream().noneMatch(AudioTrack.class::isInstance)) throw new AssertionError("No decoded audio track");
                    System.out.println("MEDIA_AUDIO_READY tracks="+media.getTracks().size()+" duration="+(long)player.getTotalDuration().toMillis());
                    player.play();
                } catch(Throwable error) {fail(error);}
            });
            player.setOnPaused(() -> callback(() -> {pauseTime=currentMillis();pausedAt=System.nanoTime();phase=2;}));
            player.setOnEndOfMedia(() -> callback(() -> {
                if(phase!=4 || currentMillis()<1800){fail(new AssertionError("Playback ended before pause/seek/resume coverage"));return;}
                complete=true;Platform.exit();
            }));
            long deadline=System.nanoTime()+30_000_000_000L;
            observer=new AnimationTimer(){@Override public void handle(long now){
                try {
                    if(System.nanoTime()>deadline) throw new AssertionError("Media playback timeout: "+player.getStatus());
                    if(phase==0 && player.getStatus()==MediaPlayer.Status.PLAYING && currentMillis()>400){phase=1;player.pause();}
                    if(phase==2 && System.nanoTime()-pausedAt>250_000_000L){
                        if(Math.abs(currentMillis()-pauseTime)>80) throw new AssertionError("Paused clock continued");
                        phase=3;player.seek(Duration.millis(1200));
                    }
                    if(phase==3 && Math.abs(currentMillis()-1200)<100){phase=4;player.play();}
                }catch(Throwable error){fail(error);}
            }};observer.start();
        } catch(Throwable error){fail(error);}
    }
    @Override public void stop() {
        try { if(observer!=null) observer.stop(); }
        catch(Throwable error) { recordFailure(error); }
        try { if(player!=null) player.dispose(); }
        catch(Throwable error) { recordFailure(error); }
    }
    public static void main(String[] args){launch(args);if(failure!=null)throw new AssertionError("Media audio failed",failure);if(!complete)throw new AssertionError("Media audio incomplete");System.out.println("MEDIA_AUDIO_PROBE_PASS");}
}
