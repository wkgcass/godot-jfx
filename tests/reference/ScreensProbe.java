import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.stage.WindowHelper;
import javafx.animation.AnimationTimer;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.layout.StackPane;
import javafx.stage.Stage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class ScreensProbe {
    static final CountDownLatch done=new CountDownLatch(1);
    static final AtomicReference<Throwable> failure=new AtomicReference<>();
    static int index;
    static int[] data;
    static Stage root, child;
    static void require(boolean value,String message) { if(!value) throw new AssertionError(message); }
    static void place() {
        var screen=javafx.stage.Screen.getScreens().get(index);
        child.setX(screen.getVisualBounds().getMinX()+40); child.setY(screen.getVisualBounds().getMinY()+40);
    }
    public static void main(String[] args) throws Exception {
        Platform.startup(() -> {
            Platform.setImplicitExit(false);
            data=GodotBridge.screenInfo();
            root=new Stage(); child=new Stage();
            Button next=new Button("Next monitor");
            next.setOnAction(e -> {
                if(++index==data.length/10) { done.countDown(); return; }
                place();
            });
            root.setScene(new Scene(new StackPane(next),240,120)); root.show();
            child.setScene(new Scene(new StackPane(new Button("Monitor target")),200,100));
            place(); child.show();
            // Exercise the upstream settings notification and replacement of
            // Screen objects without changing the user's display configuration.
            com.sun.glass.ui.Screen.notifySettingsChanged();
            new AnimationTimer() {
                public void handle(long now) {
                    try {
                        if(index>=data.length/10) { stop(); return; }
                        var screens=com.sun.glass.ui.Screen.getScreens();
                        require(screens.size()==data.length/10,"Glass screen count");
                        require(javafx.stage.Screen.getScreens().size()==screens.size(),"JavaFX screen count");
                        for(int i=0;i<screens.size();++i) {
                            int n=i*10; var s=screens.get(i); var f=javafx.stage.Screen.getScreens().get(i);
                            require(s.getNativeScreen()==data[n],"Screen identity");
                            float scale=data[n+9]/96f;
                            require(s.getPlatformX()==data[n+1] && s.getPlatformY()==data[n+2] && s.getPlatformWidth()==data[n+3] && s.getPlatformHeight()==data[n+4],"Platform screen bounds");
                            require(s.getWidth()==Math.round(data[n+3]/scale) && s.getHeight()==Math.round(data[n+4]/scale),"Logical screen dimensions");
                            require(Math.abs(s.toPlatformX(s.getVisibleX())-data[n+5])<=1 && Math.abs(s.toPlatformY(s.getVisibleY())-data[n+6])<=1,"Screen work origin");
                            require(Math.abs(s.getVisibleWidth()*scale-data[n+7])<=scale && Math.abs(s.getVisibleHeight()*scale-data[n+8])<=scale,"Screen work area");
                            require(s.getResolutionX()==Math.round(data[n+9]/scale) && f.getDpi()==s.getResolutionX(),"Logical DPI metadata");
                            require(f.getOutputScaleX()==scale && s.getPlatformScaleX()==scale,"System scale");
                            require(f.getBounds().getMinX()==s.getX() && f.getVisualBounds().getWidth()==s.getVisibleWidth(),"Public Screen metadata");
                        }
                        int n=index*10;
                        long id=WindowHelper.getPeer(child).getRawHandle();
                        var peer=com.sun.glass.ui.Window.getWindows().stream().filter(w -> w.getNativeWindow()==id).findFirst().orElseThrow();
                        if(peer.getScreen()!=screens.get(index) || Math.abs(child.getX()-screens.get(index).getVisibleX()-40)>1 || Math.abs(child.getY()-screens.get(index).getVisibleY()-40)>1) return;
                        StringBuilder title=new StringBuilder("Screens ").append(index).append(' ').append(id);
                        for(int j=0;j<10;++j) title.append(' ').append(data[n+j]);
                        root.setTitle(title.toString());
                    } catch(Throwable error) { failure.set(error); stop(); done.countDown(); }
                }
            }.start();
        });
        boolean completed=done.await(30,TimeUnit.SECONDS); Platform.exit();
        if(failure.get()!=null) throw new AssertionError(failure.get());
        require(completed,"Screen enumeration/window association timed out");
        System.out.println("SCREENS_PROBE_PASS count="+data.length/10);
    }
}
