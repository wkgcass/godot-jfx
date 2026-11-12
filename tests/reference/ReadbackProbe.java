import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.prism.*;
import com.sun.prism.godot.*;
import com.sun.prism.paint.Color;
import java.nio.*;

public final class ReadbackProbe {
    private static void near(int actual, int expected) {
        for (int shift=0;shift<32;shift+=8)
            if (Math.abs(((actual>>>shift)&255)-((expected>>>shift)&255))>2)
                throw new AssertionError("Readback pixel " + Integer.toHexString(actual) + " != " + Integer.toHexString(expected));
    }
    private static void rejects(Runnable call, Class<? extends Throwable> type) {
        try { call.run(); } catch (Throwable failure) {
            if (type.isInstance(failure)) return;
            throw new AssertionError("Unexpected validation failure",failure);
        }
        throw new AssertionError("Invalid readback was accepted");
    }
    public static void main(String[] args) {
        var factory = new GodotResourceFactory(null);
        if ("1".equals(System.getenv("GODOT_JFX_READBACK_STOP"))) {
            var pending = factory.createRTTexture(4,4,Texture.WrapMode.CLAMP_TO_EDGE);
            var unchanged = IntBuffer.allocate(16);
            java.util.Arrays.fill(unchanged.array(),0x12345678);
            if (pending.readPixels(unchanged)) throw new AssertionError("Stopped readback unexpectedly succeeded");
            for(int n:unchanged.array()) if(n!=0x12345678) throw new AssertionError("Stopped readback modified output");
            System.out.println("READBACK_PROBE_PASS stopped pending request woke without partial writes");
            return;
        }
        var rt = factory.createRTTexture(4,4,Texture.WrapMode.CLAMP_TO_EDGE);
        var blank = factory.createRTTexture(3,2,Texture.WrapMode.CLAMP_TO_EDGE);
        IntBuffer zero = IntBuffer.allocate(6);
        if (!blank.readPixels(zero)) throw new AssertionError("Initial read failed");
        for (int n : zero.array()) near(n,0);
        rejects(()->GodotBridge.readPixels(0x7fff000000000001L,factory.getContext().getCommands().getLastSubmittedSequence(),0,0,1,1),IllegalArgumentException.class);
        var g=rt.createGraphics();
        g.clear(Color.TRANSPARENT);
        g.setPaint(new Color(0,0,1,1)); g.fillRect(2,0,2,4);
        g.setPaint(new Color(1,0,0,.5f)); g.fillRect(0,0,2,2);
        g.setPaint(new Color(0,1,0,1)); g.fillRect(0,2,2,2);
        long openSequence=factory.getContext().submit();
        rejects(()->GodotBridge.readPixels(((GodotTexture)rt).getNativeHandle(),openSequence,0,0,1,1),IllegalArgumentException.class);
        IntBuffer ints=IntBuffer.allocate(20);
        java.util.Arrays.fill(ints.array(),0x12345678);
        ints.position(2); ints.limit(18);
        if (!rt.readPixels(ints) || ints.position()!=2 || ints.limit()!=18) throw new AssertionError("Int buffer state");
        near(ints.get(2),0x80800000); near(ints.get(4),0xff0000ff); near(ints.get(10),0xff00ff00);
        if (ints.array()[0]!=0x12345678 || ints.array()[19]!=0x12345678) throw new AssertionError("Int buffer overrun");
        ByteBuffer storage=ByteBuffer.allocateDirect(36).order(ByteOrder.BIG_ENDIAN);
        for(int i=0;i<36;i++) storage.put(i,(byte)0x5a);
        storage.position(4); storage.limit(32);
        ByteBuffer bytes=storage.slice(); bytes.position(3); bytes.limit(19);
        if (!rt.readPixels(bytes,1,1,2,2) || bytes.position()!=3 || bytes.limit()!=19) throw new AssertionError("Byte buffer state");
        int[] expected={0x80800000,0xff0000ff,0xff00ff00,0xff0000ff};
        for(int i=0;i<4;i++) {
            int p=3+i*4;
            int argb=(bytes.get(p)&255)|((bytes.get(p+1)&255)<<8)|((bytes.get(p+2)&255)<<16)|((bytes.get(p+3)&255)<<24);
            near(argb,expected[i]);
        }
        if(storage.get(6)!=(byte)0x5a || storage.get(23)!=(byte)0x5a) throw new AssertionError("Byte buffer overrun");
        // Drawing can resume on the same Graphics after a synchronous read.
        g.setPaint(new Color(1,1,0,1)); g.fillRect(2,2,2,2);
        IntBuffer direct=ByteBuffer.allocateDirect(64).order(ByteOrder.nativeOrder()).asIntBuffer();
        if(!rt.readPixels(direct)) throw new AssertionError("Direct int read failed");
        near(direct.get(0),0x80800000); near(direct.get(15),0xffffff00);
        rejects(()->rt.readPixels(IntBuffer.allocate(15)),IllegalArgumentException.class);
        rejects(()->rt.readPixels(IntBuffer.allocate(16).asReadOnlyBuffer()),ReadOnlyBufferException.class);
        rejects(()->rt.readPixels(FloatBuffer.allocate(16)),IllegalArgumentException.class);
        rejects(()->rt.readPixels(ints,-1,0,1,1),IllegalArgumentException.class);
        rejects(()->rt.readPixels(ints,3,0,2,1),IllegalArgumentException.class);
        if(!rt.readPixels(IntBuffer.allocate(0),4,4,0,0)) throw new AssertionError("Empty read failed");
        rt.dispose(); blank.dispose(); factory.getContext().submit();
        long tick=0; for(int i=0;i<8;i++) tick=GodotBridge.awaitTick(tick,1000);
        System.out.println("READBACK_PROBE_PASS");
    }
}
