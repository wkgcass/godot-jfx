// Local deterministic audio fixtures: MP3 through the Windows Media Foundation
// encoder, AIFF as a hand-written uncompressed PCM container. Both carry a
// 440 Hz tone so decoding exercises the real sample path instead of silence.
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cwchar>
#include <cstring>
#include <stdexcept>
#include <vector>

using Microsoft::WRL::ComPtr;
constexpr UINT32 rate = 44100, seconds = 2, channels = 1, bits = 16;
static void check(HRESULT hr, const char *operation) {
    if (FAILED(hr)) {
        std::fprintf(stderr, "%s HRESULT=0x%08lx\n", operation, static_cast<unsigned long>(hr));
        throw std::runtime_error(operation);
    }
}
static std::vector<short> tone() {
    std::vector<short> pcm(rate * seconds);
    for (UINT32 i = 0; i < pcm.size(); ++i)
        pcm[i] = static_cast<short>(12000.0 * std::sin(2.0 * 3.14159265358979 * 440.0 * i / rate));
    return pcm;
}

static void encode_mp3(const wchar_t *path) {
    ComPtr<IMFSinkWriter> writer;
    check(MFCreateSinkWriterFromURL(path, nullptr, nullptr, &writer), "create sink writer (MP3)");
    ComPtr<IMFMediaType> compressed;
    check(MFCreateMediaType(&compressed), "output media type");
    check(compressed->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio), "major type");
    check(compressed->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_MP3), "MP3 subtype");
    check(compressed->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels), "channels");
    check(compressed->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, rate), "sample rate");
    check(compressed->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 16000), "128 kbps");
    DWORD stream = 0;
    check(writer->AddStream(compressed.Get(), &stream), "add MP3 stream");
    ComPtr<IMFMediaType> input;
    check(MFCreateMediaType(&input), "input media type");
    check(input->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio), "input major");
    check(input->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM), "input PCM");
    check(input->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels), "input channels");
    check(input->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, rate), "input rate");
    check(input->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, bits), "input bits");
    check(input->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, channels * bits / 8), "input block");
    check(input->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, rate * channels * bits / 8), "input avg");
    check(writer->SetInputMediaType(stream, input.Get(), nullptr), "set input type");
    check(writer->BeginWriting(), "begin writing");
    const auto pcm = tone();
    for (UINT32 offset = 0; offset < pcm.size(); offset += rate / 10) {
        const DWORD count = (std::min)(rate / 10, static_cast<UINT32>(pcm.size()) - offset);
        ComPtr<IMFMediaBuffer> buffer;
        check(MFCreateMemoryBuffer(count * 2, &buffer), "buffer");
        BYTE *data = nullptr;
        check(buffer->Lock(&data, nullptr, nullptr), "lock");
        std::memcpy(data, pcm.data() + offset, count * 2);
        check(buffer->Unlock(), "unlock");
        check(buffer->SetCurrentLength(count * 2), "buffer length");
        ComPtr<IMFSample> sample;
        check(MFCreateSample(&sample), "sample");
        check(sample->AddBuffer(buffer.Get()), "sample buffer");
        check(sample->SetSampleTime(static_cast<LONGLONG>(offset) * 10000000 / rate), "sample time");
        check(sample->SetSampleDuration(static_cast<LONGLONG>(count) * 10000000 / rate), "sample duration");
        check(writer->WriteSample(stream, sample.Get()), "write sample");
    }
    check(writer->Finalize(), "finalize");
}

static void put_be32(std::vector<unsigned char> &out, UINT32 value) {
    out.push_back(static_cast<unsigned char>(value >> 24));
    out.push_back(static_cast<unsigned char>(value >> 16));
    out.push_back(static_cast<unsigned char>(value >> 8));
    out.push_back(static_cast<unsigned char>(value));
}
static void put_be16(std::vector<unsigned char> &out, UINT16 value) {
    out.push_back(static_cast<unsigned char>(value >> 8));
    out.push_back(static_cast<unsigned char>(value));
}
static void put_tag(std::vector<unsigned char> &out, const char tag[4]) {
    out.insert(out.end(), tag, tag + 4);
}
static void write_aiff(const wchar_t *path) {
    const auto pcm = tone();
    std::vector<unsigned char> aiff, comm, ssnd;
    put_tag(comm, "COMM");
    put_be32(comm, 18);
    put_be16(comm, channels);
    put_be32(comm, static_cast<UINT32>(pcm.size()));
    put_be16(comm, bits);
    // 44100 Hz as an 80-bit IEEE 754 extended float.
    const unsigned char extended[10] = { 0x40, 0x0E, 0xAC, 0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    comm.insert(comm.end(), extended, extended + 10);
    put_tag(ssnd, "SSND");
    put_be32(ssnd, 8 + static_cast<UINT32>(pcm.size()) * 2);
    put_be32(ssnd, 0); // offset
    put_be32(ssnd, 0); // block size
    for (short sample : pcm) put_be16(ssnd, static_cast<UINT16>(sample));
    put_tag(aiff, "FORM");
    put_be32(aiff, 4 + static_cast<UINT32>(comm.size() + ssnd.size()));
    put_tag(aiff, "AIFF");
    aiff.insert(aiff.end(), comm.begin(), comm.end());
    aiff.insert(aiff.end(), ssnd.begin(), ssnd.end());
    FILE *file = nullptr;
    if (_wfopen_s(&file, path, L"wb") != 0 || !file) throw std::runtime_error("open AIFF output");
    if (std::fwrite(aiff.data(), 1, aiff.size(), file) != aiff.size()) { std::fclose(file); throw std::runtime_error("write AIFF"); }
    if (std::fclose(file) != 0) throw std::runtime_error("close AIFF output");
}

int wmain(int argc, wchar_t **argv) {
    if (argc != 3 || (std::wcscmp(argv[1], L"mp3") != 0 && std::wcscmp(argv[1], L"aiff") != 0)) {
        std::fprintf(stderr, "usage: make_audio_fixture mp3|aiff <output path>\n");
        return 2;
    }
    bool started = false;
    try {
        check(MFStartup(MF_VERSION), "MFStartup");
        started = true;
        if (std::wcscmp(argv[1], L"mp3") == 0) encode_mp3(argv[2]);
        else write_aiff(argv[2]);
        const HRESULT shutdown = MFShutdown();
        started = false;
        check(shutdown, "MFShutdown");
    } catch (const std::exception &error) {
        std::fprintf(stderr, "make_audio_fixture failed: %s\n", error.what());
        if (started) MFShutdown();
        return 1;
    }
    std::printf("MAKE_AUDIO_FIXTURE_PASS codec=%ls rate=%u seconds=%u channels=%u bits=%u\n", argv[1], rate, seconds, channels, bits);
    return 0;
}
