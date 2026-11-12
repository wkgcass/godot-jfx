import com.sun.prism.godot.GodotShader;
import java.util.Map;

/** No toolkit or GPU: validate generated stock-shader selection before drawing. */
public final class LcdShaderLoadProbe {
    public static void main(String[] args) {
        boolean reject = args.length == 1 && args[0].equals("reject");
        for (String name : new String[]{"Solid_TextureSecondPassLCD", "Solid_TextureSecondPassLCD_AlphaTest"}) {
            try {
                var shader = GodotShader.loadPrism(name, Map.of("dstColor", 0, "glyphColor", 1),
                        Map.of("gamma", 0), ignored -> {});
                shader.dispose();
                if (reject) throw new AssertionError("Unsupported screen rewrite was silently accepted: " + name);
            } catch (IllegalStateException error) {
                if (!reject || !error.getMessage().equals(
                        "Cannot enable LCD screen sampling for generated shader: " + name)) throw error;
            }
        }
        System.out.println("LCD_SHADER_LOAD_PASS reject=" + reject);
    }
}
