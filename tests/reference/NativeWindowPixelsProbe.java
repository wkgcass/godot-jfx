import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.tk.godot.GodotRenderCommands;
import com.sun.prism.godot.GodotShader;
import java.util.Map;

public final class NativeWindowPixelsProbe {
    private static long tick;
    private static void waitFor(long sequence) {
        long deadline=System.nanoTime()+5_000_000_000L;
        while(GodotBridge.nativeWindowAck()<sequence) {
            tick=GodotBridge.awaitTick(tick,100);
            if(tick<0||System.nanoTime()>deadline) throw new AssertionError("Native ack timeout");
        }
    }
    private static void verify(int step) {
        GodotBridge.hostCommand(1,0,0,"Native pixels "+step);
        long deadline=System.nanoTime()+10_000_000_000L;
        for(;;) {
            double[] events=GodotBridge.pollInput();
            for(int i=0;i<events.length;i+=9) if(events[i]==2) return;
            tick=GodotBridge.awaitTick(tick,100);
            if(tick<0||System.nanoTime()>deadline) throw new AssertionError("Pixel verification timeout "+step);
        }
    }
    private static void publish(GodotRenderCommands commands,long target,long id,int red,int green,int blue) {
        commands.beginPresent(); commands.selectTarget(target); commands.clear();
        var shader=new GodotShader("shader_type canvas_item; render_mode unshaded, blend_premul_alpha;",Map.of(),Map.of(),selected -> {});
        commands.shaderState(shader.snapshot()); shader.dispose();
        float[] vertices=new float[28]; byte[] colors=new byte[16];
        for(int i=0;i<4;++i) {
            vertices[i*7]=(i/2)*320; vertices[i*7+1]=(i%2)*180;
            colors[i*4]=(byte)red; colors[i*4+1]=(byte)green; colors[i*4+2]=(byte)blue; colors[i*4+3]=(byte)255;
        }
        commands.drawQuads(vertices,colors,4,1,0,0,0,1,0); commands.presentNativeWindow(id,320,180,1);
    }
    public static void main(String[] args) {
        int[] host=GodotBridge.hostInfo(); int x=host[3]+host[0]+30,y=host[4];
        GodotBridge.nativeWindowCommand(100,0,1,x,y,320,180,0,false,"Native pixels A");
        GodotBridge.nativeWindowCommand(101,0,1,x,y+240,320,180,0,false,"Native pixels B");
        GodotBridge.nativeWindowCommand(100,0,2,x,y,320,180,0,true,null);
        waitFor(GodotBridge.nativeWindowCommand(101,0,2,x,y+240,320,180,0,true,null));
        var c=new GodotRenderCommands(); long a=0x100000001L,b=0x100000002L;
        c.allocateRenderTarget(a,320,180); c.allocateRenderTarget(b,320,180);
        publish(c,a,100,255,0,0); publish(c,b,101,0,0,255); verify(0);
        publish(c,a,100,0,255,0); verify(1);
        waitFor(GodotBridge.nativeWindowCommand(101,0,2,x,y+240,320,180,0,false,null));
        publish(c,b,101,255,255,0); verify(2);
        waitFor(GodotBridge.nativeWindowCommand(101,0,2,x,y+240,320,180,0,true,null)); verify(3);
        waitFor(GodotBridge.nativeWindowCommand(101,0,3,0,0,0,0,0,false,null));
        publish(c,b,101,0,255,255); c.removeWindow(101); c.disposeTexture(b); c.submit(); verify(4);
        c.removeWindow(100); c.disposeTexture(a); c.submit(); verify(5);
        waitFor(GodotBridge.nativeWindowCommand(100,0,3,0,0,0,0,0,false,null));
        System.out.println("NATIVE_WINDOW_PIXELS_PROBE_PASS");
    }
}
