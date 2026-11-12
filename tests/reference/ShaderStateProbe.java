import com.sun.prism.godot.GodotShader;
import com.sun.prism.ps.ShaderFactory;
import java.io.InputStream;
import java.lang.reflect.Proxy;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import java.util.zip.ZipFile;

/** Descriptor contract and compatibility with the real generated Prism loaders. */
public final class ShaderStateProbe {
    static void require(boolean value) { if (!value) throw new AssertionError(); }
    static void rejects(Class<? extends Throwable> type, Runnable action) {
        try { action.run(); } catch (Throwable failure) {
            if (type.isInstance(failure)) return;
            throw new AssertionError(failure);
        }
        throw new AssertionError("Expected " + type.getName());
    }
    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        ShaderFactory factory = (ShaderFactory) Proxy.newProxyInstance(ShaderFactory.class.getClassLoader(),
                new Class<?>[]{ShaderFactory.class}, (proxy, method, values) -> {
                    if (!method.getName().equals("createShader")) throw new AssertionError(method);
                    return GodotShader.loadPrism((String) values[0], (Map<String,Integer>) values[2],
                            (Map<String,Integer>) values[3], selected -> {});
                });
        int loaders = 0;
        try (ZipFile sdk = new ZipFile(args[0])) {
            for (var entry : sdk.stream().filter(e -> e.getName().startsWith("com/sun/prism/shader/")
                    && e.getName().endsWith("_Loader.class")).toList()) {
                String qualified = entry.getName().replace('/', '.').replace(".class", "");
                String name = qualified.substring(qualified.lastIndexOf('.') + 1).replace("_Loader", "");
                GodotShader shader = (GodotShader) Class.forName(qualified)
                        .getMethod("loadShader", ShaderFactory.class, String.class, InputStream.class)
                        .invoke(null, factory, name, null);
                require(shader.isValid());
                shader.dispose();
                ++loaders;
            }
        }
        require(loaders == 212);
        AtomicReference<GodotShader> selected = new AtomicReference<>();
        GodotShader shader = new GodotShader("uniform sampler2D image; uniform vec4 tint; uniform int mode; "
                + "uniform vec4 weights[2]; uniform ivec4 indices[2];", Map.of("image", 1),
                Map.of("tint", 0, "weights", 1, "indices", 3, "mode", 5), selected::set);
        shader.enable(); require(selected.get() == shader);
        shader.setConstant("tint", .1f, .2f, .3f, .4f);
        shader.setConstant("mode", 7);
        FloatBuffer weights = FloatBuffer.wrap(new float[]{99,99,99,99,1,2,3,4,5,6,7,8}).asReadOnlyBuffer();
        weights.position(2);
        shader.setConstants("weights", weights, 1, 2);
        require(weights.position() == 2);
        shader.setConstants("indices", IntBuffer.wrap(new int[]{1,2,3,4,5,6,7,8}), 0, 2);
        var before = shader.snapshot();
        weights = FloatBuffer.wrap(new float[]{9,10,11,12});
        shader.setConstants("weights", weights, 0, 1);
        shader.setConstant("tint", 1f, 1f, 1f, 1f);
        require(Float.intBitsToFloat(before.constants().get("weights").words()[0]) == 1f);
        int[] after = shader.snapshot().constants().get("weights").words();
        require(Float.intBitsToFloat(after[0]) == 9f && Float.intBitsToFloat(after[4]) == 5f);
        after[0] = 0;
        require(Float.intBitsToFloat(shader.snapshot().constants().get("weights").words()[0]) == 9f);
        rejects(UnsupportedOperationException.class, () -> before.constants().clear());
        rejects(IllegalArgumentException.class, () -> shader.setConstant("mode", 1f));
        rejects(IllegalArgumentException.class, () -> shader.setConstant("tint", Float.NaN, 0f, 0f, 0f));
        rejects(IllegalArgumentException.class, () -> shader.setConstants("weights", FloatBuffer.allocate(8), Integer.MAX_VALUE, 1));
        rejects(IllegalArgumentException.class, () -> shader.setConstants("weights", FloatBuffer.allocate(12), 0, 3));
        require(Float.intBitsToFloat(shader.snapshot().constants().get("weights").words()[0]) == 9f);
        AtomicReference<Throwable> threadFailure = new AtomicReference<>();
        Thread worker = new Thread(() -> { try { shader.snapshot(); } catch (Throwable t) { threadFailure.set(t); } });
        worker.start(); worker.join(); require(threadFailure.get() instanceof IllegalStateException);
        shader.dispose(); require(selected.get() == null && !shader.isValid());
        shader.dispose();
        rejects(IllegalStateException.class, shader::snapshot);
        require(before.constants().get("mode").words()[0] == 7);
        System.out.println("SHADER_STATE_PASS: " + loaders + " real loaders; immutable snapshots, arrays, validation, ownership and disposal");
    }
}
