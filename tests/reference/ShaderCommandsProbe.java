import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.tk.godot.GodotRenderCommands;
import com.sun.prism.godot.GodotShader;
import java.nio.FloatBuffer;
import java.util.Map;

public final class ShaderCommandsProbe {
    static void quad(GodotRenderCommands commands, int x) {
        float[] vertices = new float[28];
        byte[] colors = new byte[16];
        java.util.Arrays.fill(colors, (byte)255);
        for (int i = 0; i < 4; ++i) {
            vertices[i * 7] = x + (i / 2) * 80;
            vertices[i * 7 + 1] = 16 + (i % 2) * 96;
        }
        commands.drawQuads(vertices, colors, 4);
    }
    public static void main(String[] args) {
        GodotRenderCommands commands = new GodotRenderCommands();
        GodotShader shader = new GodotShader("shader_type canvas_item; render_mode unshaded, blend_premul_alpha; "
                + "uniform sampler2D image; uniform vec4 colors[2]; uniform int index; void fragment() { COLOR = colors[index] * texture(image, UV); }",
                Map.of("image", 1), Map.of("colors", 0, "index", 2), selected -> {});
        commands.resize(400, 240); commands.clear();
        long texture = (1L << 32) | 1;
        commands.createTexture(texture, 1, 1, new byte[]{-1,-1,-1,-1});
        shader.setConstants("colors", FloatBuffer.wrap(new float[]{.8f,.2f,.6f,1,0,1,0,1}), 0, 2);
        shader.setConstant("index", 0);
        var first = shader.snapshot();
        commands.shaderState(first, new long[]{0,texture}); quad(commands, 16);
        commands.updateTexture(texture, 1, 1, new byte[]{0,-1,0,-1});
        shader.setConstant("index", 1);
        commands.shaderState(shader.snapshot(), new long[]{0,texture}); quad(commands, 200);
        commands.disposeTexture(texture);
        shader.setConstants("colors", FloatBuffer.wrap(new float[]{1,0,0,1,1,0,0,1}), 0, 2);
        shader.dispose();
        if (commands.submit() != 1) throw new AssertionError("Unexpected sequence");
        long tick = 0;
        for (int i = 0; i < 8; ++i) tick = GodotBridge.awaitTick(tick, 1000);
        System.out.println("BRIDGE_PROBE_PASS shader snapshots and array/scalar transport");
    }
}
