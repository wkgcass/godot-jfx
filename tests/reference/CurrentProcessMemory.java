import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;
import java.lang.management.ManagementFactory;
import java.nio.file.Files;
import java.nio.file.Path;

/** Read-only per-OS metrics for the JVM hosting the media pipeline. */
final class CurrentProcessMemory {
    private static final long ORIGIN=System.nanoTime();
    private static final String OS=System.getProperty("os.name","");
    private static final boolean MAC=OS.startsWith("Mac");
    private static final boolean LINUX=OS.equals("Linux");
    private static final MethodHandle CURRENT, MEMORY, HANDLES;
    static {
        if(MAC || LINUX) {
            CURRENT=null;MEMORY=null;HANDLES=null;
        } else {
            if(!OS.startsWith("Windows") || ValueLayout.ADDRESS.byteSize()!=8)
                throw new UnsupportedOperationException("Unsupported process metrics platform: " + OS);
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
        if (LINUX) {
            long rss = -1, clean = -1, dirty = -1, huge = 0;
            for (String line : Files.readAllLines(Path.of("/proc/self/smaps_rollup"))) {
                String[] fields = line.trim().split("\\s+");
                switch (fields[0]) {
                    case "Rss:" -> rss = Long.parseLong(fields[1]);
                    case "Private_Clean:" -> clean = Long.parseLong(fields[1]);
                    case "Private_Dirty:" -> dirty = Long.parseLong(fields[1]);
                    case "Private_Hugetlb:" -> huge = Long.parseLong(fields[1]);
                }
            }
            if (rss <= 0 || clean < 0 || dirty < 0) throw new IllegalStateException("Incomplete smaps_rollup");
            workingSet = Math.multiplyExact(rss, 1024L);
            privateBytes = Math.multiplyExact(clean + dirty + huge, 1024L);
            handles = ManagementFactory.getPlatformMXBean(com.sun.management.UnixOperatingSystemMXBean.class)
                    .getOpenFileDescriptorCount();
        } else if(MAC) {
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
