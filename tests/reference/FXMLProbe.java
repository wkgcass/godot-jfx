import javafx.application.*;
import javafx.animation.AnimationTimer;
import javafx.fxml.*;
import javafx.scene.*;
import javafx.scene.control.*;
import javafx.scene.layout.VBox;
import javafx.scene.shape.Rectangle;
import javafx.scene.paint.Color;
import javafx.stage.*;
import java.net.URL;
import java.util.ResourceBundle;
import com.sun.javafx.stage.WindowHelper;
import com.sun.javafx.tk.Toolkit;
import com.sun.javafx.tk.RenderJob;

public class FXMLProbe extends Application {
    static Stage primary, child;
    static DetailController detail;
    static Throwable failure;
    static boolean complete;
    public static class FormController {
        @FXML private VBox root;
        @FXML private TextField name;
        @FXML private Button open;
        @FXML private Label heading, included;
        @FXML private Rectangle swatch;
        @FXML private URL location;
        @FXML private ResourceBundle resources;
        @FXML private void initialize() {
            if(!Platform.isFxApplicationThread() || root==null || name==null || open==null || swatch==null ||
                !"Included fragment".equals(included.getText()) || !resources.getString("heading").equals(heading.getText()) ||
                !location.toString().endsWith("form.fxml")) throw new AssertionError("FXML injection/initialize failed");
        }
        @FXML private void openDetail() {
            try {
                if(!Platform.isFxApplicationThread() || !"Godot测试".equals(name.getText()) || child!=null) throw new AssertionError("FXML action input differs");
                var loader=new FXMLLoader(FXMLProbe.class.getResource("fxml/detail.fxml"));
                Parent content=loader.load();detail=loader.getController();
                detail.message.setText("你好，"+name.getText());
                child=new Stage(StageStyle.UNDECORATED);child.initOwner(primary);child.setScene(new Scene(content));child.show();
            } catch(Throwable e){failure=e;Platform.exit();}
        }
    }
    public static class DetailController {
        @FXML private Label message;
        @FXML private Button close;
        @FXML private void initialize() {
            if(message==null || close==null || !Platform.isFxApplicationThread()) throw new AssertionError("Detail injection failed");
        }
        @FXML private void closeDetail() {
            if(!"你好，Godot测试".equals(message.getText())) {failure=new AssertionError("FXML detail text differs");Platform.exit();return;}
            complete=true;child.close();primary.close();
        }
    }
    @Override public void start(Stage stage) throws Exception {
        primary=stage;
        var loader=new FXMLLoader(getClass().getResource("fxml/form.fxml"),ResourceBundle.getBundle("fxml.messages"));
        Parent root=loader.load();FormController form=loader.getController();
        stage.initStyle(StageStyle.UNDECORATED);stage.setScene(new Scene(root));stage.show();root.applyCss();root.requestFocus();
        if(!Color.web("#336699").equals(form.swatch.getFill())) throw new AssertionError("Relative CSS resource failed");
        new AnimationTimer() {
            int step,stable;String previous="";
            final long deadline=System.nanoTime()+60_000_000_000L;
            @Override public void handle(long now) {
                try {
                    if(complete){stop();return;}
                    if(System.nanoTime()>deadline) throw new AssertionError("FXML timeout step="+step);
                    if(step==0 && form.name.isFocused()) step=1;
                    if(step==1 && form.name.getText().equals("Godot测试")) step=2;
                    if(step==2 && child!=null && child.isShowing()) step=3;
                    Window target=step==3?child:primary;
                    Node node=step==3?detail.close:step==2?form.open:form.name;
                    var b=node.localToScreen(node.getBoundsInLocal());if(b==null) return;
                    int x=(int)Math.round(b.getCenterX()-target.getX()),y=(int)Math.round(b.getCenterY()-target.getY());
                    var s=form.swatch.localToScreen(form.swatch.getBoundsInLocal());
                    long id=step==3?WindowHelper.getPeer(child).getRawHandle():0;
                    String title="FXML "+step+" "+x+" "+y+" "+id+" "+Math.round(s.getCenterX()-primary.getX())+" "+Math.round(s.getCenterY()-primary.getY());
                    if(!title.equals(previous)){previous=title;stable=0;}
                    if(++stable==2) Platform.runLater(()->Toolkit.getToolkit().addRenderJob(new RenderJob(()->Platform.runLater(()->{
                        if(title.equals(previous)&&!complete&&failure==null){primary.setTitle(title);System.out.println(title);}
                    }))));
                } catch(Throwable e){failure=e;stop();Platform.exit();}
            }
        }.start();
    }
    public static void main(String[] args) {
        launch(args);
        if(failure!=null) throw new AssertionError(failure);
        if(!complete) throw new AssertionError("FXML flow incomplete");
        System.out.println("FXML_PROBE_PASS");
    }
}
