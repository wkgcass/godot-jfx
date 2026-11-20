# bridge-protocol — historical verification

## Native window synchronization

Earlier test-native-window-bridge.ps1 runs passed GL and the retired Vulkan
separate-thread mode with
two native windows, Unicode titles, independent resize/visibility, 12 hide/show
cycles, invalid requests, owner-tree destruction and clean native-window counts.
Protocol tests cover rejection atomicity, FIFO draining and finish admission.
The pre-fix Vulkan swap-chain failure is preserved in
agentdir/artifacts/logs/native-window-bridge-before-window-sync.log. The existing encoded
host-stop regression passes. Secondary standard Stage creation/properties/snapshots
and GPU publication now use these APIs. Per-window input/focus/close use the input
queue described next; IME properties and window-addressed preedit are implemented,
while physical IME/DPI acceptance remains pending. Native GPU publication
uses opcode 26, described below.
