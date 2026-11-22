import javafx.application.*;
import javafx.animation.AnimationTimer;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.media.*;
import javafx.stage.Stage;
import java.nio.file.Path;
import java.lang.reflect.Method;
import java.util.concurrent.atomic.AtomicLong;
import com.sun.media.jfxmedia.events.NewFrameEvent;
import com.sun.media.jfxmedia.events.VideoRendererListener;
import com.sun.media.jfxmedia.control.VideoRenderControl;
import com.sun.media.jfxmedia.control.VideoDataBuffer;

/** Measures upstream media counters without snapshots in the measurement window. */
public final class MediaFrameBenchmark extends Application {
    private static Throwable failure;
    private static boolean complete;
    private MediaPlayer player;
    private AnimationTimer timer;
    private long started, ended;
    private double mediaStart;
    private int decodedStart, renderedStart, pulses, unfocused;
    private Method decoded, rendered;
    private final AtomicLong callbacks=new AtomicLong();
    private long callbacksStart;
    private volatile boolean measureTiming;
    private long previousCallback, previousPulse, previousPulseCallbacks;
    private final long[] callbackIntervals=new long[7], pulseIntervals=new long[7], callbacksPerPulse=new long[5];
    private static void interval(long[] histogram,long ns){
        double ms=ns/1e6;int bucket=ms<1?0:ms<8?1:ms<12?2:ms<20?3:ms<25?4:ms<40?5:6;
        histogram[bucket]++;
    }
    private VideoRenderControl renderControl;
    private com.sun.media.jfxmedia.MediaPlayer nativePlayer;
    private Method latestFrame;
    private final boolean measureClock="1".equals(System.getenv("GODOT_JFX_MEDIA_CLOCK"));
    private final java.util.ArrayList<Double> clockOffsets=new java.util.ArrayList<>();
    private final VideoRendererListener listener=new VideoRendererListener(){
        public synchronized void videoFrameUpdated(NewFrameEvent event){
            long now=System.nanoTime();
            if(measureTiming && previousCallback!=0)interval(callbackIntervals,now-previousCallback);
            previousCallback=now;
            if (callbacks.incrementAndGet() == 1) {
                VideoDataBuffer frame = event.getFrameData();
                System.out.println("MEDIA_FRAME_FORMAT " + frame.getFormat() + " planes=" + frame.getPlaneCount());
            }
        }
        public void releaseVideoFrames(){}
    };
    private void fail(Throwable error){failure=error;Platform.exit();}
    @Override public void start(Stage stage){
        try {
            System.out.println("MEDIA_FRAME_BACKEND glass="+com.sun.glass.ui.Application.GetApplication().getClass().getName()
                    +" prism="+com.sun.prism.GraphicsPipeline.getPipeline().getClass().getName());
            decoded=MediaView.class.getDeclaredMethod("perfGetDecodedFrameCount");decoded.setAccessible(true);
            rendered=MediaView.class.getDeclaredMethod("perfGetRenderedFrameCount");rendered.setAccessible(true);
            if(measureClock){latestFrame=MediaPlayer.class.getDeclaredMethod("getLatestFrame");latestFrame.setAccessible(true);}
            var media=new Media(Path.of(System.getenv("GODOT_JFX_MEDIA_FILE")).toUri().toString());
            media.setOnError(()->fail(media.getError()));
            player=new MediaPlayer(media);player.setMute(true);player.setOnError(()->fail(player.getError()));
            double rate=Double.parseDouble(System.getenv().getOrDefault("GODOT_JFX_MEDIA_RATE","1"));
            if(rate!=1 && rate!=2)throw new IllegalArgumentException("Benchmark rate must be 1 or 2");
            player.setRate(rate);
            var view=new MediaView(player);view.setFitWidth(640);view.setFitHeight(360);view.setPreserveRatio(false);
            stage.setScene(new Scene(new Pane(view),640,360));stage.setTitle("MediaBenchmark warmup");stage.show();
            player.setOnReady(()->{
                try {
                    if("1080p60".equals(System.getenv("GODOT_JFX_MEDIA_FIXTURE")) &&
                            (media.getWidth()!=1920 || media.getHeight()!=1080 || Math.abs(player.getTotalDuration().toMillis()-16000)>50))
                        throw new AssertionError("1080p60 fixture dimensions/duration differ");
                    System.out.printf(java.util.Locale.ROOT,"MEDIA_FRAME_SOURCE fixture=%s width=%d height=%d duration_ms=%.3f%n",
                            System.getenv().getOrDefault("GODOT_JFX_MEDIA_FIXTURE","unspecified"),media.getWidth(),media.getHeight(),player.getTotalDuration().toMillis());
                    Method retrieve=MediaPlayer.class.getDeclaredMethod("retrieveJfxPlayer");retrieve.setAccessible(true);
                    nativePlayer=(com.sun.media.jfxmedia.MediaPlayer)retrieve.invoke(player);
                    renderControl=nativePlayer.getVideoRenderControl();
                    renderControl.addVideoRendererListener(listener);player.play();
                }catch(Throwable error){fail(error);}
            });
            long deadline=System.nanoTime()+30_000_000_000L;
            timer=new AnimationTimer(){public void handle(long now){try {
                if(System.nanoTime()>deadline)throw new AssertionError("Video benchmark timeout");
                if(started==0 && player.getCurrentTime().toMillis()>2000){
                    // Verify actual decoded content before timing; no readback while measuring.
                    var picture=view.snapshot(null,null);
                    var colors=new java.util.HashSet<Integer>();
                    for(int y=10;y<350;y+=17)for(int x=10;x<630;x+=19)colors.add(picture.getPixelReader().getArgb(x,y));
                    if(colors.size()<20)throw new AssertionError("Benchmark decoded picture is missing");
                    started=System.nanoTime();decodedStart=(int)decoded.invoke(view);renderedStart=(int)rendered.invoke(view);
                    mediaStart=player.getCurrentTime().toMillis();
                    callbacksStart=callbacks.get();
                    previousPulseCallbacks=callbacksStart;measureTiming=true;
                    stage.setTitle("MediaBenchmark START");
                }
                if(started!=0 && ended==0){
                    pulses++;if(!stage.isFocused())unfocused++;
                    long pulseNow=System.nanoTime(), callbackNow=callbacks.get();
                    if(previousPulse!=0){
                        interval(pulseIntervals,pulseNow-previousPulse);
                        callbacksPerPulse[(int)Math.min(4,callbackNow-previousPulseCallbacks)]++;
                    }
                    previousPulse=pulseNow;previousPulseCallbacks=callbackNow;
                    if(measureClock){
                        // getLatestFrame holds a native frame reference. Release it
                        // even if clock sampling fails; never read pixel buffers.
                        VideoDataBuffer frame=(VideoDataBuffer)latestFrame.invoke(player);
                        if(frame!=null)try{
                            double offset=(nativePlayer.getPresentationTime()-frame.getTimestamp())*1000/rate;
                            if(!Double.isFinite(offset))throw new AssertionError("Invalid media clock sample");
                            clockOffsets.add(offset);
                        }finally{frame.releaseFrame();}
                    }
                    if(System.nanoTime()-started>=10_000_000_000L){
                        ended=System.nanoTime();
                        measureTiming=false;
                        synchronized(listener){
                            System.out.println("MEDIA_FRAME_TIMING interval_bins_ms=[1,8,12,20,25,40,infinity] callbacks="+java.util.Arrays.toString(callbackIntervals)+" pulses="+java.util.Arrays.toString(pulseIntervals)+" callbacks_per_pulse_0_1_2_3_4plus="+java.util.Arrays.toString(callbacksPerPulse));
                        }
                        int decodedFrames=(int)decoded.invoke(view)-decodedStart;
                        int renderedFrames=(int)rendered.invoke(view)-renderedStart;
                        System.out.println("MEDIA_FRAME_CALLBACKS count="+(callbacks.get()-callbacksStart));
                        double seconds=(ended-started)/1e9;
                        if(measureClock){
                            if(clockOffsets.isEmpty())throw new AssertionError("No clock/frame samples");
                            var sorted=new java.util.ArrayList<>(clockOffsets);java.util.Collections.sort(sorted);
                            int middle=clockOffsets.size()/2;
                            double first=clockOffsets.subList(0,middle).stream().mapToDouble(Double::doubleValue).average().orElseThrow();
                            double last=clockOffsets.subList(middle,clockOffsets.size()).stream().mapToDouble(Double::doubleValue).average().orElseThrow();
                            System.out.printf(java.util.Locale.ROOT,"MEDIA_FRAME_CLOCK samples=%d wall_ms_min=%.3f median=%.3f p95=%.3f max=%.3f first_half_mean=%.3f last_half_mean=%.3f%n",sorted.size(),sorted.get(0),sorted.get(sorted.size()/2),sorted.get((int)((sorted.size()-1)*.95)),sorted.get(sorted.size()-1),first,last);
                        }
                        System.out.printf(java.util.Locale.ROOT,"MEDIA_FRAME_JAVA rate=%.1f current_rate=%.1f seconds=%.6f media_ms=%.3f decoded=%d rendered=%d decoded_fps=%.3f rendered_fps=%.3f pulses=%d unfocused=%d%n",rate,player.getCurrentRate(),seconds,player.getCurrentTime().toMillis()-mediaStart,decodedFrames,renderedFrames,decodedFrames/seconds,renderedFrames/seconds,pulses,unfocused);
                        if(player.getCurrentRate()!=rate)throw new AssertionError("Requested playback rate not active");
                        if(decodedFrames<1 || renderedFrames<1)throw new AssertionError("No video frame activity");
                        stage.setTitle("MediaBenchmark END");
                    }
                }
                if(ended!=0 && System.nanoTime()-ended>500_000_000L){complete=true;Platform.exit();}
            }catch(Throwable error){fail(error);}}};timer.start();
        }catch(Throwable error){fail(error);}
    }
    @Override public void stop(){if(timer!=null)timer.stop();if(renderControl!=null)renderControl.removeVideoRendererListener(listener);if(player!=null)player.dispose();}
    public static void main(String[] args){launch(args);if(failure!=null)throw new AssertionError("Media benchmark",failure);if(!complete)throw new AssertionError("Media benchmark incomplete");System.out.println("MEDIA_FRAME_BENCHMARK_PASS");}
}
