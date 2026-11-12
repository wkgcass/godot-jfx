import com.sun.glass.ui.Screen;
import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.prism.Graphics;
import com.sun.prism.CompositeMode;
import com.sun.prism.RTTexture;
import com.sun.prism.Texture;
import com.sun.prism.PixelFormat;
import com.sun.prism.godot.GodotTexture;
import com.sun.prism.godot.GodotShader;
import java.util.Map;
import java.nio.IntBuffer;
import com.sun.prism.RenderTarget;
import com.sun.prism.godot.GodotGraphics;
import com.sun.prism.godot.GodotResourceFactory;
import com.sun.prism.paint.Color;
import com.sun.javafx.geom.Rectangle;

public final class PrismContextProbe {
    public static void main(String[] args) {
        var factory = new GodotResourceFactory(null);
        RenderTarget target = new RenderTarget() {
            boolean opaque;
            public Screen getAssociatedScreen() { return null; }
            public Graphics createGraphics() { return new GodotGraphics(factory.getContext(), this); }
            public int getPhysicalWidth() { return 400; }
            public int getPhysicalHeight() { return 240; }
            public int getContentX() { return 0; }
            public int getContentY() { return 0; }
            public int getContentWidth() { return 400; }
            public int getContentHeight() { return 240; }
            public boolean isOpaque() { return opaque; }
            public void setOpaque(boolean value) { opaque = value; }
            public boolean isMSAA() { return false; }
        };
        Graphics graphics = target.createGraphics();
        graphics.clear(Color.TRANSPARENT);
        graphics.setPaint(new Color(.8f,.2f,.6f,1));
        graphics.fillRect(16,16,80,96);
        graphics.setPaint(new Color(0,1,0,1));
        graphics.translate(200,16);
        graphics.scale(2,2);
        graphics.fillRect(0,0,40,48);
        graphics.setTransform(1,0,0,1,0,0);
        graphics.setClipRect(new Rectangle(20,140,20,20));
        graphics.setPaint(new Color(0,0,1,1));
        graphics.fillRect(0,120,80,80);
        graphics.setClipRect(new Rectangle(0,0,0,0));
        graphics.setPaint(new Color(1,1,0,1));
        graphics.fillRect(0,0,400,240);
        graphics.setClipRect(null);
        graphics.setPaint(new Color(1,0,0,1));
        graphics.fillRect(120,140,40,40);
        graphics.setClipRect(new Rectangle(130,150,10,10));
        graphics.clear(new Color(0,0,1,.5f));
        graphics.setClipRect(null);
        graphics.translate(120,140);
        graphics.scale(2,2);
        graphics.clearQuad(0,0,5,5);
        graphics.setTransform(1,0,0,1,0,0);
        graphics.setPaint(new Color(0,0,1,1));
        graphics.fillRect(200,140,60,40);
        graphics.setCompositeMode(CompositeMode.SRC);
        graphics.setPaint(new Color(1,0,0,.5f));
        graphics.fillRect(220,140,20,40);
        graphics.setCompositeMode(CompositeMode.SRC_OVER);
        factory.getContext().flushVertexBuffer();
        RTTexture offscreen = factory.createRTTexture(32,32,Texture.WrapMode.CLAMP_TO_EDGE);
        if (offscreen == null || offscreen.getPhysicalWidth() != 32 || offscreen.isOpaque()) throw new AssertionError("RT allocation metadata");
        Texture alias = offscreen.getSharedTexture(Texture.WrapMode.REPEAT);
        if (!(alias instanceof RTTexture) || alias.getLockCount() != 2) throw new AssertionError("RT alias lost type/lock");
        alias.unlock();
        boolean rejected = false;
        try { offscreen.update(IntBuffer.allocate(1),PixelFormat.INT_ARGB_PRE,0,0,0,0,1,1,4,false); }
        catch (UnsupportedOperationException expected) { rejected = true; }
        if (!rejected) throw new AssertionError("RT accepted CPU upload");
        var commands = factory.getContext().getCommands();
        commands.shaderState(new GodotShader.Snapshot("shader_type canvas_item; render_mode unshaded, blend_premul_alpha;",Map.of(),Map.of()));
        commands.clip(false,0,0,0,0);
        byte[] white = new byte[16]; java.util.Arrays.fill(white,(byte)255);
        commands.drawTexturedQuads(((GodotTexture)offscreen).getNativeHandle(),
                new float[]{300,200,0,0,0,0,0, 300,230,0,0,1,0,0, 360,200,0,1,0,0,0, 360,230,0,1,1,0,0},white,4);
        offscreen.dispose();
        if (!alias.isSurfaceLost()) throw new AssertionError("RT alias survived resource disposal");
        graphics.sync();
        long tick = 0;
        for (int i = 0; i < 8; ++i) tick = GodotBridge.awaitTick(tick, 1000);
        System.out.println("BRIDGE_PROBE_PASS BaseShaderGraphics fillRect, paints, transforms, vertex batching");
    }
}
