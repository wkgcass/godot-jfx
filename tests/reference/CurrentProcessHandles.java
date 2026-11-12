import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;
import java.nio.charset.StandardCharsets;
import java.util.TreeMap;

/** Optional current-process PSS handle-type census. Never logs object names. */
final class CurrentProcessHandles {
    private static final SymbolLookup API=SymbolLookup.libraryLookup("kernel32.dll",Arena.global());
    private static MethodHandle bind(String name,FunctionDescriptor descriptor){
        return Linker.nativeLinker().downcallHandle(API.find(name).orElseThrow(),descriptor);
    }
    private static final MethodHandle CURRENT=bind("GetCurrentProcess",FunctionDescriptor.of(ValueLayout.ADDRESS));
    private static final MethodHandle CAPTURE=bind("PssCaptureSnapshot",FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.JAVA_INT,ValueLayout.JAVA_INT,ValueLayout.ADDRESS));
    private static final MethodHandle FREE=bind("PssFreeSnapshot",FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.ADDRESS));
    private static final MethodHandle CREATE_MARKER=bind("PssWalkMarkerCreate",FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.ADDRESS));
    private static final MethodHandle FREE_MARKER=bind("PssWalkMarkerFree",FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS));
    private static final MethodHandle WALK=bind("PssWalkSnapshot",FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.ADDRESS,ValueLayout.JAVA_INT));
    private static final MethodHandle QUERY_TYPE=Linker.nativeLinker().downcallHandle(
        SymbolLookup.libraryLookup("ntdll.dll",Arena.global()).find("NtQueryObject").orElseThrow(),
        FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.JAVA_INT,ValueLayout.ADDRESS));
    private static void check(int result,String api){if(result!=0)throw new IllegalStateException(api+" error "+result);}
    public static void main(String[] args) throws Throwable {
        for(int i=1;i<=3;i++)report("SELF_CHECK",i);
    }
    static void report(String phase,int cycle) throws Throwable {
        try(var arena=Arena.ofConfined()){
            MemorySegment process=(MemorySegment)CURRENT.invokeExact();
            MemorySegment snapshotOut=arena.allocate(ValueLayout.ADDRESS),markerOut=arena.allocate(ValueLayout.ADDRESS);
            // Handles, names and basic information only: no memory/VA clone.
            check((int)CAPTURE.invokeExact(process,0x1c,0,snapshotOut),"PssCaptureSnapshot");
            MemorySegment snapshot=snapshotOut.get(ValueLayout.ADDRESS,0);
            try {
                check((int)CREATE_MARKER.invokeExact(MemorySegment.NULL,markerOut),"PssWalkMarkerCreate");
                MemorySegment marker=markerOut.get(ValueLayout.ADDRESS,0);
                try {
                    // Windows x64 PSS_HANDLE_ENTRY per installed SDK ProcessSnapshot.h.
                    MemorySegment entry=arena.allocate(136,8);
                    MemorySegment typeInfo=arena.allocate(4096,8),typeSize=arena.allocate(4,4);
                    var counts=new TreeMap<String,Integer>();
                    while(true){
                        int result=(int)WALK.invokeExact(snapshot,2,marker,entry,136);
                        if(result==259)break; // ERROR_NO_MORE_ITEMS
                        check(result,"PssWalkSnapshot");
                        int bytes=Short.toUnsignedInt(entry.get(ValueLayout.JAVA_SHORT,56));
                        MemorySegment name=entry.get(ValueLayout.ADDRESS,64);
                        if(bytes>256 || (bytes&1)!=0)throw new IllegalStateException("Invalid PSS type name length");
                        // Windows may not supply names for every captured handle.
                        String type=bytes==0 || name.equals(MemorySegment.NULL) ? "unavailable" :
                            new String(name.reinterpret(bytes).toArray(ValueLayout.JAVA_BYTE),StandardCharsets.UTF_16LE);
                        if(type.equals("unavailable")){
                            // PSS omits some type strings. Query only the type of
                            // that same-process handle; never query its object name.
                            int status=(int)QUERY_TYPE.invokeExact(entry.get(ValueLayout.ADDRESS,0),2,typeInfo,4096,typeSize);
                            if(status==0){
                                int length=Short.toUnsignedInt(typeInfo.get(ValueLayout.JAVA_SHORT,0));
                                MemorySegment pointer=typeInfo.get(ValueLayout.ADDRESS,8);
                                if(length>0 && length<=256 && (length&1)==0 && !pointer.equals(MemorySegment.NULL))
                                    type=new String(pointer.reinterpret(length).toArray(ValueLayout.JAVA_BYTE),StandardCharsets.UTF_16LE);
                            }else type="unavailable_"+Integer.toHexString(status);
                        }
                        type=type.replace("\u0000", "");
                        counts.merge(type,1,Integer::sum);
                    }
                    System.out.println("MEDIA_HANDLE_TYPES phase="+phase+" cycle="+cycle+" counts="+counts);
                }finally{check((int)FREE_MARKER.invokeExact(marker),"PssWalkMarkerFree");}
            }finally{check((int)FREE.invokeExact(process,snapshot),"PssFreeSnapshot");}
        }
        if("1".equals(System.getenv("GODOT_JFX_MEDIA_PROVIDERS")))Providers.report(phase,cycle);
    }

    /** Read-only ETW registration metadata, filtered to this process before logging. */
    private static final class Providers {
        private static final MethodHandle ENUM=Linker.nativeLinker().downcallHandle(
                SymbolLookup.libraryLookup("advapi32.dll",Arena.global()).find("EnumerateTraceGuidsEx").orElseThrow(),
                FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.JAVA_INT,ValueLayout.ADDRESS,
                        ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.JAVA_INT,ValueLayout.ADDRESS));
        private static TreeMap<String,Integer> previous=new TreeMap<>();
        private static MemorySegment query(Arena arena,int kind,MemorySegment input) throws Throwable {
            var size=arena.allocate(4,4);
            var output=MemorySegment.NULL;
            int capacity=0;
            for(int attempt=0;attempt<5;attempt++){
                int result=(int)ENUM.invokeExact(kind,input,(int)input.byteSize(),output,capacity,size);
                int used=size.get(ValueLayout.JAVA_INT,0);
                if(result==0)return output.asSlice(0,used);
                if(result==4201 || result==2)return MemorySegment.NULL; // provider disappeared
                if(result!=122)throw new IllegalStateException("EnumerateTraceGuidsEx error "+result);
                if(used<=0 || used>4*1024*1024)throw new IllegalStateException("Invalid ETW metadata size "+used);
                capacity=used;output=arena.allocate(capacity,8);
            }
            throw new IllegalStateException("ETW registration list kept changing");
        }
        private static String guid(MemorySegment value){
            return String.format("%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                    value.get(ValueLayout.JAVA_INT,0),Short.toUnsignedInt(value.get(ValueLayout.JAVA_SHORT,4)),
                    Short.toUnsignedInt(value.get(ValueLayout.JAVA_SHORT,6)),
                    value.get(ValueLayout.JAVA_BYTE,8),value.get(ValueLayout.JAVA_BYTE,9),
                    value.get(ValueLayout.JAVA_BYTE,10),value.get(ValueLayout.JAVA_BYTE,11),
                    value.get(ValueLayout.JAVA_BYTE,12),value.get(ValueLayout.JAVA_BYTE,13),
                    value.get(ValueLayout.JAVA_BYTE,14),value.get(ValueLayout.JAVA_BYTE,15));
        }
        static void report(String phase,int cycle) throws Throwable {
            var counts=new TreeMap<String,Integer>();
            try(var arena=Arena.ofConfined()){
                var list=query(arena,0,MemorySegment.NULL);
                if(list.byteSize()%16!=0)throw new IllegalStateException("Invalid GUID list length");
                for(long offset=0;offset<list.byteSize();offset+=16){
                    var id=list.asSlice(offset,16);
                    try(var instanceArena=Arena.ofConfined()){
                        var info=query(instanceArena,1,id);
                        if(info.byteSize()==0)continue;
                        int instances=info.get(ValueLayout.JAVA_INT,0);
                        long entry=8;
                        for(int i=0;i<instances;i++){
                            // TRACE_GUID_INFO (8 bytes), TRACE_PROVIDER_INSTANCE_INFO (16 bytes).
                            if(entry+16>info.byteSize())throw new IllegalStateException("Truncated ETW instance");
                            long pid=Integer.toUnsignedLong(info.get(ValueLayout.JAVA_INT,entry+8));
                            if(pid==ProcessHandle.current().pid())counts.merge(guid(id),1,Integer::sum);
                            long next=Integer.toUnsignedLong(info.get(ValueLayout.JAVA_INT,entry));
                            if(i+1<instances && next<16)throw new IllegalStateException("Invalid ETW instance offset");
                            entry+=next;
                        }
                    }
                }
            }
            var changes=new TreeMap<String,Integer>();
            counts.forEach((id,count)->{int delta=count-previous.getOrDefault(id,0);if(delta!=0)changes.put(id,delta);});
            previous.forEach((id,count)->{if(!counts.containsKey(id))changes.put(id,-count);});
            System.out.println("MEDIA_ETW_PROVIDERS phase="+phase+" cycle="+cycle+" total="+
                    counts.values().stream().mapToInt(Integer::intValue).sum()+" delta="+changes);
            previous=counts;
        }
    }
}
