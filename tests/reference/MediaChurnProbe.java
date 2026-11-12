import javafx.application.*;
import javafx.animation.AnimationTimer;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.scene.media.*;
import javafx.stage.Stage;
import java.nio.file.Path;
import java.lang.management.ManagementFactory;
import java.util.HashSet;

/** Repeated native decoder/player and GPU texture lifetime, without forced GC. */
public final class MediaChurnProbe extends Application {
    private static Throwable failure;
    private static boolean complete;
    private MediaPlayer player;
    private MediaView view;
    private Pane root;
    private Stage stage;
    private AnimationTimer timer;
    // Reuse the snapshot destination so its cached RTT is not a fresh resource
    // lifetime each cycle. Player/MediaView/decoder lifetimes remain fresh.
    private final javafx.scene.image.WritableImage picture = new javafx.scene.image.WritableImage(360,200);
    private int cycle;
    private final boolean audioOnly="1".equals(System.getenv("GODOT_JFX_MEDIA_AUDIO_ONLY"));
    private final int cycles=Integer.parseInt(System.getenv().getOrDefault("GODOT_JFX_MEDIA_CYCLES","24"));
    private final int settleSeconds=Integer.parseInt(System.getenv().getOrDefault("GODOT_JFX_MEDIA_SETTLE","0"));
    private long settleStart;
    private int lastSettle=-1;
    private long deadline, next;
    private void fail(Throwable error){failure=error;Platform.exit();}
    private void create(){
        cycle++;
        stage.setTitle("MediaChurn playing "+cycle);
        Media media=new Media(Path.of(System.getenv("GODOT_JFX_MEDIA_FILE")).toUri().toString());
        media.setOnError(()->fail(media.getError()));
        player=new MediaPlayer(media);player.setMute(true);
        player.setOnError(()->fail(player.getError()));
        if(!audioOnly){
            view=new MediaView(player);view.setFitWidth(240+(cycle%3)*40);view.setFitHeight(160);view.setPreserveRatio(false);
            root.getChildren().setAll(view);
        }
        player.setOnReady(()->{
            if(audioOnly && (media.getTracks().stream().noneMatch(t->t instanceof AudioTrack)
                    || media.getTracks().stream().anyMatch(t->t instanceof VideoTrack)
                    || Math.abs(player.getTotalDuration().toMillis()-2000)>50)){
                fail(new AssertionError("Expected two-second audio-only PCM fixture"));return;
            }
            player.play();
        });
        deadline=System.nanoTime()+20_000_000_000L;
    }
    @Override public void start(Stage window){
        stage=window;root=new Pane();stage.setScene(new Scene(root,360,200));stage.show();
        try {create();} catch(Throwable error){fail(error);return;}
        timer=new AnimationTimer(){public void handle(long now){
            try {
                if(player!=null){
                    if(System.nanoTime()>deadline)throw new AssertionError("Churn decoder timeout cycle="+cycle);
                    if(player.getCurrentTime().toMillis()<1600)return;
                    if(!audioOnly){
                        view.snapshot(null,picture);
                        var colors=new HashSet<Integer>();
                        for(int y=10;y<150;y+=7)for(int x=10;x<230;x+=7)colors.add(picture.getPixelReader().getArgb(x,y));
                        if(colors.size()<80)throw new AssertionError("Missing decoded picture cycle="+cycle);
                        view.setMediaPlayer(null);root.getChildren().clear();view=null;
                    }
                    player.dispose();player=null;
                    stage.setTitle("MediaChurn drained "+cycle);
                    long heap=ManagementFactory.getMemoryMXBean().getHeapMemoryUsage().getUsed();
                    long gc=ManagementFactory.getGarbageCollectorMXBeans().stream().mapToLong(b->Math.max(0,b.getCollectionCount())).sum();
                    System.out.println("MEDIA_CHURN_JAVA cycle="+cycle+" heap_used="+heap+" gc_count="+gc);
                    CurrentProcessMemory.report(cycle);
                    next=System.nanoTime()+1_000_000_000L;
                } else if(System.nanoTime()>next){
                    if(cycle==cycles){
                        if(settleStart==0)settleStart=System.nanoTime();
                        int elapsed=(int)((System.nanoTime()-settleStart)/1_000_000_000L);
                        if(elapsed/10!=lastSettle){lastSettle=elapsed/10;CurrentProcessMemory.report("MEDIA_CHURN_IDLE",elapsed);}
                        if(elapsed>=settleSeconds){complete=true;timer.stop();Platform.exit();}
                    }else create();
                }
            }catch(Throwable error){fail(error);}
        }};timer.start();
    }
    @Override public void stop(){if(timer!=null)timer.stop();if(player!=null)player.dispose();}
    public static void main(String[] args){launch(args);if(failure!=null)throw new AssertionError("Media churn",failure);if(!complete)throw new AssertionError("Media churn incomplete");System.out.println("MEDIA_CHURN_PROBE_PASS");}
}
