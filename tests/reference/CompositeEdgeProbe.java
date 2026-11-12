import javafx.application.Platform;
import com.sun.javafx.tk.Toolkit;
import com.sun.javafx.tk.RenderJob;
import com.sun.prism.*;
import com.sun.prism.paint.Color;
import java.nio.IntBuffer;
import java.nio.file.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;

/** Identical low-level Prism operations on source-built D3D and Godot. */
public final class CompositeEdgeProbe {
    public static void main(String[] args) throws Exception {
        var done=new CountDownLatch(1);
        var failure=new AtomicReference<Throwable>();
        Platform.startup(()->Toolkit.getToolkit().addRenderJob(new RenderJob(()->{
            try {
                var factory=GraphicsPipeline.getDefaultResourceFactory();
                StringBuilder result=new StringBuilder();
                for (var mode:CompositeMode.values()) for(boolean aa:new boolean[]{true,false}) for(float offset:new float[]{0,.25f}) {
                    var rt=factory.createRTTexture(4,4,Texture.WrapMode.CLAMP_NOT_NEEDED);
                    if(rt==null) throw new AssertionError("RT allocation");
                    try {
                        var g=rt.createGraphics();
                        g.clear(new Color(0,0,1,1));
                        g.setAntialiasedShape(aa);
                        g.setCompositeMode(mode);
                        g.setPaint(new Color(1,0,0,.5f)); g.fillRect(offset,offset,2,2);
                        g.setPaint(new Color(0,1,0,1)); g.fillRect(offset,2+offset,2,2);
                        var data=IntBuffer.allocate(16);
                        if(!rt.readPixels(data)) throw new AssertionError("Read pixels");
                        result.append(mode).append('/').append(aa).append('/').append(offset);
                        for(int pixel:data.array()) result.append(' ').append(String.format("%08x",pixel));
                        result.append('\n');
                    } finally {rt.dispose();}
                }
                String output=System.getProperty("edges.output",System.getenv("GODOT_JFX_EDGE_OUTPUT"));
                Files.writeString(Path.of(output),result);
                System.out.println("COMPOSITE_EDGE_PROBE_PASS "+GraphicsPipeline.getPipeline().getClass().getSimpleName());
            } catch(Throwable error) {failure.set(error);}
            finally {done.countDown(); Platform.runLater(Platform::exit);}
        })));
        if(!done.await(30,TimeUnit.SECONDS)) throw new AssertionError("Edge render timeout");
        if(failure.get()!=null) throw new AssertionError(failure.get());
    }
}
