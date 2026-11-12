import com.sun.javafx.geom.Rectangle;
import com.sun.javafx.geom.transform.BaseTransform;
import com.sun.scenario.effect.*;
import com.sun.scenario.effect.impl.*;
import java.lang.ref.SoftReference;
import java.util.List;

/** Deterministic pool eviction/reuse test; no graphics device or GC timing. */
public final class ImagePoolReuseProbe {
    static final class Image implements PoolFilterable {
        final boolean lost;
        int locks;
        Image(boolean lost) { this.lost = lost; }
        public void setImagePool(ImagePool pool) {}
        public ImagePool getImagePool() { return null; }
        public Object getData() { return this; }
        public int getContentWidth() { return 32; }
        public int getContentHeight() { return 32; }
        public void setContentWidth(int width) {}
        public void setContentHeight(int height) {}
        public int getMaxContentWidth() { return 32; }
        public int getMaxContentHeight() { return 32; }
        public int getPhysicalWidth() { return 32; }
        public int getPhysicalHeight() { return 32; }
        public float getPixelScale() { return 1; }
        public void flush() {}
        public void lock() { locks++; }
        public void unlock() {
            if (locks <= 0) throw new AssertionError("Image unlocked without a lock");
            locks--;
        }
        public boolean isLost() { return lost; }
    }
    static final class PoolRenderer extends Renderer {
        int allocations, clears;
        public Effect.AccelType getAccelType() { return Effect.AccelType.NONE; }
        public int getCompatibleWidth(int width) { return width; }
        public int getCompatibleHeight(int height) { return height; }
        public PoolFilterable createCompatibleImage(int width, int height) { allocations++; return new Image(false); }
        public void clearImage(Filterable image) { clears++; }
        public ImageData createImageData(FilterContext context, Filterable image) { throw new AssertionError(); }
        public Filterable transform(FilterContext context, Filterable image, BaseTransform transform, Rectangle from, Rectangle to) { throw new AssertionError(); }
        public ImageData transform(FilterContext context, ImageData image, BaseTransform transform, Rectangle from, Rectangle to) { throw new AssertionError(); }
        public RendererState getRendererState() { return RendererState.OK; }
        protected Renderer getBackupRenderer() { throw new AssertionError(); }
        public boolean isImageDataCompatible(ImageData data) { return true; }
        protected EffectPeer<?> createPeer(FilterContext context, String name, int count) { throw new AssertionError(); }
    }
    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        var constructor = ImagePool.class.getDeclaredConstructor(); constructor.setAccessible(true);
        var field = ImagePool.class.getDeclaredField("unlocked"); field.setAccessible(true);
        for (int scenario = 0; scenario < 4; ++scenario) {
            var pool = constructor.newInstance();
            var entries = (List<SoftReference<PoolFilterable>>)field.get(pool);
            Image valid = new Image(false);
            if (scenario == 0 || scenario == 2) entries.add(new SoftReference<>(null));
            if (scenario == 1 || scenario == 2) entries.add(new SoftReference<>(new Image(true)));
            entries.add(new SoftReference<>(valid));
            Image newest = null;
            if (scenario == 3) { newest = new Image(false); entries.add(new SoftReference<>(newest)); }
            var renderer = new PoolRenderer();
            PoolFilterable expected = scenario == 3 && !"0".equals(System.getenv("GODOT_JFX_IMAGE_POOL_LIFO")) ? newest : valid;
            if (pool.checkOut(renderer, 32, 32) != expected || renderer.allocations != 0 || renderer.clears != 1)
                throw new AssertionError("Pool skipped reusable image or changed tie order: scenario=" + scenario);
        }
        // Put the lost image first in the selected traversal direction.
        var pool = constructor.newInstance();
        var entries = (List<SoftReference<PoolFilterable>>)field.get(pool);
        Image lost = new Image(true), valid = new Image(false);
        boolean lifo = !"0".equals(System.getenv("GODOT_JFX_IMAGE_POOL_LIFO"));
        entries.add(new SoftReference<>(lifo ? valid : lost));
        entries.add(new SoftReference<>(lifo ? lost : valid));
        var renderer = new PoolRenderer();
        if (pool.checkOut(renderer,32,32) != valid || lost.locks != 0 || valid.locks != 1)
            throw new AssertionError("Lost candidate retained its lock or reusable image was not locked");
        pool.checkIn(valid);
        if (valid.locks != 0) throw new AssertionError("checkIn retained image lock");
        if (pool.checkOut(renderer,32,32) != valid || renderer.allocations != 0)
            throw new AssertionError("checkIn image was not reused");
        pool.checkIn(valid);
        pool.dispose();
        if (valid.locks != 0 || lost.locks != 0) throw new AssertionError("Pool lifecycle leaked a lock");
        System.out.println("IMAGE_POOL_REUSE_PASS lifo=" + System.getenv("GODOT_JFX_IMAGE_POOL_LIFO"));
    }
}
