import com.sun.javafx.tk.godot.GodotBridge;

public final class NativeWindowBridgeProbe {
    private static long tick;
    private static void check(boolean value,String message) { if(!value) throw new AssertionError(message); }
    private static void waitFor(long sequence) {
        long deadline=System.nanoTime()+5_000_000_000L;
        while(GodotBridge.nativeWindowAck()<sequence) {
            tick=GodotBridge.awaitTick(tick,100);
            check(tick>=0&&System.nanoTime()<deadline,"Native acknowledgement timeout");
        }
    }
    private static void awaitWaylandRestore() {
        long deadline = System.nanoTime() + 5_000_000_000L;
        // Ack confirms command consumption. A later host tick publishes the
        // focus or activated configure that confirms the compositor restored it.
        while (GodotBridge.nativeWindowInfo(100)[9] != 0) {
            long[] child = GodotBridge.nativeWindowInfo(101);
            check(child.length == 11 && child[1] == 100 && child[7] == 1 && child[9] == 0,
                    "Child changed during owner restore");
            tick = GodotBridge.awaitTick(tick, 100);
            check(tick >= 0 && System.nanoTime() < deadline, "Native restore differs after Wayland activation");
        }
    }
    private static void hold(String title) {
        GodotBridge.hostCommand(1,0,0,title);
        for(int i=0;i<30;++i) { tick=GodotBridge.awaitTick(tick,1000); check(tick>=0,"Host stopped"); }
    }
    private static void rejected(Runnable action) {
        try { action.run(); } catch(IllegalArgumentException expected) { return; }
        throw new AssertionError("Invalid native request accepted");
    }
    private static long property(long id, int property, int a, int b, String title) {
        return GodotBridge.nativeWindowCommand(id,0,4,a,b,0,0,property,false,title);
    }
    public static void main(String[] args) {
        int[] host=GodotBridge.hostInfo(); int x=host[3]+host[0]+30, y=host[4];
        long a=GodotBridge.nativeWindowCommand(100,0,1,x,y,320,180,0,false,"独立窗口 A");
        rejected(() -> GodotBridge.nativeWindowCommand(100,0,1,x,y,320,180,0,false,"duplicate"));
        rejected(() -> GodotBridge.nativeWindowCommand(101,999,1,x,y,320,180,0,false,"owner"));
        long b=GodotBridge.nativeWindowCommand(101,100,1,x,y+240,320,180,1,false,"独立窗口 B");
        check(b==a+1,"Rejected request consumed sequence");
        GodotBridge.nativeWindowCommand(100,0,2,x,y,320,180,0,true,null);
        waitFor(GodotBridge.nativeWindowCommand(101,0,2,x,y+240,320,180,0,true,null));
        long[] first=GodotBridge.nativeWindowInfo(100), second=GodotBridge.nativeWindowInfo(101);
        check(first.length==11&&second.length==11&&first[2]!=second[2]&&first[7]==1&&second[1]==100,"Distinct native snapshot differs");
        hold("Native bridge shown");
        rejected(() -> property(100,99,0,0,null));
        rejected(() -> property(100,6,5,0,null));
        rejected(() -> property(100,7,2,0,null));
        rejected(() -> property(100,12,-1,0,null));
        rejected(() -> property(100,1,0,0,"x".repeat(4097)));
        property(100,1,0,0,"更新标题 A");
        property(100,7,0,0,null);
        property(100,9,1,0,null);
        property(100,12,200,100,null);
        property(100,13,600,400,null);
        waitFor(property(100,15,1,0,null));
        hold("Native bridge properties");
        property(100,7,1,0,null);
        property(100,9,0,0,null);
        property(100,12,0,0,null);
        property(100,13,0,0,null);
        waitFor(property(100,15,0,0,null));
        hold("Native bridge reset");
        waitFor(property(100,6,1,0,null));
        check(GodotBridge.nativeWindowInfo(100)[9]==1&&GodotBridge.nativeWindowInfo(101)[9]==0,"Independent minimize differs");
        waitFor(property(100,6,0,0,null));
        if (System.getProperty("os.name").equals("Linux")) {
            awaitWaylandRestore();
        }
        check(GodotBridge.nativeWindowInfo(100)[9]==0,"Native restore differs");
        waitFor(property(100,4,0,0,null));
        waitFor(GodotBridge.nativeWindowCommand(100,0,2,x+20,y+10,400,240,0,true,null));
        first=GodotBridge.nativeWindowInfo(100); second=GodotBridge.nativeWindowInfo(101);
        check(first[5]==400&&first[6]==240&&second[5]==320&&second[6]==180,"Independent resize differs");
        hold("Native bridge resized");
        rejected(() -> GodotBridge.nativeWindowCommand(101,0,2,x,y,0,180,0,true,null));
        waitFor(GodotBridge.nativeWindowCommand(101,0,2,x,y+240,320,180,0,false,null));
        check(GodotBridge.nativeWindowInfo(101)[7]==0&&GodotBridge.nativeWindowInfo(100)[7]==1,"Independent hide differs");
        for(int cycle=0;cycle<12;++cycle) {
            waitFor(GodotBridge.nativeWindowCommand(101,0,2,x,y+240,320,180,0,true,null));
            check(GodotBridge.nativeWindowInfo(101)[7]==1,"Native reshow differs");
            waitFor(GodotBridge.nativeWindowCommand(101,0,2,x,y+240,320,180,0,false,null));
            check(GodotBridge.nativeWindowInfo(101)[7]==0,"Native rehide differs");
        }
        hold("Native bridge hidden");
        waitFor(GodotBridge.nativeWindowCommand(100,0,3,0,0,0,0,0,false,null));
        check(GodotBridge.nativeWindowInfo(100).length==0&&GodotBridge.nativeWindowInfo(101).length==0,"Owner destroy left snapshots");
        rejected(() -> GodotBridge.nativeWindowCommand(101,0,2,x,y,320,180,0,true,null));
        rejected(() -> GodotBridge.nativeWindowCommand(100,0,1,x,y,320,180,0,false,"reuse"));
        rejected(() -> property(101,1,0,0,"closed"));
        hold("Native bridge destroyed");
        System.out.println("NATIVE_WINDOW_BRIDGE_PROBE_PASS");
    }
}
