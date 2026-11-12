import com.sun.glass.ui.Screen;
import com.sun.javafx.geom.Rectangle;
import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.prism.*;
import com.sun.prism.godot.*;
import com.sun.prism.paint.Color;

public final class BlitProbe {
    public static void main(String[] args) {
        var factory = new GodotResourceFactory(null);
        RenderTarget screen = new RenderTarget() {
            public Screen getAssociatedScreen() { return null; }
            public Graphics createGraphics() { return new GodotGraphics(factory.getContext(), this); }
            public int getPhysicalWidth() { return 200; }
            public int getPhysicalHeight() { return 120; }
            public int getContentX() { return 0; }
            public int getContentY() { return 0; }
            public int getContentWidth() { return 200; }
            public int getContentHeight() { return 120; }
            public boolean isOpaque() { return false; }
            public void setOpaque(boolean value) {}
            public boolean isMSAA() { return false; }
        };
        var src = factory.createRTTexture(32,16,Texture.WrapMode.CLAMP_TO_EDGE);
        var dst = factory.createRTTexture(64,48,Texture.WrapMode.CLAMP_TO_EDGE);
        var sg = src.createGraphics();
        sg.clear(Color.TRANSPARENT);
        sg.setPaint(new Color(1,0,0,.5f)); sg.fillRect(0,0,16,16);
        sg.setPaint(new Color(0,0,1,1)); sg.fillRect(16,0,16,16);
        var dg = dst.createGraphics();
        dg.clear(new Color(0,1,0,1));
        dg.translate(50,40); dg.setClipRect(new Rectangle(50,40,8,8)); dg.setExtraAlpha(.5f);
        dg.setPaint(new Color(1,1,0,1)); dg.fillRect(0,0,8,8);
        src.setLinearFiltering(false);
        dg.blit(src,dst,0,0,16,16,8,8,40,40);
        // A normal draw after blit must restore the caller's cached state.
        dg.fillRect(0,0,8,8);
        var g = screen.createGraphics();
        g.clear(Color.TRANSPARENT);
        g.translate(120,90); g.setClipRect(new Rectangle(0,0,1,1)); g.setExtraAlpha(.1f);
        g.blit(dst,null,0,0,64,48,20,20,84,68);
        g.blit(src,null,16,0,32,16,100,20,132,52);
        // Full source scaling includes a half-red/half-blue bilinear boundary.
        g.blit(src,null,0,0,32,16,20,80,84,112);
        g.blit(src,null,32,0,0,16,140,20,172,52);
        Texture alias = src.getSharedTexture(Texture.WrapMode.REPEAT);
        if (alias == null) throw new AssertionError("Missing RT shared alias");
        try {
            src.createGraphics().blit((RTTexture)alias,src,0,0,8,8,8,8,16,16);
            throw new AssertionError("Self-storage blit accepted");
        } catch (IllegalArgumentException expected) {} finally { alias.unlock(); }
        src.dispose(); dst.dispose();
        g.sync();
        long tick=0;
        for (int i=0;i<12;++i) tick=GodotBridge.awaitTick(tick,1000);
        System.out.println("BLIT_PROBE_PASS");
    }
}
