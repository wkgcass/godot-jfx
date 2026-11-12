import io.vproxy.vfx.intro.*;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.scene.*;
import io.vproxy.vfx.ui.button.FusionButton;
import io.vproxy.vfx.ui.table.*;
import io.vproxy.vfx.manager.task.TaskManager;
import io.vproxy.vfx.control.globalscreen.GlobalScreenUtils;
import javafx.application.*;
import javafx.animation.AnimationTimer;
import javafx.scene.*;
import javafx.scene.control.*;
import javafx.stage.Stage;
import com.sun.javafx.tk.Toolkit;
import com.sun.javafx.tk.RenderJob;
import java.util.*;

public final class VfxTableProbe extends IntroFXMain {
    private static Throwable failure;
    private static boolean complete;
    private static final String EDITED="Godot测试";
    private static void require(boolean value,String message) { if(!value) throw new AssertionError(message); }
    private static void collect(Node node,List<Node> out) {
        out.add(node); if(node instanceof Parent p) for(Node child:p.getChildrenUnmodifiable()) collect(child,out);
    }
    private static FusionButton button(List<Node> nodes,String text) {
        return nodes.stream().filter(n->n instanceof FusionButton b && text.equals(b.getTextNode().getText())).map(n->(FusionButton)n).findFirst().orElseThrow();
    }
    @SuppressWarnings("unchecked")
    private static VTableView<_06bVTableViewDemoScene.Data> capturedTable(FusionButton add) throws Exception {
        for(var field:add.getClass().getDeclaredFields()) if(VTableView.class.isAssignableFrom(field.getType())) {
            field.setAccessible(true); return (VTableView<_06bVTableViewDemoScene.Data>)field.get(add);
        }
        throw new AssertionError("Original Add button does not capture its table");
    }
    @Override public void start(Stage stage) {
        super.start(stage);
        try {
            var sf=IntroFXMain.class.getDeclaredField("mainScenes"); sf.setAccessible(true);
            var gf=IntroFXMain.class.getDeclaredField("sceneGroup"); gf.setAccessible(true);
            var group=(VSceneGroup)gf.get(this);
            var page=(VScene)((List<?>)sf.get(this)).get(18);
            group.show(page,VSceneShowMethod.FROM_RIGHT);
            new AnimationTimer() {
                int phase,stable; String previous="";
                long deadline=System.nanoTime()+90_000_000_000L;
                VTableView<_06bVTableViewDemoScene.Data> table;
                _06bVTableViewDemoScene.Data edited;
                _06bVTableViewDemoScene.Data deleted;
                TextField field;
                @Override public void handle(long now) {
                    try {
                        require(now<deadline,"VFX table timeout phase="+phase+" target="+previous);
                        if(group.getCurrentMainScene()!=page) return;
                        var nodes=new ArrayList<Node>(); collect(page.getNode(),nodes);
                        if(table==null) {
                            table=capturedTable(button(nodes,"Add"));
                            require(table.getItems().size()==10,"Initial table count differs");
                            edited=table.getItems().get(0);
                            field=nodes.stream().filter(n->n instanceof TextField t && edited.name.equals(t.getText())).map(n->(TextField)n).findFirst().orElseThrow();
                        }
                        var bandwidth=table.getColumns().get(4);
                        boolean advance=switch(phase) {
                            case 0 -> table.getItems().size()==11;
                            case 1 -> table.getSelectedItem()==edited;
                            case 2 -> field.isFocused();
                            case 3 -> EDITED.equals(field.getText());
                            case 4 -> !field.isFocused() && EDITED.equals(edited.name);
                            case 5 -> bandwidth.getSortPriority()>0 && bandwidth.getSortOrder()==VTableSortOrder.ASC;
                            case 6 -> bandwidth.getSortOrder()==VTableSortOrder.DESC;
                            case 7 -> table.getItems().size()==10 && !table.getItems().contains(deleted);
                            default -> false;
                        };
                        if(advance) {
                            if(phase==5 || phase==6) {
                                int direction=phase==5?1:-1;
                                var items=table.getItems();
                                for(int i=1;i<items.size();i++) require(direction*Integer.compare(items.get(i-1).bandwidth,items.get(i).bandwidth)<=0,"Table sort order differs");
                            }
                            System.out.println("VFX_TABLE_ACTION_PASS phase="+phase+" rows="+table.getItems().size());
                            phase++; stable=0;previous="";deadline=now+45_000_000_000L;
                            if(phase==7) {deleted=table.getSelectedItem();require(deleted!=null,"No selected row to delete");}
                        }
                        if(phase==8) {require(EDITED.equals(edited.name),"Committed name lost");complete=true;stop();Platform.exit();return;}
                        Node target=switch(phase) {
                            case 0 -> button(nodes,"Add");
                            case 1 -> nodes.stream().filter(n->n instanceof Label l && edited.id.equals(l.getText())).findFirst().orElseThrow();
                            case 2,3 -> field;
                            case 4 -> nodes.stream().filter(n->n instanceof TextField && n!=field).findFirst().orElseThrow();
                            case 5,6 -> nodes.stream().filter(n->n instanceof Label l && "bandwidth".equals(l.getText())).findFirst().orElseThrow();
                            case 7 -> button(nodes,"Del");
                            default -> throw new AssertionError();
                        };
                        var bounds=target.localToScreen(target.getBoundsInLocal()); if(bounds==null || bounds.getWidth()<=0) return;
                        int x=(int)Math.round((bounds.getMinX()+bounds.getMaxX())/2-stage.getX());
                        int y=(int)Math.round((bounds.getMinY()+bounds.getMaxY())/2-stage.getY());
                        require(x>0 && y>0 && x<stage.getWidth() && y<stage.getHeight(),"Target outside window");
                        String title="VfxTable "+phase+" "+x+" "+y;
                        if(!title.equals(previous)) {previous=title;stable=0;}
                        if(++stable==2) Toolkit.getToolkit().addRenderJob(new RenderJob(()->Platform.runLater(()->{
                            if(title.equals(previous) && failure==null && !complete) stage.setTitle(title);
                        })));
                    } catch(Throwable error) {failure=error;stop();Platform.exit();}
                }
            }.start();
        } catch(Throwable error) {failure=error;Platform.exit();}
    }
    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme()); Application.launch(VfxTableProbe.class,args);
        TaskManager.get().terminate(); GlobalScreenUtils.unregister();
        if(failure!=null) throw new AssertionError(failure);
        require(complete,"VFX table interaction incomplete");
        System.out.println("VFX_TABLE_PROBE_PASS");
    }
}
