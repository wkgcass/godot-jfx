import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.tk.godot.GodotRenderCommands;
import com.sun.prism.PixelFormat;
import com.sun.prism.Texture;
import com.sun.prism.godot.GodotTexture;
import com.sun.prism.godot.GodotTexturePool;
import java.nio.*;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicInteger;

public final class PrismTextureProbe {
    private static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    private static void draw(GodotRenderCommands commands, GodotTexture texture, int x, int y, int width) {
        float[] vertices = new float[28]; byte[] colors = new byte[16]; Arrays.fill(colors, (byte) 255);
        for (int i = 0; i < 4; ++i) {
            vertices[i * 7] = x + (i / 2) * width; vertices[i * 7 + 1] = y + (i % 2) * 64;
            vertices[i * 7 + 3] = i / 2; vertices[i * 7 + 4] = i % 2;
        }
        commands.drawTexturedQuads(texture.getNativeHandle(), vertices, colors, 4);
    }
    public static void main(String[] args) throws Exception {
        GodotRenderCommands commands = new GodotRenderCommands();
        AtomicInteger flushes = new AtomicInteger();
        GodotTexturePool pool = new GodotTexturePool(commands, flushes::incrementAndGet);
        commands.resize(400, 240); commands.clear();
        GodotTexture bgra = GodotTexture.create(pool, PixelFormat.BYTE_BGRA_PRE, Texture.WrapMode.CLAMP_TO_EDGE, 2, 2);
        ByteBuffer bytes = ByteBuffer.allocate(55);
        for (int row = 1; row < 3; ++row) for (int col = 1; col < 3; ++col) {
            int offset = 7 + row * 16 + col * 4;
            bytes.put(offset, (byte) 153).put(offset + 1, (byte) 51).put(offset + 2, (byte) 204).put(offset + 3, (byte) 255);
        }
        bytes.position(7); ByteBuffer source = bytes.asReadOnlyBuffer();
        bgra.update(source, PixelFormat.BYTE_BGRA_PRE, 0, 0, 1, 1, 2, 2, 16, false);
        require(source.position() == 7 && source.limit() == 55, "Byte source position/limit changed");
        require(flushes.get() == 1, "Texture upload did not flush preceding vertices");
        Texture alias = bgra.getSharedTexture(Texture.WrapMode.REPEAT);
        require(alias.getLockCount() == 2 && ((GodotTexture) alias).getNativeHandle() == bgra.getNativeHandle(), "Shared texture resource/lock differs");
        alias.unlock();
        long first = bgra.getNativeHandle();
        draw(commands, bgra, 16, 16, 160); bgra.dispose();
        require(alias.isSurfaceLost() && pool.used() == 0, "Disposed shared texture remained live or charged");

        GodotTexture argb = GodotTexture.create(pool, PixelFormat.INT_ARGB_PRE, Texture.WrapMode.CLAMP_TO_EDGE, 2, 2);
        require(argb.getNativeHandle() == first + (1L << 32), "Texture slot generation did not advance");
        IntBuffer ints = IntBuffer.allocate(14);
        for (int row = 1; row < 3; ++row) for (int col = 1; col < 3; ++col) ints.put(2 + row * 4 + col, 0xff00ff00);
        ints.position(2); IntBuffer intSource = ints.asReadOnlyBuffer();
        int previousFlushes = flushes.get();
        argb.update(intSource, PixelFormat.INT_ARGB_PRE, 0, 0, 1, 1, 2, 2, 16, true);
        require(intSource.position() == 2 && flushes.get() == previousFlushes, "Int source changed or skipFlush ignored");
        boolean rejected = false;
        try { argb.update(intSource, PixelFormat.INT_ARGB_PRE, 0, 0, Integer.MAX_VALUE, 0, 2, 2, 16, false); }
        catch (IllegalArgumentException expected) { rejected = true; }
        require(rejected, "Overflowing source region accepted");
        argb.unlock(); rejected = false;
        try { argb.update(intSource, PixelFormat.INT_ARGB_PRE, 0, 0, 1, 1, 2, 2, 16, false); }
        catch (IllegalStateException expected) { rejected = true; }
        require(rejected, "Unlocked texture accepted an upload"); argb.lock();
        draw(commands, argb, 200, 16, 80); argb.dispose();

        GodotTexture rgb = GodotTexture.create(pool, PixelFormat.BYTE_RGB, Texture.WrapMode.CLAMP_TO_EDGE, 2, 2);
        ByteBuffer rgbBytes = ByteBuffer.allocate(41);
        for (int row = 1; row < 3; ++row) for (int col = 1; col < 3; ++col) rgbBytes.put(5 + row * 12 + col * 3 + 2, (byte) 255);
        rgbBytes.position(5); rgb.update(rgbBytes, PixelFormat.BYTE_RGB, 0, 0, 1, 1, 2, 2, 12, false);
        draw(commands, rgb, 310, 16, 60); rgb.dispose();
        GodotTexture gray = GodotTexture.create(pool, PixelFormat.BYTE_GRAY, Texture.WrapMode.CLAMP_TO_EDGE, 1, 1);
        gray.update(ByteBuffer.wrap(new byte[] {(byte) 128}), PixelFormat.BYTE_GRAY, 0, 0, 0, 0, 1, 1, 1, false);
        draw(commands, gray, 16, 144, 160); gray.dispose();
        GodotTexture alpha = GodotTexture.create(pool, PixelFormat.BYTE_ALPHA, Texture.WrapMode.CLAMP_TO_EDGE, 1, 1);
        alpha.update(ByteBuffer.wrap(new byte[] {(byte) 128}), PixelFormat.BYTE_ALPHA, 0, 0, 0, 0, 1, 1, 1, false);
        draw(commands, alpha, 200, 144, 80);
        Thread disposer = new Thread(alpha::dispose); disposer.start(); disposer.join();
        require(alpha.isSurfaceLost(), "Cross-thread disposal was not requested");
        pool.freeDisposalRequestedAndCheckResources(false);
        require(pool.used() == 0, "Deferred disposal did not release pool accounting");
        GodotTexture floating = GodotTexture.create(pool,PixelFormat.FLOAT_XYZW,Texture.WrapMode.CLAMP_TO_ZERO,2,2);
        require(pool.used() == 64 && pool.estimateTextureSize(2,2,PixelFormat.FLOAT_XYZW) == 64,"Float texture accounting differs");
        FloatBuffer floatSource = FloatBuffer.allocate(47);
        for (int row = 0; row < 2; ++row) for (int component = 0; component < 8; ++component) floatSource.put(23+row*16+component,(component-3)*.25f);
        floatSource.position(3);
        floating.update(floatSource.asReadOnlyBuffer(),PixelFormat.FLOAT_XYZW,0,0,1,1,2,2,64,false);
        require(floatSource.position() == 3,"Float upload changed source position");
        int remaining = commands.remainingBatchBytes();
        floatSource.put(46,Float.NaN); rejected = false;
        try { floating.update(floatSource,PixelFormat.FLOAT_XYZW,0,0,1,1,2,2,64,false); }
        catch (IllegalArgumentException expected) { rejected = true; }
        require(rejected && remaining == commands.remainingBatchBytes(),"Invalid float upload emitted a partial patch");
        previousFlushes = flushes.get();
        floating.setLinearFiltering(false); floating.setLinearFiltering(false);
        require(flushes.get() == previousFlushes+1,"Filtering mutation did not flush exactly once");
        FloatBuffer blueFloat=FloatBuffer.wrap(new float[]{0,0,1,1, 0,0,1,1, 0,0,1,1, 0,0,1,1});
        floating.update(blueFloat,PixelFormat.FLOAT_XYZW,0,0,0,0,2,2,32,false);
        floating.update(FloatBuffer.wrap(new float[]{.2f,.7f,.1f,1}),PixelFormat.FLOAT_XYZW,1,1,0,0,1,1,16,false);
        draw(commands,floating,120,144,60);
        floating.dispose();
        require(pool.used() == 0,"Float disposal retained pool charge");
        GodotTexture large = GodotTexture.create(pool, PixelFormat.BYTE_BGRA_PRE, Texture.WrapMode.CLAMP_TO_EDGE, 1024, 1024);
        ByteBuffer largeSource = ByteBuffer.allocateDirect(1024 * 1024 * 4).order(ByteOrder.LITTLE_ENDIAN);
        while (largeSource.hasRemaining()) largeSource.putInt(0xffff8000);
        largeSource.flip();
        large.update(largeSource, PixelFormat.BYTE_BGRA_PRE, 0, 0, 0, 0, 1024, 1024, 4096, false);
        require(largeSource.position() == 0, "Chunked upload changed source position");
        draw(commands, large, 310, 144, 60); large.dispose();
        require(pool.used() == 0, "Large source texture remained charged");
        require(commands.submit() == 2, "Large texture did not split safely across bounded batches");
        long tick = 0;
        for (int i = 0; i < 8; ++i) { tick = GodotBridge.awaitTick(tick, 1000); require(tick >= 0, "Host stopped"); }
        System.out.println("BRIDGE_PROBE_PASS: real Prism Texture formats, offsets, stride, locks, shared handle and deferred disposal");
    }
}
