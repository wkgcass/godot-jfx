import io.vproxy.vfx.intro.IntroFXMain;
import io.vproxy.vfx.intro.IntroTheme;
import io.vproxy.vfx.theme.Theme;
import io.vproxy.vfx.ui.scene.VScene;
import io.vproxy.vfx.ui.scene.VSceneGroup;
import io.vproxy.vfx.ui.scene.VSceneShowMethod;
import javafx.animation.PauseTransition;
import javafx.application.Application;
import javafx.embed.swing.SwingFXUtils;
import javafx.stage.Stage;
import javafx.util.Duration;
import javax.imageio.ImageIO;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/** Reference images only: runs unchanged VFX scenes on source-built Windows D3D. */
public class VfxReference extends Application {
    private IntroFXMain demo;
    private List<VScene> scenes;
    private VSceneGroup group;
    private Stage stage;
    private int page;
    private final Path output = Path.of("artifacts/reference/vfx-pages-d3d"+(Boolean.getBoolean("vfx.freeze.fusion")?"-frozen":""));

    @Override @SuppressWarnings("unchecked")
    public void start(Stage primary) throws Exception {
        stage = primary;
        demo = new IntroFXMain();
        demo.start(primary);
        var listField = IntroFXMain.class.getDeclaredField("mainScenes");
        listField.setAccessible(true);
        scenes = (List<VScene>) listField.get(demo);
        var groupField = IntroFXMain.class.getDeclaredField("sceneGroup");
        groupField.setAccessible(true);
        group = (VSceneGroup) groupField.get(demo);
        Files.createDirectories(output);
        Files.writeString(output.resolve("run.json"),"{\"status\":\"running\"}");
        later(5);
    }

    private void later(int seconds) {
        var pause = new PauseTransition(Duration.seconds(seconds));
        pause.setOnFinished(e -> capture());
        pause.play();
    }

    private void capture() {
        try {
            if(Boolean.getBoolean("vfx.freeze.fusion")) freezeFusion(stage.getScene().getRoot());
            double sx=stage.getOutputScaleX(), sy=stage.getOutputScaleY();
            var parameters=new javafx.scene.SnapshotParameters();
            parameters.setFill(stage.getScene().getFill());
            parameters.setTransform(new javafx.scene.transform.Scale(sx,sy));
            parameters.setViewport(new javafx.geometry.Rectangle2D(0,0,stage.getScene().getWidth()*sx,stage.getScene().getHeight()*sy));
            var image=stage.getScene().getRoot().snapshot(parameters,null);
            ImageIO.write(SwingFXUtils.fromFXImage(image, null),
                "png", output.resolve(String.format("%02d.png", page)).toFile());
            System.out.println("VFX_REFERENCE_PAGE " + page + " " + scenes.get(page).getClass().getSimpleName());
            if (++page == Math.min(scenes.size(),Integer.getInteger("vfx.reference.pages",scenes.size()))) {
                Files.writeString(output.resolve("run.json"),"{\"status\":\"passed\",\"pages\":"+page+",\"system_scale\":"+sx+"}");
                stage.fireEvent(new javafx.stage.WindowEvent(stage, javafx.stage.WindowEvent.WINDOW_CLOSE_REQUEST));
                System.out.println("VFX_REFERENCE_PASS");
            } else {
                group.show(scenes.get(page), VSceneShowMethod.FROM_RIGHT);
                later(2);
            }
        } catch (Exception failure) {
            failure.printStackTrace();
            System.exit(1);
        }
    }
    private static void freezeFusion(javafx.scene.Node node) {
        if(node instanceof io.vproxy.vfx.ui.button.FusionButton button) button.setDisableAnimation(true);
        if(node instanceof javafx.scene.Parent parent) for(var child:parent.getChildrenUnmodifiable()) freezeFusion(child);
    }

    public static void main(String[] args) {
        Theme.setTheme(new IntroTheme());
        launch(args);
    }
}
