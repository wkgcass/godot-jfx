import com.sun.glass.ui.Screen;
import com.sun.glass.ui.godot.GodotScreenLayout;

/** Synthetic geometry checks do not change the user's display configuration. */
public final class ScreenLayoutProbe {
    private static int[] monitor(int id,int x,int y,int w,int h,int dpi) {
        return new int[]{id,x,y,w,h,x,y,w,h-40,dpi};
    }
    private static Screen[] layout(boolean hidpi,int[]... rows) {
        int[] data=new int[rows.length*10];
        for(int i=0;i<rows.length;i++) System.arraycopy(rows[i],0,data,i*10,10);
        return GodotScreenLayout.create(data,hidpi);
    }
    private static void bounds(Screen s,int x,int y,int w,int h) {
        if(s.getX()!=x || s.getY()!=y || s.getWidth()!=w || s.getHeight()!=h)
            throw new AssertionError("Bounds: "+s+" expected "+x+","+y+","+w+","+h);
        float tolerance=.5f/s.getPlatformScaleX()+.0001f;
        if(Math.abs(s.fromPlatformX(s.toPlatformX(x+50))-x-50)>tolerance || Math.abs(s.fromPlatformY(s.toPlatformY(y+50))-y-50)>tolerance)
            throw new AssertionError("Coordinate round trip");
    }
    public static void main(String[] args) {
        var main=monitor(1,0,0,3840,2160,192);
        var s=layout(true,main,monitor(2,3840,0,1920,1080,96));
        bounds(s[0],0,0,1920,1080); bounds(s[1],1920,0,1920,1080);
        if(s[0].getVisibleHeight()!=1060 || s[0].getResolutionX()!=96 || s[0].getPlatformWidth()!=3840 || s[0].getPlatformScaleX()!=2)
            throw new AssertionError("Work area, DPI or platform metadata");
        s=layout(true,main,monitor(2,-1920,1080,1920,1080,96));
        bounds(s[1],-1920,0,1920,1080); // bottom-aligned physical monitors
        s=layout(true,main,monitor(2,0,-1200,1920,1200,120));
        bounds(s[1],0,-960,1536,960);
        s=layout(true,main,monitor(2,3840,540,1920,1080,96));
        bounds(s[1],1920,0,1920,1080); // align the midpoint of vertical overlap
        s=layout(true,main,monitor(2,3840,0,1920,1080,96),monitor(3,5760,0,2560,1440,144));
        bounds(s[2],3840,0,1707,960); // propagation through a neighboring monitor
        s=layout(true,main,monitor(2,9000,500,1920,1080,96));
        bounds(s[1],9000,500,1920,1080); // disconnected group retains its anchor
        s=layout(false,main,monitor(2,-1920,1080,1920,1080,96));
        bounds(s[0],0,0,3840,2160); bounds(s[1],-1920,1080,1920,1080);
        System.out.println("SCREEN_LAYOUT_PROBE_PASS");
    }
}
