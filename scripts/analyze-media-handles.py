"""Summarize optional self-process handle censuses without logging object names."""
import json
import re
import sys
from pathlib import Path

path=Path(sys.argv[1])
text=path.read_text(encoding="utf-8-sig").replace("\0", "")
samples=[]
for match in re.finditer(r"MEDIA_HANDLE_TYPES phase=(\w+) cycle=(\d+) counts=\{([^}]+)\}", text):
    counts={name.strip():int(value) for name,value in re.findall(r"([^,=]+)=(\d+)",match[3])}
    samples.append({"phase":match[1],"cycle_or_idle_seconds":int(match[2]),"counts":counts})
if not samples or "MEDIA_CHURN_PROBE_PASS" not in text:
    raise ValueError("Missing completed handle census run")
initial=samples[0]["counts"]
last=samples[-1]["counts"]
providers=[]
for match in re.finditer(r"MEDIA_ETW_PROVIDERS phase=(\w+) cycle=(\d+) total=(\d+) delta=\{([^}]*)\}",text):
    changes={key:int(value) for key,value in re.findall(r"([0-9a-f-]{36})=(-?\d+)",match[4])}
    providers.append({"phase":match[1],"cycle_or_idle_seconds":int(match[2]),"total":int(match[3]),"delta":changes})
aac_provider="51311de3-d55e-454a-9c58-43dc7b4c01d2"
aac=None
if providers:
    retained=0
    registrations=[]
    for sample in providers:
        retained+=sample["delta"].get(aac_provider,0)
        registrations.append(retained)
    if min(registrations)<0:
        raise ValueError("Inconsistent AAC provider deltas")
    aac={"provider":aac_provider,"registrations":registrations,
         "last_minus_first":registrations[-1]-registrations[0],
         "no_growth_after_first":max(registrations)==registrations[0]}
result={"source":str(path),"samples":samples,
        "provider_samples":providers,
        "aac_decoder_registration_check":aac,
        "last_minus_first":{key:last.get(key,0)-initial.get(key,0) for key in sorted(initial.keys()|last.keys())},
        "limitations":"Same-process PSS snapshot plus optional NtQueryObject type fallback; handles may change during a census. Type counts do not identify the allocating provider or prove the source of memory growth."}
output=path.with_suffix(".handles.json")
output.write_text(json.dumps(result,indent=2),encoding="utf-8")
print(json.dumps(result,indent=2))
if "--require-stable-aac" in sys.argv[2:]:
    if aac is None or not aac["no_growth_after_first"]:
        raise SystemExit("AAC decoder registration stability failed or was not sampled")
