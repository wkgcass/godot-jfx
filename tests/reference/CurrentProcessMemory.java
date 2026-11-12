import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;

/** Read-only Windows x64 metrics for this JVM's own host process. */
final class CurrentProcessMemory {
    private static final long ORIGIN=System.nanoTime();
    private static final MethodHandle CURRENT, MEMORY, HANDLES;
    static {
        if(!System.getProperty("os.name").startsWith("Windows") || ValueLayout.ADDRESS.byteSize()!=8)
            throw new UnsupportedOperationException("Process metrics require Windows x64");
        var lookup=SymbolLookup.libraryLookup("kernel32.dll",Arena.global());
        var linker=Linker.nativeLinker();
        CURRENT=linker.downcallHandle(lookup.find("GetCurrentProcess").orElseThrow(),FunctionDescriptor.of(ValueLayout.ADDRESS));
        MEMORY=linker.downcallHandle(lookup.find("K32GetProcessMemoryInfo").orElseThrow(),FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.ADDRESS,ValueLayout.JAVA_INT));
        HANDLES=linker.downcallHandle(lookup.find("GetProcessHandleCount").orElseThrow(),FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.ADDRESS));
    }
    static void report(int cycle) throws Throwable {
        report("MEDIA_CHURN_PROCESS",cycle);
    }
    static void report(String prefix,int cycle) throws Throwable {
        try(var arena=Arena.ofConfined()){
            MemorySegment process=(MemorySegment)CURRENT.invokeExact();
            // PROCESS_MEMORY_COUNTERS_EX: two DWORDs followed by nine SIZE_Ts.
            MemorySegment counters=arena.allocate(80,8),handles=arena.allocate(4,4);
            counters.set(ValueLayout.JAVA_INT,0,80);
            if((int)MEMORY.invokeExact(process,counters,80)==0 || (int)HANDLES.invokeExact(process,handles)==0)
                throw new IllegalStateException("Current-process metrics unavailable");
            System.out.println(prefix+" cycle="+cycle+" pid="+ProcessHandle.current().pid()
                +" private_bytes="+counters.get(ValueLayout.JAVA_LONG,72)
                +" working_set="+counters.get(ValueLayout.JAVA_LONG,16)
                +" handles="+Integer.toUnsignedLong(handles.get(ValueLayout.JAVA_INT,0))
                +" elapsed_ms="+(System.nanoTime()-ORIGIN)/1_000_000
                +" java_threads="+java.lang.management.ManagementFactory.getThreadMXBean().getThreadCount());
        }
        if("1".equals(System.getenv("GODOT_JFX_MEDIA_HANDLES")) && (cycle==1 || cycle%12==0 || prefix.equals("MEDIA_CHURN_IDLE")))
            CurrentProcessHandles.report(prefix,cycle);
    }
}
