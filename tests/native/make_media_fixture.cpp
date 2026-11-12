// Local deterministic moving-pattern fixture, encoded by the installed Windows H.264 encoder.
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>
#include <cstdio>
#include <stdexcept>

using Microsoft::WRL::ComPtr;
constexpr UINT32 width=1920, height=1080, fps=60, frames=16*fps;
static void check(HRESULT hr, const char* operation) {
    if (FAILED(hr)) {
        std::fprintf(stderr,"%s HRESULT=0x%08lx\n",operation,static_cast<unsigned long>(hr));
        throw std::runtime_error(operation);
    }
}
static void dimensions(IMFMediaType* type) {
    check(type->SetGUID(MF_MT_MAJOR_TYPE,MFMediaType_Video),"major type");
    check(type->SetUINT32(MF_MT_INTERLACE_MODE,MFVideoInterlace_Progressive),"progressive");
    check(MFSetAttributeSize(type,MF_MT_FRAME_SIZE,width,height),"frame size");
    check(MFSetAttributeRatio(type,MF_MT_FRAME_RATE,fps,1),"frame rate");
    check(MFSetAttributeRatio(type,MF_MT_PIXEL_ASPECT_RATIO,1,1),"pixel aspect");
}
static void encode(const wchar_t* path) {
    ComPtr<IMFSinkWriter> writer;
    check(MFCreateSinkWriterFromURL(path,nullptr,nullptr,&writer),"create sink writer");
    ComPtr<IMFMediaType> compressed,input;
    check(MFCreateMediaType(&compressed),"output media type");
    dimensions(compressed.Get());
    check(compressed->SetGUID(MF_MT_SUBTYPE,MFVideoFormat_H264),"H.264 output");
    check(compressed->SetUINT32(MF_MT_AVG_BITRATE,8000000),"bit rate");
    check(compressed->SetUINT32(MF_MT_MPEG2_PROFILE,77),"Main profile");
    DWORD stream=0;
    check(writer->AddStream(compressed.Get(),&stream),"add video stream");
    check(MFCreateMediaType(&input),"input media type");
    dimensions(input.Get());
    check(input->SetGUID(MF_MT_SUBTYPE,MFVideoFormat_RGB32),"RGB32 input");
    check(writer->SetInputMediaType(stream,input.Get(),nullptr),"set input type");
    check(writer->BeginWriting(),"begin writing");
    for(UINT32 frame=0;frame<frames;frame++) {
        ComPtr<IMFMediaBuffer> buffer;
        constexpr DWORD bytes=width*height*4;
        check(MFCreateMemoryBuffer(bytes,&buffer),"frame buffer");
        BYTE* data=nullptr;
        check(buffer->Lock(&data,nullptr,nullptr),"lock buffer");
        auto pixels=reinterpret_cast<DWORD*>(data);
        // Color ramps plus a moving bright bar: every encoded frame differs.
        const UINT32 bar=(frame*13)%(width-96);
        for(UINT32 y=0;y<height;y++)for(UINT32 x=0;x<width;x++) {
            const DWORD red=x*255/(width-1), green=y*255/(height-1);
            pixels[y*width+x]=(x>=bar && x<bar+96) ? 0x00ffffff :
                (red<<16)|(green<<8)|((frame*3)&255);
        }
        check(buffer->Unlock(),"unlock buffer");
        check(buffer->SetCurrentLength(bytes),"buffer length");
        ComPtr<IMFSample> sample;
        check(MFCreateSample(&sample),"frame sample");
        check(sample->AddBuffer(buffer.Get()),"sample buffer");
        const LONGLONG start=static_cast<LONGLONG>(frame)*10000000/fps;
        const LONGLONG end=static_cast<LONGLONG>(frame+1)*10000000/fps;
        check(sample->SetSampleTime(start),"sample time");
        check(sample->SetSampleDuration(end-start),"sample duration");
        check(writer->WriteSample(stream,sample.Get()),"write video frame");
        if(frame%120==0)std::printf("ENCODE_PROGRESS frame=%u/%u\n",frame,frames);
    }
    check(writer->Finalize(),"finalize MP4");
}
static void verify(const wchar_t* path) {
    ComPtr<IMFSourceReader> reader;
    check(MFCreateSourceReaderFromURL(path,nullptr,&reader),"verify reader");
    ComPtr<IMFMediaType> type;
    check(reader->GetNativeMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM,0,&type),"native video type");
    UINT32 w=0,h=0,numerator=0,denominator=0;
    check(MFGetAttributeSize(type.Get(),MF_MT_FRAME_SIZE,&w,&h),"encoded size");
    check(MFGetAttributeRatio(type.Get(),MF_MT_FRAME_RATE,&numerator,&denominator),"encoded frame rate");
    GUID subtype={};check(type->GetGUID(MF_MT_SUBTYPE,&subtype),"encoded subtype");
    if(w!=width || h!=height || denominator==0 || numerator!=fps*denominator || subtype!=MFVideoFormat_H264)
        throw std::runtime_error("Encoded video format differs");
    UINT32 count=0;
    for(;;) {
        DWORD flags=0;LONGLONG timestamp=0;ComPtr<IMFSample> sample;
        check(reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM,0,nullptr,&flags,&timestamp,&sample),"verify sample");
        if(sample)count++;
        if(flags&MF_SOURCE_READERF_ENDOFSTREAM)break;
        if(count>frames)throw std::runtime_error("Too many encoded frames");
    }
    if(count!=frames)throw std::runtime_error("Encoded sample count differs");
    std::printf("MEDIA_FIXTURE_PASS width=%u height=%u fps=%u/%u frames=%u seconds=16 codec=H264\n",w,h,numerator,denominator,count);
}
int wmain(int argc,wchar_t** argv) {
    if(argc!=2)return 2;
    HRESULT initialized=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    if(FAILED(initialized))return 3;
    HRESULT started=MFStartup(MF_VERSION);
    int result=1;
    if(SUCCEEDED(started)) {
        try {encode(argv[1]);verify(argv[1]);result=0;}
        catch(const std::exception& error){std::fprintf(stderr,"MEDIA_FIXTURE_FAIL %s\n",error.what());}
        if(FAILED(MFShutdown()))result=1;
    }
    CoUninitialize();return result;
}
