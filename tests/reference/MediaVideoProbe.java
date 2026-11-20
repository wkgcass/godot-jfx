import javafx.application.*;
import javafx.animation.AnimationTimer;
import javafx.scene.*;
import javafx.scene.layout.Pane;
import javafx.scene.media.*;
import javafx.scene.image.WritableImage;
import javafx.scene.paint.Color;
import javafx.scene.shape.Rectangle;
import javafx.scene.transform.Scale;
import javafx.stage.Stage;
import javafx.util.Duration;
import javafx.embed.swing.SwingFXUtils;
import javax.imageio.ImageIO;
import java.nio.file.Path;
import java.util.HashSet;

public final class MediaVideoProbe extends Application {
    private static Throwable failure;
    private static boolean complete;
    private MediaPlayer player;
    private AnimationTimer observer;
    private int phase;
    private long pausedAt;
    private double seekTarget;
    private void fail(Throwable error) { failure=error; Platform.exit(); }

    private static WritableImage checkResizedVideo(Pane root, MediaView video) {
        // Render the paused frame on the target pixel grid by scaling the node around its origin.
        // Samples from the 320x180 snapshot may fall on different source texels.
        Scale scale = new Scale(200.0 / video.getFitWidth(), 120.0 / video.getFitHeight());
        video.getTransforms().add(scale);
        WritableImage reference = root.snapshot(null, null);
        video.getTransforms().remove(scale);
        video.setFitWidth(200);
        video.setFitHeight(120);
        WritableImage opaque = root.snapshot(null, null);
        video.setClip(new Rectangle(160, 100));
        video.setOpacity(0.5);
        WritableImage half = root.snapshot(null, null);

        int maxResizeError = 0;
        int maxBlendError = 0;
        var colors = new HashSet<Integer>();
        for (int y = 0; y < half.getHeight(); y++) {
            for (int x = 0; x < half.getWidth(); x++) {
                int scaled = reference.getPixelReader().getArgb(x, y);
                int fitted = opaque.getPixelReader().getArgb(x, y);
                int blended = half.getPixelReader().getArgb(x, y);
                boolean inside = x >= 20 && x < 180 && y >= 20 && y < 120;
                if (inside) colors.add(fitted);
                else if (blended != 0xffff00ff) throw new AssertionError("Video escaped clip at " + x + "," + y);
                for (int shift = 0; shift < 24; shift += 8) {
                    int channel = (fitted >>> shift) & 255;
                    int resizeError = Math.abs(channel - ((scaled >>> shift) & 255));
                    maxResizeError = Math.max(maxResizeError, resizeError);
                    if (resizeError > 12) throw new AssertionError("Video resize differs at " + x + "," + y + " by " + resizeError);
                    if (inside) {
                        int background = shift == 8 ? 0 : 255;
                        int expected = (channel + background) / 2;
                        int blendError = Math.abs(((blended >>> shift) & 255) - expected);
                        maxBlendError = Math.max(maxBlendError, blendError);
                        if (blendError > 12) throw new AssertionError("Video opacity differs at " + x + "," + y + " by " + blendError);
                    }
                }
            }
        }
        if (colors.size() < 100) throw new AssertionError("No decoded picture in resized clip");
        System.out.println("MEDIA_VIDEO_RESIZE_PASS max_resize_error=" + maxResizeError + " max_blend_error=" + maxBlendError);
        return half;
    }
    @Override public void start(Stage stage) {
        try {
            Media media=new Media(Path.of(System.getenv("GODOT_JFX_MEDIA_FILE")).toUri().toString());
            media.setOnError(()->fail(media.getError()));
            player=new MediaPlayer(media); player.setMute(true);
            player.setOnError(()->fail(player.getError()));
            MediaView video=new MediaView(player);
            video.setFitWidth(320); video.setFitHeight(180); video.setPreserveRatio(false);
            video.setLayoutX(20); video.setLayoutY(20);
            Pane root=new Pane(video);
            stage.setScene(new Scene(root,360,220,Color.MAGENTA)); stage.show();
            player.setOnReady(()->{
                if(media.getWidth()<1 || media.getHeight()<1) { fail(new AssertionError("No decoded video dimensions")); return; }
                System.out.println("MEDIA_VIDEO_READY width="+media.getWidth()+" height="+media.getHeight());
                player.play();
            });
            player.setOnPaused(()->{
                if(phase==1)phase=2;
                else if(phase==4)phase=5;
                else {fail(new AssertionError("Unexpected pause callback phase="+phase));return;}
                pausedAt=System.nanoTime();
            });
            player.setOnEndOfMedia(()->{
                if(phase!=7 || player.getCurrentTime().toMillis()<seekTarget){fail(new AssertionError("Unexpected video end phase="+phase));return;}
                phase=8;player.stop();
            });
            long deadline=System.nanoTime()+30_000_000_000L;
            observer=new AnimationTimer(){public void handle(long now){
                try {
                    if(System.nanoTime()>deadline) throw new AssertionError("Video timeout: "+player.getStatus()+" phase="+phase+" time="+player.getCurrentTime());
                    if(phase==0 && player.getCurrentTime().toMillis()>1600){phase=1;player.pause();}
                    if(phase==2 && System.nanoTime()-pausedAt>300_000_000L){
                        phase=3;
                        WritableImage picture=root.snapshot(null,null);
                        HashSet<Integer> colors=new HashSet<>();
                        for(int y=30;y<190;y+=3) for(int x=30;x<330;x+=3) colors.add(picture.getPixelReader().getArgb(x,y));
                        if(colors.size()<100) throw new AssertionError("Video has no decoded picture: colors="+colors.size());
                        ImageIO.write(SwingFXUtils.fromFXImage(picture,null),"png",Path.of(System.getenv("GODOT_JFX_MEDIA_CAPTURE")).toFile());
                        WritableImage resized=checkResizedVideo(root, video);
                        String capture=System.getenv("GODOT_JFX_MEDIA_CAPTURE");
                        ImageIO.write(SwingFXUtils.fromFXImage(resized,null),"png",Path.of(capture.replace(".png","-resized.png")).toFile());
                        player.play();
                    }
                    if(phase==3 && player.getCurrentTime().toMillis()>2300){phase=4;player.pause();}
                    if(phase==5 && System.nanoTime()-pausedAt>250_000_000L){
                        seekTarget=player.getTotalDuration().toMillis()-1200;
                        if(!Double.isFinite(seekTarget) || seekTarget<3000)throw new AssertionError("Invalid video duration");
                        phase=6;player.seek(Duration.millis(seekTarget));
                    }
                    if(phase==6 && Math.abs(player.getCurrentTime().toMillis()-seekTarget)<150){phase=7;player.play();}
                    if(phase==8 && player.getStatus()==MediaPlayer.Status.STOPPED && player.getCurrentTime().toMillis()<100){
                        video.setFitWidth(320);video.setFitHeight(180);video.setClip(null);video.setOpacity(1);
                        phase=9;player.play();
                    }
                    // Native playback/seek events arrive asynchronously: immediately
                    // after play(), currentTime can briefly still contain the old EOS.
                    if(phase==9 && player.getStatus()==MediaPlayer.Status.PLAYING && player.getCurrentTime().toMillis()<500)phase=10;
                    if(phase==10 && player.getCurrentTime().toMillis()>1600 && player.getCurrentTime().toMillis()<5000){
                        var replay=root.snapshot(null,null);var colors=new HashSet<Integer>();
                        for(int y=30;y<190;y+=3)for(int x=30;x<330;x+=3)colors.add(replay.getPixelReader().getArgb(x,y));
                        ImageIO.write(SwingFXUtils.fromFXImage(replay,null),"png",Path.of(System.getenv("GODOT_JFX_MEDIA_CAPTURE").replace(".png","-replay.png")).toFile());
                        if(colors.size()<100)throw new AssertionError("No decoded picture after stop/replay: colors="+colors.size()+" time="+player.getCurrentTime()+" status="+player.getStatus());
                        System.out.println("MEDIA_VIDEO_CONTROLS_PASS seek_ms="+seekTarget+" end stop replay");
                        complete=true;phase=11;observer.stop();Platform.exit();
                    }
                } catch(Throwable error){fail(error);}
            }};observer.start();
        } catch(Throwable error){fail(error);}
    }
    @Override public void stop(){if(observer!=null)observer.stop();if(player!=null)player.dispose();}
    public static void main(String[] args){launch(args);if(failure!=null)throw new AssertionError("Video failed",failure);if(!complete)throw new AssertionError("Video incomplete");System.out.println("MEDIA_VIDEO_PROBE_PASS");}
}
