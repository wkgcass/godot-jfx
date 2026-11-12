import com.sun.glass.ui.Screen;
import com.sun.javafx.geom.Rectangle;
import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.prism.*;
import com.sun.prism.godot.*;
import com.sun.prism.paint.Color;

public final class CompositeProbe {
    public static void main(String[] args) {
        var factory = new GodotResourceFactory(null);
        RenderTarget screen = new RenderTarget() {
            public Screen getAssociatedScreen() { return null; }
            public Graphics createGraphics() { return new GodotGraphics(factory.getContext(), this); }
            public int getPhysicalWidth() { return 320; }
            public int getPhysicalHeight() { return 280; }
            public int getContentX() { return 0; }
            public int getContentY() { return 0; }
            public int getContentWidth() { return 320; }
            public int getContentHeight() { return 280; }
            public boolean isOpaque() { return false; }
            public void setOpaque(boolean value) {}
            public boolean isMSAA() { return false; }
        };
        var canvas = factory.createRTTexture(320,280,Texture.WrapMode.CLAMP_TO_EDGE);
        Graphics g = canvas.createGraphics();
        g.clear(Color.TRANSPARENT);
        var texture = factory.createRTTexture(16,16,Texture.WrapMode.CLAMP_TO_EDGE);
        var tg = texture.createGraphics();
        tg.clear(new Color(1,0,0,.25f));
        var custom = new GodotShader("shader_type canvas_item; render_mode unshaded, blend_premul_alpha;\n" +
                "void fragment() { /* } return; */ float t = 0.25; if (UV.x >= 0.0) { COLOR=vec4(t,0.0,0.0,t); } else { COLOR=vec4(1.0); } }\n" +
                "float unused_helper() { return 1.0; }", java.util.Map.of(), java.util.Map.of(), factory.getContext()::selectShader);
        CompositeMode[] modes = CompositeMode.values();
        float[] alphas = {0,.25f,1};
        for (int row=0;row<5;row++) for (int col=0;col<modes.length;col++) {
            int x=10+col*60, y=10+row*50;
            ((GodotGraphics)g).setExternalShader(null);
            g.setClipRect(null); g.setCompositeMode(CompositeMode.SRC);
            g.setPaint(new Color(0,0,1,.5f)); g.fillRect(x,y,40,40);
            g.setClipRect(new Rectangle(x+10,y,30,40));
            g.setCompositeMode(modes[col]);
            if (row==4) {
                ((GodotGraphics)g).setExternalShader(custom);
                g.fillRect(x,y,40,40);
            } else if (row==3) g.drawTexture(texture,x,y,40,40);
            else { g.setPaint(new Color(1,0,0,alphas[row])); g.fillRect(x,y,40,40); }
        }
        screen.createGraphics().blit(canvas,null,0,0,320,280,0,0,320,280);
        texture.dispose(); canvas.dispose();
        g.sync();
        factory.getContext().getCommands().endTargetPass();
        custom.dispose();
        long tick=0;
        for (int i=0;i<12;i++) tick=GodotBridge.awaitTick(tick,1000);
        System.out.println("COMPOSITE_PROBE_PASS");
    }
}
