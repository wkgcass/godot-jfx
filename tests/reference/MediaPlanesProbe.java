import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.prism.*;
import com.sun.prism.godot.*;
import com.sun.prism.paint.Color;
import java.nio.*;

public final class MediaPlanesProbe {
    private static class Frame implements MediaFrame {
        final ByteBuffer[] planes;
        int holds;
        Frame(int count, int y, int cr, int cb, int alpha) {
            planes = new ByteBuffer[count];
            int[] values = {y, cr, cb, alpha};
            for (int p=0; p<count; p++) {
                int height = p==1 || p==2 ? 4 : 8;
                ByteBuffer buffer = ByteBuffer.allocateDirect(strideForPlane(p)*height);
                int visible = p==1 || p==2 ? 3 : 6;
                // Encoded padding and stride padding deliberately differ from the picture.
                for (int row=0; row<visible; row++) for (int x=0; x<visible; x++)
                    buffer.put(row*strideForPlane(p)+x,(byte)values[p]);
                planes[p]=buffer.asReadOnlyBuffer();
            }
        }
        public ByteBuffer getBufferForPlane(int p) { return planes[p]; }
        public PixelFormat getPixelFormat() { return PixelFormat.MULTI_YCbCr_420; }
        public int getWidth() { return 6; }
        public int getHeight() { return 6; }
        public int getEncodedWidth() { return 8; }
        public int getEncodedHeight() { return 8; }
        public int planeCount() { return planes.length; }
        public int[] planeStrides() { return planes.length==3 ? new int[]{12,6,6} : new int[]{12,6,6,12}; }
        public int strideForPlane(int p) { return p==1 || p==2 ? 6 : 12; }
        public MediaFrame convertToFormat(PixelFormat format) { return format==getPixelFormat() ? this : null; }
        public void holdFrame() { holds++; }
        public void releaseFrame() { if (--holds<0) throw new AssertionError("Unbalanced frame release"); }
    }
    private static void verify(GodotResourceFactory factory, RTTexture target, int count, int y, int cr, int cb, int alpha, int expected) {
        Frame frame=new Frame(count,y,cr,cb,alpha);
        Texture texture=factory.createTexture(frame);
        if (frame.holds!=0 || !factory.isCompatibleTexture(texture)) throw new AssertionError("Video ownership");
        texture.update(frame,false);
        texture.setLinearFiltering(false);
        var g=target.createGraphics();
        g.clear(Color.TRANSPARENT);
        g.drawTexture(texture,0,0,6,6);
        IntBuffer pixels=IntBuffer.allocate(36);
        if (!target.readPixels(pixels)) throw new AssertionError("Video readback");
        for (int pixel:pixels.array()) for (int shift=0;shift<32;shift+=8)
            if (Math.abs(((pixel>>>shift)&255)-((expected>>>shift)&255))>3)
                throw new AssertionError("Video color: "+Integer.toHexString(pixel)+" expected "+Integer.toHexString(expected));
        for (ByteBuffer plane:frame.planes) if (plane.position()!=0) throw new AssertionError("Frame buffer modified");
        texture.dispose();
    }
    public static void main(String[] args) {
        var factory=new GodotResourceFactory(null);
        var target=factory.createRTTexture(6,6,Texture.WrapMode.CLAMP_TO_EDGE);
        verify(factory,target,3,81,240,90,255,0xffff0000);
        verify(factory,target,4,145,34,54,128,0x80008000);
        // Three planes immediately after four must not sample the previous alpha plane.
        verify(factory,target,3,41,110,240,255,0xff0000ff);
        // Packed decoders also pad their encoded rows. Logical texture bounds
        // must describe the visible picture, not the unused decoder padding.
        ByteBuffer packed=ByteBuffer.allocateDirect(8*40).order(ByteOrder.nativeOrder());
        for(int y=0;y<6;y++)for(int x=0;x<6;x++)packed.putInt(y*40+x*4,0xff00ff00);
        Frame packedFrame=new Frame(1,0,0,0,0){
            @Override public PixelFormat getPixelFormat(){return PixelFormat.INT_ARGB_PRE;}
            @Override public ByteBuffer getBufferForPlane(int p){return packed.asReadOnlyBuffer();}
            @Override public int strideForPlane(int p){return 40;}
            @Override public int[] planeStrides(){return new int[]{40};}
        };
        Texture packedTexture=factory.createTexture(packedFrame);
        if(packedTexture.getContentWidth()!=6 || packedTexture.getContentHeight()!=6)
            throw new AssertionError("Packed video exposes encoded padding as picture");
        packedTexture.update(packedFrame,false);
        var graphics=target.createGraphics();graphics.clear(Color.TRANSPARENT);
        graphics.drawTexture(packedTexture,0,0,6,6);
        IntBuffer packedPixels=IntBuffer.allocate(36);
        if(!target.readPixels(packedPixels))throw new AssertionError("Packed video readback");
        for(int pixel:packedPixels.array())if(pixel!=0xff00ff00)throw new AssertionError("Packed video padded edge: "+Integer.toHexString(pixel));
        if(packedFrame.holds!=0 || packed.position()!=0)throw new AssertionError("Packed video frame ownership");
        packedTexture.dispose();
        Frame invalid=new Frame(1,0,0,0,0){
            @Override public PixelFormat getPixelFormat(){return PixelFormat.INT_ARGB_PRE;}
            @Override public int getWidth(){return 9;}
        };
        try { factory.createTexture(invalid);throw new AssertionError("Invalid visible extent accepted"); }
        catch(IllegalArgumentException expected){}
        if(invalid.holds!=0)throw new AssertionError("Failed packed allocation retained frame");
        target.dispose(); factory.getContext().submit();
        long tick=0; for(int i=0;i<8;i++) tick=GodotBridge.awaitTick(tick,1000);
        System.out.println("MEDIA_PLANES_PROBE_PASS");
    }
}
