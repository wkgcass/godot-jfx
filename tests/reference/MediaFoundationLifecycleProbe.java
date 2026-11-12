import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;

/** Isolates balanced MF lifetime, optionally including a source reader, from JavaFX. */
public final class MediaFoundationLifecycleProbe {
    private static MethodHandle bind(SymbolLookup library,String name,FunctionDescriptor descriptor){
        return Linker.nativeLinker().downcallHandle(library.find(name).orElseThrow(),descriptor);
    }
    private static void check(int hr,String operation){
        if(hr<0)throw new IllegalStateException(operation+" HRESULT=0x"+Integer.toHexString(hr));
    }
    public static void main(String[] args) throws Throwable {
        try(var arena=Arena.ofConfined()){
            var mf=SymbolLookup.libraryLookup("mfplat.dll",arena);
            var ole=SymbolLookup.libraryLookup("ole32.dll",arena);
            var init=bind(ole,"CoInitializeEx",FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.JAVA_INT));
            var uninit=bind(ole,"CoUninitialize",FunctionDescriptor.ofVoid());
            var start=bind(mf,"MFStartup",FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.JAVA_INT,ValueLayout.JAVA_INT));
            var stop=bind(mf,"MFShutdown",FunctionDescriptor.of(ValueLayout.JAVA_INT));
            MethodHandle createReader=null;
            MemorySegment url=MemorySegment.NULL;
            if(args.length>0){
                createReader=bind(SymbolLookup.libraryLookup("mfreadwrite.dll",arena),"MFCreateSourceReaderFromURL",
                        FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS,ValueLayout.ADDRESS,ValueLayout.ADDRESS));
                byte[] text=(Path.of(args[0]).toAbsolutePath().toString()+"\0").getBytes(StandardCharsets.UTF_16LE);
                url=arena.allocate(text.length,2);url.copyFrom(MemorySegment.ofArray(text));
            }
            check((int)init.invokeExact(MemorySegment.NULL,0),"CoInitializeEx");
            try{
                CurrentProcessHandles.report("MF_BASELINE",0);
                for(int cycle=1;cycle<=24;cycle++){
                    // MF_VERSION and MFSTARTUP_LITE from the installed Windows SDK.
                    check((int)start.invokeExact(0x20070,1),"MFStartup");
                    try{
                        if(createReader!=null){
                            try(var scope=Arena.ofConfined()){
                                var out=scope.allocate(ValueLayout.ADDRESS);
                                check((int)createReader.invokeExact(url,MemorySegment.NULL,out),"MFCreateSourceReaderFromURL");
                                var reader=out.get(ValueLayout.ADDRESS,0);
                                if(reader.equals(MemorySegment.NULL))throw new AssertionError("Null source reader");
                                // IUnknown::Release is vtable slot 2 (Windows x64).
                                var table=reader.reinterpret(8).get(ValueLayout.ADDRESS,0).reinterpret(24);
                                var release=Linker.nativeLinker().downcallHandle(table.get(ValueLayout.ADDRESS,16),
                                        FunctionDescriptor.of(ValueLayout.JAVA_INT,ValueLayout.ADDRESS));
                                int refs=(int)release.invokeExact(reader);
                                System.out.println("MF_READER_RELEASE cycle="+cycle+" refs="+Integer.toUnsignedString(refs));
                            }
                        }
                    }finally{check((int)stop.invokeExact(),"MFShutdown");}
                    if(cycle==1 || cycle%12==0)CurrentProcessHandles.report("MF_DISPOSED",cycle);
                }
                System.out.println("MF_LIFECYCLE_PROBE_PASS");
            }finally{uninit.invokeExact();}
        }
    }
}
