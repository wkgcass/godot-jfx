using System;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Runtime.InteropServices;

// Drives only the exact random-token test dialogs, never unrelated windows.
public static class FileDialogDriver {
    delegate bool EnumCallback(IntPtr window,IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumCallback callback,IntPtr data);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window,StringBuilder text,int size);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder text,int size);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr window,uint command);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll")] static extern IntPtr GetDlgItem(IntPtr window,int id);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window,uint message,IntPtr wparam,IntPtr lparam);
    static string Title(IntPtr window) {var b=new StringBuilder(1024); GetWindowText(window,b,b.Capacity); return b.ToString();}
    static IntPtr Find(string title) {
        IntPtr result=IntPtr.Zero;
        EnumWindows((w,d) => {if(Title(w)==title || Title(w)==title+" (DEBUG)"){result=w;return false;}return true;},IntPtr.Zero);
        return result;
    }
    public static Task<string> Start(string token,CancellationToken cancellation,bool stopping,string ready) {
        return Task.Run(() => {
            var report=new StringBuilder();
            uint process=0;
            for(int step=0;step<(stopping ? 1 : 6);step++) {
                IntPtr dialog=IntPtr.Zero;
                var deadline=DateTime.UtcNow.AddSeconds(45);
                while(dialog==IntPtr.Zero) {
                    cancellation.ThrowIfCancellationRequested();
                    if(DateTime.UtcNow>deadline) throw new Exception("Dialog not found for case "+step);
                    dialog=Find(token+" case "+step);
                    Thread.Sleep(25);
                }
                uint current; GetWindowThreadProcessId(dialog,out current);
                if(step==0) {
                    var root=Find(token+" root");
                    if(root==IntPtr.Zero) throw new Exception("Root owner not found");
                    GetWindowThreadProcessId(root,out process);
                }
                if(current!=process) throw new Exception("Dialog belongs to another process");
                var cls=new StringBuilder(128); GetClassName(dialog,cls,128);
                if(cls.ToString()!="#32770") throw new Exception("Not a Windows common dialog: "+cls);
                var owner=GetWindow(dialog,4); // GW_OWNER
                if(step==4) {
                    if(owner!=IntPtr.Zero) throw new Exception("Unowned chooser acquired owner");
                    foreach(string name in new[]{" root"," child"}) {
                        var restored=Find(token+name);
                        if(restored==IntPtr.Zero || !IsWindowEnabled(restored))
                            throw new Exception("Owner chain was not restored: "+name);
                    }
                }
                else {
                    string expected=token+(step==1 || step==3 || step==5 ? " child" : " root");
                    if(Title(owner)!=expected && Title(owner)!=expected+" (DEBUG)") throw new Exception("Wrong native owner: "+Title(owner));
                    if(IsWindowEnabled(owner)) throw new Exception("Dialog owner was not disabled");
                    if(step==1 || step==3 || step==5) {
                        var ancestor=Find(token+" root");
                        if(ancestor==IntPtr.Zero || IsWindowEnabled(ancestor))
                            throw new Exception("Dialog owner ancestor was not disabled");
                    }
                }
                report.AppendLine("DIALOG_NATIVE case="+step+" owner="+Title(owner));
                Console.WriteLine("DIALOG_NATIVE case="+step);
                if(stopping) { System.IO.File.WriteAllText(ready,"native-dialog-observed"); break; }
                Thread.Sleep(500); // Confirm the FX loop continues while Show is modal.
                if(step!=5) {
                    IntPtr button=IntPtr.Zero;
                    var readyDeadline=DateTime.UtcNow.AddSeconds(10);
                    while(button==IntPtr.Zero || !IsWindowVisible(dialog) || !IsWindowEnabled(button)) {
                        cancellation.ThrowIfCancellationRequested();
                        if(DateTime.UtcNow>readyDeadline) throw new Exception("Dialog button not ready in case "+step);
                        button=GetDlgItem(dialog,step==4 ? 2 : 1);
                        Thread.Sleep(25);
                    }
                    Console.WriteLine("DIALOG_BUTTON case="+step+" hwnd="+button);
                    if(!PostMessage(dialog,0x0111,new IntPtr(step==4 ? 2 : 1),button)) throw new Exception("Cannot submit test dialog");
                }
            }
            return report+"FILE_DIALOG_NATIVE_PASS";
        },cancellation);
    }
}
