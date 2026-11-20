# frame-benchmark — historical verification

## GPU timestamp capacity

The 2026-11-13 diagnostic table/transition rerun used a temporary project override
of 8192, then removed it; ordinary project settings were unchanged. All 68
transitions passed, with 1691 window samples averaging about 512 us. Offscreen
samples still remained zero on the direct path. Logs are
`vfx-table-scroll-mobile-safe.log` and `vfx-transition-mobile-safe.log`; the initial
capacity failure is preserved in `agentdir/artifacts/dead-code-audit/table-default-timestamp-limit.log`.
