using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

// Preserve native text bytes: OLE String conversion can change CF_TEXT's codepage.
public static class ClipboardSnapshot {
    [DllImport("user32.dll",SetLastError=true)] static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll")] static extern bool CloseClipboard();
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint RegisterClipboardFormat(string name);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClipboardFormatName(uint format, System.Text.StringBuilder name, int maxCount);
    [DllImport("user32.dll",SetLastError=true)] static extern uint EnumClipboardFormats(uint format);
    [DllImport("user32.dll")] static extern IntPtr GetClipboardData(uint format);
    [DllImport("user32.dll")] static extern IntPtr SetClipboardData(uint format, IntPtr data);
    [DllImport("user32.dll")] static extern bool EmptyClipboard();
    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern IntPtr GetClipboardOwner();
    [DllImport("kernel32.dll")] static extern UIntPtr GlobalSize(IntPtr data);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalAlloc(uint flags, UIntPtr size);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr data);
    [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr data);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalFree(IntPtr data);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern int WideCharToMultiByte(uint codePage, uint flags, string wide, int wideLength, byte[] multi, int multiLength, IntPtr defaultChar, IntPtr usedDefault);
    // Exact inverse of the native reader's MultiByteToWideChar(CP_ACP).
    public static byte[] AnsiBytes(string text) {
        int length=WideCharToMultiByte(0,0,text,text.Length,null,0,IntPtr.Zero,IntPtr.Zero);
        if(length<=0) throw new Exception("ANSI conversion failed");
        var bytes=new byte[length];
        if(WideCharToMultiByte(0,0,text,text.Length,bytes,length,IntPtr.Zero,IntPtr.Zero)!=length) throw new Exception("ANSI conversion failed");
        return bytes;
    }
    static void Open(IntPtr owner) {
        int error=0;
        for (int i=0;i<25;i++) {
            if(OpenClipboard(owner)) return;
            error=Marshal.GetLastWin32Error();
            Thread.Sleep(10);
        }
        throw new Exception("Cannot open clipboard for snapshot/restore; Windows error "+error);
    }
    // Names of registered formats (>=0xC000) seen at capture time; restore
    // re-registers them and expects the same session-global IDs.
    static readonly Dictionary<uint,string> RegisteredNames=new Dictionary<uint,string>();
    public static uint CapturedSequence { get; private set; }
    public static Dictionary<uint,string> RegisteredFormatNames() { return new Dictionary<uint,string>(RegisteredNames); }
    public static void RequireUnchanged(uint expected, uint actual) {
        if(expected==0 || actual==0 || expected!=actual)
            throw new InvalidOperationException("Clipboard changed or sequence unavailable; newer content preserved");
    }
    // A movable byte block is not proof that its contents survive ownership
    // transfer. OLE/private formats can contain process-specific metadata.
    public static bool IsPortableRegisteredFormat(string name) {
        return name=="HTML Format" || name=="Rich Text Format"
            || name=="UniformResourceLocator" || name=="UniformResourceLocatorW"
            || (name!=null && name.StartsWith("application/x-godot-custom-",StringComparison.Ordinal));
    }
    // Bound the complete backup, not each format independently. Pure arithmetic
    // allows boundary checks without opening or changing the system clipboard.
    public const ulong MaxSnapshotBytes = 256UL * 1024 * 1024;
    public static ulong AddSnapshotBytes(ulong total, ulong size) {
        if(total>MaxSnapshotBytes || size==0 || size>MaxSnapshotBytes-total)
            throw new InvalidOperationException("Clipboard snapshot exceeds 256 MiB total or contains an empty block; writes refused");
        return total+size;
    }
    static void ValidateBlocks(Dictionary<uint,byte[]> blocks) {
        ulong total=0;
        foreach(var pair in blocks) {
            if(pair.Value==null) throw new ArgumentException("Clipboard block is null");
            total=AddSnapshotBytes(total,(ulong)pair.Value.Length);
        }
    }
    // Until insertion succeeds the dictionary does not own this native block.
    static void TrackBlock(Dictionary<uint,IntPtr> blocks, uint format, IntPtr handle) {
        try { blocks.Add(format,handle); }
        catch { GlobalFree(handle); throw; }
    }
    // Zero means either normal completion or failure; never accept a partial
    // enumeration as a complete backup before destructive test publication.
    static List<uint> EnumerateFormats(Func<uint,uint> next, Func<int> lastError) {
        var formats=new List<uint>();
        uint previous=0;
        while(true) {
            uint format=next(previous);
            if(format==0) {
                int error=lastError();
                if(error!=0) throw new InvalidOperationException("Clipboard format enumeration failed; test writes refused. Windows error "+error);
                return formats;
            }
            formats.Add(format);
            previous=format;
        }
    }
    public static Dictionary<uint,byte[]> Capture() {
        var result=new Dictionary<uint,byte[]>(); Open(IntPtr.Zero);
        RegisteredNames.Clear();
        try {
            ulong total=0;
            var present=EnumerateFormats(EnumClipboardFormats,Marshal.GetLastWin32Error);
            foreach(uint f in present) {
                // Handle views synthesized from a byte sibling (CF_BITMAP/CF_PALETTE from
                // CF_DIB(V5), CF_METAFILEPICT from CF_ENHMETAFILE) regenerate on restore;
                // alone they cannot be snapshotted by bytes and refuse the test.
                if(f==2 && (present.Contains(8) || present.Contains(17))) continue;
                if(f==3 && present.Contains(14)) continue;
                if(f==9 && (present.Contains(8) || present.Contains(17))) continue;
                // Text formats plus CF_DIB(8)/CF_HDROP(15)/CF_DIBV5(17) snapshot as raw bytes.
                if(f<0xC000 && f!=1 && f!=7 && f!=13 && f!=16 && f!=8 && f!=15 && f!=17)
                    throw new Exception("Unsupported native clipboard format "+f+"; test writes refused");
                if(f>=0xC000) {
                    // Only formats with a known portable payload can be restored
                    // as bytes. Unknown/private data must leave the test unwritten.
                    var name=new System.Text.StringBuilder(260);
                    if(GetClipboardFormatName(f,name,name.Capacity)<=0)
                        throw new Exception("Unnamed registered clipboard format "+f+"; test writes refused");
                    if(!IsPortableRegisteredFormat(name.ToString()))
                        throw new Exception("Unverified registered clipboard format "+name+"; test writes refused");
                    RegisteredNames[f]=name.ToString();
                }
                IntPtr h=GetClipboardData(f); ulong size=GlobalSize(h).ToUInt64();
                total=AddSnapshotBytes(total,size);
                IntPtr p=GlobalLock(h); if(p==IntPtr.Zero) throw new Exception("Cannot lock clipboard snapshot");
                try { var bytes=new byte[(int)size]; Marshal.Copy(p,bytes,0,bytes.Length); result.Add(f,bytes); }
                finally { GlobalUnlock(h); }
            }
            CapturedSequence=GetClipboardSequenceNumber();
        } finally { CloseClipboard(); }
        return result;
    }
    // Raw bytes of one format for the comparison side; null when the format is absent.
    public static byte[] ReadFormat(uint format) {
        Open(IntPtr.Zero);
        try {
            IntPtr h=GetClipboardData(format);
            if(h==IntPtr.Zero) return null;
            ulong size=GlobalSize(h).ToUInt64();
            if(size==0 || size>MaxSnapshotBytes) throw new Exception("Cannot read clipboard allocation");
            IntPtr p=GlobalLock(h); if(p==IntPtr.Zero) throw new Exception("Cannot lock clipboard data");
            try { var bytes=new byte[(int)size]; Marshal.Copy(p,bytes,0,bytes.Length); return bytes; }
            finally { GlobalUnlock(h); }
        } finally { CloseClipboard(); }
    }
    public static uint RegisterFormat(string name) {
        uint format=RegisterClipboardFormat(name);
        if(format==0) throw new Exception("Cannot register clipboard format "+name);
        return format;
    }
    // Exact publication of pre-encoded blocks; nothing is synthesized or converted.
    public static uint WriteRaw(Dictionary<uint,byte[]> blocks, IntPtr owner) {
        if(owner==IntPtr.Zero) throw new ArgumentException("Clipboard publication requires a window owner",nameof(owner));
        ValidateBlocks(blocks);
        var handles=new Dictionary<uint,IntPtr>();
        try {
            foreach(var pair in blocks) {
                IntPtr h=GlobalAlloc(0x42,(UIntPtr)pair.Value.Length);
                if(h==IntPtr.Zero) throw new Exception("Clipboard write allocation failed");
                TrackBlock(handles,pair.Key,h); IntPtr p=GlobalLock(h);
                if(p==IntPtr.Zero) throw new Exception("Clipboard write lock failed");
                try { Marshal.Copy(pair.Value,0,p,pair.Value.Length); } finally { GlobalUnlock(h); }
            }
            var formats=new List<uint>(handles.Keys); // Allocate before destructive publication.
            Open(owner);
            try {
                if(!EmptyClipboard()) throw new Exception("Clipboard write clear failed");
                foreach(uint f in formats) {
                    if(SetClipboardData(f,handles[f])==IntPtr.Zero) throw new Exception("Clipboard write publication failed");
                    handles[f]=IntPtr.Zero;
                }
            } finally { CloseClipboard(); }
            // CloseClipboard may synthesize additional formats and advance the
            // sequence. Sample after publication completes, but reacquire the
            // lock and verify ownership before accepting that sequence: an
            // external writer in the gap must never be mistaken for our write.
            Open(owner);
            try {
                if(GetClipboardOwner()!=owner)
                    throw new InvalidOperationException("Clipboard owner changed after publication; newer content preserved");
                uint sequence=GetClipboardSequenceNumber();
                if(sequence==0) throw new InvalidOperationException("Clipboard sequence unavailable after publication");
                return sequence;
            } finally { CloseClipboard(); }
        } finally { foreach(var h in handles.Values) if(h!=IntPtr.Zero) GlobalFree(h); }
    }
    public static void Restore(Dictionary<uint,byte[]> snapshot, IntPtr owner, uint expectedSequence) {
        if(owner==IntPtr.Zero) throw new ArgumentException("Clipboard restoration requires a window owner",nameof(owner));
        ValidateBlocks(snapshot);
        var blocks=new Dictionary<uint,IntPtr>();
        try {
            foreach(var pair in snapshot) {
                if(pair.Key>=0xC000) {
                    // Same session-global ID must come back for the captured name.
                    if(!RegisteredNames.TryGetValue(pair.Key,out var name) || RegisterClipboardFormat(name)!=pair.Key)
                        throw new Exception("Registered clipboard format "+pair.Key+" changed identity");
                }
                IntPtr h=GlobalAlloc(0x42,(UIntPtr)pair.Value.Length);
                if(h==IntPtr.Zero) throw new Exception("Clipboard restore allocation failed");
                TrackBlock(blocks,pair.Key,h); IntPtr p=GlobalLock(h);
                if(p==IntPtr.Zero) throw new Exception("Clipboard restore lock failed");
                try { Marshal.Copy(pair.Value,0,p,pair.Value.Length); } finally { GlobalUnlock(h); }
            }
            var formats=new List<uint>(blocks.Keys); // Allocate before clearing existing content.
            Open(owner);
            try {
                // Compare under the same lock used for EmptyClipboard: no
                // external writer can race the check and the restoration.
                RequireUnchanged(expectedSequence,GetClipboardSequenceNumber());
                if(!EmptyClipboard()) throw new Exception("Clipboard restore clear failed");
                foreach(uint f in formats) {
                    if(SetClipboardData(f,blocks[f])==IntPtr.Zero) throw new Exception("Clipboard restore publication failed");
                    blocks[f]=IntPtr.Zero;
                }
            } finally { CloseClipboard(); }
        } finally { foreach(var h in blocks.Values) if(h!=IntPtr.Zero) GlobalFree(h); }
        var actual=Capture();
        foreach(var pair in snapshot) {
            if(!actual.TryGetValue(pair.Key,out var bytes) || bytes.Length!=pair.Value.Length)
                throw new Exception("Restored clipboard allocation differs");
            for(int i=0;i<bytes.Length;i++) if(bytes[i]!=pair.Value[i])
                throw new Exception("Restored clipboard bytes differ");
        }
    }
}
