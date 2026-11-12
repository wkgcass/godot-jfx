import com.sun.prism.godot.GodotShader;
import com.sun.javafx.tk.godot.GodotRenderCommands;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Supplier;

public class ShaderSourceCacheProbe {
    static Object field(Object instance,String name) throws Exception {
        var f=instance.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(instance);
    }
    static void rejected(Runnable action) {
        try { action.run(); throw new AssertionError("Invalid shader accepted"); }
        catch(IllegalArgumentException expected) {}
    }
    public static void main(String[] args) throws Exception {
        var type=Class.forName("com.sun.prism.godot.GodotShaderSourceCache");
        var adapt=type.getDeclaredMethod("adapt",String.class,Object.class,Supplier.class);adapt.setAccessible(true);
        var calls=new AtomicInteger();
        Supplier<String> conversion=()->{calls.incrementAndGet();return "converted";};
        for(int i=0;i<10;i++) adapt.invoke(null,"source",Map.of("sampler",0),conversion);
        if(calls.get()!=1) throw new AssertionError("Repeated immutable source was converted again");
        adapt.invoke(null,"source",Map.of("sampler",1),conversion);
        if(calls.get()!=2) throw new AssertionError("Different sampler mapping collided");
        for(int i=0;i<100;i++) adapt.invoke(null,"source"+i+" ".repeat(8192),Map.of(),conversion);
        var local=type.getDeclaredField("LOCAL");local.setAccessible(true);
        var cache=((ThreadLocal<?>)local.get(null)).get();
        if(((Map<?,?>)field(cache,"entries")).size()>64 || (int)field(cache,"characters")>524288) throw new AssertionError("Unbounded adaptation cache");
        int before=calls.get();
        for(int i=0;i<2;i++) adapt.invoke(null,"x".repeat(524289),Map.of(),conversion);
        if(calls.get()!=before+2) throw new AssertionError("Oversized source retained");

        var encoder=new GodotRenderCommands();
        for(int i=0;i<100;i++) encoder.shaderState(new GodotShader.Snapshot("source"+i,Map.of(),Map.of()));
        if(((Map<?,?>)field(encoder,"shaderSources")).size()!=64) throw new AssertionError("Transport cache entry limit differs");
        for(int i=0;i<3;i++) encoder.shaderState(new GodotShader.Snapshot("x".repeat(262143)+i,Map.of(),Map.of()));
        if((int)field(encoder,"shaderSourceBytes")>524288) throw new AssertionError("Transport cache byte limit differs");
        for(String source:List.of("","\0","中文","x".repeat(262145)))
            rejected(()->encoder.shaderState(new GodotShader.Snapshot(source,Map.of(),Map.of())));
        var value=new GodotShader.Constant(true,1,false,new int[]{1});
        for(String name:List.of("a","_","a0","a".repeat(128)))
            encoder.shaderState(new GodotShader.Snapshot("valid",Map.of(),Map.of(name,value)));
        for(String name:List.of("","0a","a-b","中文","a".repeat(129)))
            rejected(()->encoder.shaderState(new GodotShader.Snapshot("valid",Map.of(),Map.of(name,value))));
        // Only source text is cached: changing uniforms must survive a cache hit.
        var composite=Class.forName("com.sun.prism.godot.GodotComposite");
        var mode=Class.forName("com.sun.prism.CompositeMode");
        var apply=composite.getDeclaredMethod("apply",GodotShader.Snapshot.class,mode);apply.setAccessible(true);
        var src=mode.getField("SRC").get(null);
        for(int i=1;i<=2;i++) {
            var input=new GodotShader.Snapshot("shader_type canvas_item; render_mode blend_premul_alpha;",Map.of(),Map.of("value",new GodotShader.Constant(true,1,false,new int[]{i})));
            var output=(GodotShader.Snapshot)apply.invoke(null,input,src);
            if(output.constants().get("value").words()[0]!=i || !output.source().contains("blend_disabled")) throw new AssertionError("Cached source captured dynamic constants");
        }
        System.out.println("SHADER_SOURCE_CACHE_PROBE_PASS");
    }
}
