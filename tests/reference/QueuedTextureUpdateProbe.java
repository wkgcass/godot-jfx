import com.sun.javafx.tk.godot.GodotBridge;
import com.sun.javafx.tk.godot.GodotRenderCommands;
import com.sun.prism.godot.GodotShader;
import java.util.*;

public final class QueuedTextureUpdateProbe {
    static void viewportState() {
        GodotRenderCommands c = new GodotRenderCommands();
        long target = 0x100000020L;
        c.allocateRenderTarget(target,16,16);
        String source = "shader_type canvas_item;\nrender_mode unshaded, blend_disabled;\nuniform vec4 tint = vec4(0.0,1.0,0.0,1.0);\nvoid fragment() { COLOR = tint; }";
        byte[] colors = new byte[16]; Arrays.fill(colors,(byte)255);
        float[] vertices = {0,0,0,0,0,0,0, 0,16,0,0,0,0,0, 16,0,0,0,0,0,0, 16,16,0,0,0,0,0};
        for (int cycle=0;cycle<4;cycle++) {
            c.selectTarget(target); c.clear();
            Map<String,GodotShader.Constant> values = cycle==0
                    ? Map.of("tint",new GodotShader.Constant(false,4,false,new int[]{0x3f800000,0,0,0x3f800000})) : Map.of();
            String selected = cycle==2 ? source.replace("0.0,1.0,0.0,1.0", "0.0,0.0,1.0,1.0") : source;
            if (cycle==3) selected = "shader_type canvas_item;\nrender_mode unshaded, blend_disabled;\nvoid fragment() { COLOR = vec4(1.0); }";
            c.shaderState(new GodotShader.Snapshot(selected,Map.of(),values));
            c.drawQuads(vertices,colors,4,1,0,0,0,1,0); c.appendEndTargetPass();
            int[] pixels=GodotBridge.readPixels(target,c.submit(),0,0,16,16);
            if(pixels==null || pixels.length!=256) throw new AssertionError("Viewport state readback missing");
            int expected=cycle==0?0xffff0000:cycle==1?0xff00ff00:cycle==2?0xff0000ff:0xffffffff;
            for(int pixel:pixels) if(pixel!=expected) throw new AssertionError("Viewport omitted uniform retained old value: cycle="+cycle+" pixel="+Integer.toHexString(pixel));
        }
        // Check the entire scalar/vector protocol through real shader execution,
        // including signed integer bits and fractional/negative floating values.
        for (boolean integer : new boolean[]{false,true}) {
            for (int components=1;components<=4;components++) {
                int[] words = new int[components];
                StringJoiner literals = new StringJoiner(",");
                for (int index=0;index<components;index++) {
                    int signed = (index % 2 == 0 ? -1 : 1) * (index + 1);
                    words[index] = integer ? signed : Float.floatToRawIntBits(signed * 0.25f);
                    literals.add(integer ? Integer.toString(signed) : Float.toString(signed * 0.25f));
                }
                String type = components==1 ? (integer ? "int" : "float") : (integer ? "ivec" : "vec")+components;
                String expected = components==1 ? literals.toString() : type+"("+literals+")";
                String condition = components==1 ? "value == "+expected : "all(equal(value,"+expected+"))";
                String code = "shader_type canvas_item;\nrender_mode unshaded, blend_disabled;\nuniform "+type+" value;\n"
                        + "void fragment() { COLOR = "+condition+" ? vec4(1.0) : vec4(1.0,0.0,0.0,1.0); }";
                c.selectTarget(target); c.clear();
                c.shaderState(new GodotShader.Snapshot(code,Map.of(),Map.of("value",
                        new GodotShader.Constant(integer,components,false,words))));
                c.drawQuads(vertices,colors,4,1,0,0,0,1,0); c.appendEndTargetPass();
                int[] pixels=GodotBridge.readPixels(target,c.submit(),0,0,16,16);
                if (pixels==null || pixels.length!=256) throw new AssertionError("Typed constant readback missing: "+type);
                for (int pixel:pixels) if(pixel!=0xffffffff) throw new AssertionError("Typed constant mismatch: "+type+" pixel="+Integer.toHexString(pixel));
            }
        }
        System.out.println("SHADER_CONSTANT_TYPES_PASS cases=8");
        c.disposeTexture(target); c.submit();
        System.out.println("VIEWPORT_STATE_PASS");
    }
    static void batchBoundary(boolean byteLimit) throws Exception {
        GodotRenderCommands c = new GodotRenderCommands();
        long target = byteLimit ? 0x100000011L : 0x100000010L;
        long filler = 0x100000012L;
        if (byteLimit) {
            c.allocateTexture(filler,512,512);
            byte[] pixels = new byte[512*512*4];
            for (int i=0;i<3;i++) c.updateTexture(filler,512,512,pixels);
        }
        c.allocateRenderTarget(target,16,16); c.selectTarget(target); c.clear();
        c.shaderState(new GodotShader.Snapshot("shader_type canvas_item; render_mode unshaded, blend_disabled;", Map.of(), Map.of()));
        var count = GodotRenderCommands.class.getDeclaredField("count");
        count.setAccessible(true); // Observe real encoded records; never fabricate transport bytes.
        int width = 7;
        while (byteLimit ? c.remainingBatchBytes() >= 176 : count.getInt(c) < 65536) {
            width = width == 7 ? 8 : 7;
            c.clip(true,0,0,width,16);
        }
        if (byteLimit && count.getInt(c) >= 65536) throw new AssertionError("Byte fixture reached command limit first");
        long before = c.getLastSubmittedSequence();
        byte[] red = new byte[16];
        for (int i=0;i<4;i++) { red[i*4]=(byte)255; red[i*4+3]=(byte)255; }
        c.drawQuads(new float[]{0,0,0,0,0,0,0, 0,16,0,0,0,0,0, 16,0,0,0,0,0,0, 16,16,0,0,0,0,0},red,4,1,0,0,0,1,0);
        if (c.getLastSubmittedSequence() <= before) throw new AssertionError("Boundary draw did not submit full batch");
        c.appendEndTargetPass();
        long sequence = c.submit();
        int[] pixels = GodotBridge.readPixels(target,sequence,0,0,16,16);
        if (pixels == null || pixels.length != 256) throw new AssertionError("Boundary readback missing");
        for (int y=0;y<16;y++) for (int x=0;x<16;x++) {
            int expected = x < width ? 0xffff0000 : 0;
            if (pixels[y*16+x] != expected) throw new AssertionError("Cross-batch shader/clip mismatch at " + x + "," + y + ": " + Integer.toHexString(pixels[y*16+x]));
        }
        c.disposeTexture(target);
        if (byteLimit) c.disposeTexture(filler);
        c.submit();
        System.out.println(byteLimit ? "BATCH_BYTE_BOUNDARY_PIXELS_PASS" : "BATCH_BOUNDARY_PIXELS_PASS");
    }
    static void draw(GodotRenderCommands c, GodotShader s, long target, long texture) {
        c.selectTarget(target); c.clear(); c.shaderState(s.snapshot(),new long[]{texture});
        byte[] colors=new byte[16]; Arrays.fill(colors,(byte)255);
        c.drawQuads(new float[]{0,0,0,0,0,0,0, 0,16,0,0,1,0,1, 16,0,0,1,0,1,0, 16,16,0,1,1,1,1},colors,4,1,0,0,0,1,0);
        c.appendEndTargetPass();
    }
    public static void main(String[] args) throws Exception {
        if ("1".equals(System.getenv("GODOT_JFX_TEST_VIEWPORT_STATE"))) {
            viewportState();
            System.out.println("QUEUED_TEXTURE_UPDATE_PASS");
            return;
        }
        GodotRenderCommands c=new GodotRenderCommands();
        long texture=0x100000001L, first=0x100000002L, second=0x100000003L;
        c.allocateTexture(texture,1,1); c.updateTexture(texture,1,1,new byte[]{(byte)255,0,0,(byte)255});
        c.allocateRenderTarget(first,16,16); c.allocateRenderTarget(second,16,16);
        GodotShader s=new GodotShader("shader_type canvas_item;\nrender_mode unshaded, blend_premul_alpha;\nvarying vec2 godot_uv0;\nvoid vertex() {\ngodot_uv0 = UV;\n}\nuniform sampler2D inputTex;\nvec4 paint(vec2 uv) { return texture(inputTex,uv); }\nvoid fragment() { COLOR = paint(godot_uv0); }",Map.of("inputTex",0),Map.of(),selected -> {});
        draw(c,s,first,texture);
        c.updateTexture(texture,1,1,new byte[]{0,0,(byte)255,(byte)255});
        draw(c,s,second,texture);
        long sequence=c.submit(); // Both passes and the intervening update in one transfer.
        for(long target:new long[]{first,second}) {
            int expected=target==first?0xffff0000:0xff0000ff;
            int[] pixels=GodotBridge.readPixels(target,sequence,0,0,16,16);
            if(pixels==null || pixels.length!=256) throw new AssertionError("Missing target readback");
            for(int pixel:pixels) if(pixel!=expected) throw new AssertionError("Queued texture version changed: "+Integer.toHexString(pixel)+" expected "+Integer.toHexString(expected));
        }
        c.disposeTexture(texture); c.disposeTexture(first); c.disposeTexture(second); c.submit(); s.dispose();
        if ("1".equals(System.getenv("GODOT_JFX_TEST_BATCH_BOUNDARY"))) {
            batchBoundary(false);
            batchBoundary(true);
        }
        System.out.println("QUEUED_TEXTURE_UPDATE_PASS");
    }
}
