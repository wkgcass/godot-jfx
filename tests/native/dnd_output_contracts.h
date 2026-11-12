#pragma once
#include <stdexcept>
inline void check_dnd_output_contracts(IDataObject *object) {
    auto check=[](bool ok) { if (!ok) throw std::runtime_error("DnD output contract failed"); };
    DVTARGETDEVICE device{};
    FORMATETC input{CF_UNICODETEXT,&device,DVASPECT_CONTENT,-1,TYMED_HGLOBAL};
    FORMATETC out{};
    check(object->GetCanonicalFormatEtc(&input,&out) == DATA_S_SAMEFORMATETC);
    check(out.cfFormat == input.cfFormat && !out.ptd && out.dwAspect == input.dwAspect
            && out.lindex == input.lindex && out.tymed == input.tymed);
    check(input.ptd == &device);
    check(object->GetCanonicalFormatEtc(&input,nullptr) == E_POINTER);
    check(object->GetCanonicalFormatEtc(nullptr,&out) == E_POINTER && !out.ptd && !out.cfFormat);
    check(object->GetCanonicalFormatEtc(&input,&input) == DATA_S_SAMEFORMATETC && !input.ptd);
    DWORD connection=123;
    check(object->DAdvise(&input,0,nullptr,&connection) == OLE_E_ADVISENOTSUPPORTED && connection == 0);
    check(object->DAdvise(&input,0,nullptr,nullptr) == OLE_E_ADVISENOTSUPPORTED);
    auto *enumerator=reinterpret_cast<IEnumSTATDATA *>(1);
    check(object->EnumDAdvise(&enumerator) == OLE_E_ADVISENOTSUPPORTED && !enumerator);
    check(object->EnumDAdvise(nullptr) == E_POINTER);
}
