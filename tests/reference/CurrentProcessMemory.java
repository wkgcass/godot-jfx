import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;

/** Read-only per-OS metrics for this JVM's own host process (Windows x64 and macOS). */
final class CurrentProcessMemory {
    private static final long ORIGIN=System.nanoTime();
    private static final String OS=System.getProperty("os.name","");
    private static final boolean MAC=OS.startsWith("Mac");
    private static final MethodHandle CURRENT, MEMORY, HANDLES;
    static {
        if(MAC) {
            CURRENT=null;MEMORY=null;HANDLES=null;
        } else {
            if(!OS.startsWith("Windows") || ValueLayout.ADDRESS.byteSize()!=8)
                throw new UnsupportedOperationException("Process metrics require Windows x64 or macOS");
            var lookup=SymbolLookup.libraryLookup("kernel32.dll",Arena.global());
            var linker=Linker.nativeLinker();
            CURRENT=linker.downcallHandle(lookup.find("GetCurrentProcess").orElseThrow(),FunctionDescriptor.of(ValueLayout.ADDRESS));
            MEMORY=linker.downcallHandle(lookup.find("K32GetProcessMemoryInfo").orElseThrow(),FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.ADDRESS,ValueLayout.JAVA_INT));
            HANDLES=linker.downcallHandle(lookup.find("GetProcessHandleCount").orElseThrow(),FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.ADDRESS));
        }
    }
    static void report(int cycle) throws Throwable {
        report("MEDIA_CHURN_PROCESS",cycle);
    }
    static void report(String prefix,int cycle) throws Throwable {
        long privateBytes,workingSet,handles;
        if(MAC) {
            // FFM downcalls to proc_pid_rusage/proc_pidinfo reliably crash this
            // JDK (Temurin 25.0.5+8, aarch64 C2: compiledIC "stub not found" and
            // metaspace corruption), so sample the process from userland tools:
            // ps RSS stands in for both memory fields and /dev/fd for handles.
            long pid=ProcessHandle.current().pid();
            var reader=new java.io.BufferedReader(new java.io.InputStreamReader(
                new ProcessBuilder("ps","-o","rss=","-p",Long.toString(pid)).start().getInputStream()));
            String line=reader.readLine();
            if(line==null || line.isBlank())throw new IllegalStateException("ps rss unavailable");
            workingSet=Long.parseLong(line.trim())*1024;
            privateBytes=workingSet;
            String[] fds=new java.io.File("/dev/fd").list();
            if(fds==null)throw new IllegalStateException("/dev/fd unavailable");
            handles=fds.length;
        } else {
            try(var arena=Arena.ofConfined()){
                MemorySegment process=(MemorySegment)CURRENT.invokeExact();
                // PROCESS_MEMORY_COUNTERS_EX: two DWORDs followed by nine SIZE_Ts.
                MemorySegment counters=arena.allocate(80,8),handleCount=arena.allocate(4,4);
                counters.set(ValueLayout.JAVA_INT,0,80);
                if((int)MEMORY.invokeExact(process,counters,80)==0 || (int)HANDLES.invokeExact(process,handleCount)==0)
                    throw new IllegalStateException("Current-process metrics unavailable");
                privateBytes=counters.get(ValueLayout.JAVA_LONG,72);
                workingSet=counters.get(ValueLayout.JAVA_LONG,16);
                handles=Integer.toUnsignedLong(handleCount.get(ValueLayout.JAVA_INT,0));
            }
        }
        System.out.println(prefix+" cycle="+cycle+" pid="+ProcessHandle.current().pid()
            +" private_bytes="+privateBytes
            +" working_set="+workingSet
            +" handles="+handles
            +" elapsed_ms="+(System.nanoTime()-ORIGIN)/1_000_000
            +" java_threads="+java.lang.management.ManagementFactory.getThreadMXBean().getThreadCount());
        if("1".equals(System.getenv("GODOT_JFX_MEDIA_HANDLES")) && (cycle==1 || cycle%12==0 || prefix.equals("MEDIA_CHURN_IDLE")))
            CurrentProcessHandles.report(prefix,cycle);
    }
}
