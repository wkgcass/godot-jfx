# Linux x64 源码构建与 WSL2 运行

Linux x64 已在 `Ubuntu-WSL2` 的 Linux 文件系统中构建并验证。Linux 回归使用隔离 Weston 上的原生 Wayland 窗口。WSLg 在 Windows 桌面的显示和交互单独验证。Vulkan 对应 `mobile`，桌面 OpenGL 对应 `gl_compatibility`。可用下面的 PowerShell 命令进入已验证的工作目录。

```powershell
wsl.exe -d Ubuntu-WSL2 --cd /home/wkgcass/godot-jfx-wsl2
```

## 构建环境

以下包名适用于 Ubuntu 26.04 x64。在仓库根目录打开 Bash，先准备系统工具和 Godot、JavaFX 的原生构建依赖。

```bash
sudo apt update

# 构建工具、Godot Wayland 窗口和 GTK 3 对话框
sudo apt install git build-essential pkg-config python3-venv \
    libwayland-bin libwayland-dev libxkbcommon-dev libgtk-3-dev

# JavaFX SDK 的 GTK、字体和 Prism ES2
sudo apt install libglib2.0-dev libpango1.0-dev libfreetype-dev libfontconfig-dev \
    libgl-dev libegl-dev libgles-dev libx11-dev libxt-dev libxtst-dev libxxf86vm-dev

# JavaFX Media 的 ALSA 和 FFmpeg 开发库
sudo apt install libasound2-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
```

`libwayland-bin` 提供 `wayland-scanner`。X11 相关开发库用于构建上游 JavaFX 的 GTK 和 ES2 模块；项目的 Godot 宿主只编入 Wayland 窗口后端。

在同一台机器上运行 Demo 或图形测试时，还要准备所选后端的运行库。以下是 Ubuntu 26.04 上已验证的 WSLg 配置。

```bash
# Vulkan/mobile：Vulkan 加载器和 dzn 使用的显示信息库
sudo apt install libvulkan1 libdisplay-info3
# OpenGL/gl_compatibility：Mesa EGL 和 Gallium 驱动
sudo apt install libegl-mesa0 libgl1-mesa-dri
# WSLg 音频输出：PulseAudio 客户端和 ALSA 的 PulseAudio 插件
sudo apt install libpulse0 libasound2-plugins
```

上面的 FFmpeg 开发包会自动带入对应的运行库。只运行已打包 Media 应用的机器可直接安装运行库：

```bash
sudo apt install libavcodec62 libavformat62 libavutil60 libswscale9
```

WSLg 上，JavaFX Media 的 GStreamer 音频输出通过 ALSA 的 PulseAudio 插件连接到系统音频服务。本机用 Vulkan 和 OpenGL 运行时均连接到双声道 `RDPSink`。若使用私有运行库，`scripts/wsl-gpu.sh` 会将 `.tools/linux/pulse` 中的 PulseAudio 库和 `.tools/linux/ffmpeg-runtime` 中的 FFmpeg 8 库加入子进程的库搜索路径。私有 ALSA 配置和插件就绪时，脚本通过 `ALSA_CONFIG_PATH` 将默认 PCM 设备接入 WSLg。

构建和运行需要带桌面组件的完整 Linux x64 JDK 25。已有 JDK 时，将 `JAVA_HOME` 指向其目录即可。本机使用 `$HOME/graalvm-jdk-25.0.3+9.1`。使用 Ubuntu 提供的 JDK 时执行：

```bash
sudo apt install openjdk-25-jdk
export JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64
```

```bash
"$JAVA_HOME/bin/java" -version
python3 scripts/setup-env.py
```

初始化脚本准备源码子模块、Ant、Maven、Python 虚拟环境中的 SCons 和媒体样本。Ubuntu WSL2 上的 dzn 也由该脚本准备，见下文的 GPU 说明。

通过 apt 安装开发包后可直接构建。只有使用本机的私有开发包目录时，才需要设置以下搜索路径。

```bash
export PKG_CONFIG_SYSROOT_DIR="$PWD/.tools/apt/sysroot"
export PKG_CONFIG_PATH="$PKG_CONFIG_SYSROOT_DIR/usr/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_SYSROOT_DIR/usr/share/pkgconfig"
export CPATH="$PKG_CONFIG_SYSROOT_DIR/usr/include:$PKG_CONFIG_SYSROOT_DIR/usr/include/x86_64-linux-gnu"
export LIBRARY_PATH="$PKG_CONFIG_SYSROOT_DIR/usr/lib/x86_64-linux-gnu"
export PATH="$PWD/.tools/linux/wayland/usr/bin:$PATH"
```

`scripts/build-linux.sh` 在编译 Godot Editor 和共享库时仅编入 Wayland 窗口后端。脚本优先使用 `PATH` 中的 `wayland-scanner`，也能直接使用本副本的 `.tools/linux/wayland/usr/bin/wayland-scanner`。两处都缺少工具时，脚本会在调用 SCons 前报错。

## 编译和打包

依次编译 Editor、共享库与 SDK，再打包应用并发布到本地 Maven 仓库。

```bash
scripts/build-linux.sh --target godot-editor --jobs 2
scripts/build-linux.sh --target godot-library --jobs 2
scripts/build-linux.sh --target jfx --jobs 2
scripts/build-vfx.sh
python3 scripts/maven_local.py install --runtime artifacts/godot-library
```

Editor 导入和导出场景。JavaFX 宿主模块编入 Godot 共享库。JFX 构建启用 Media、关闭 WebKit。可调整 `--jobs`，或向单次构建传入 `--jdk DIRECTORY`。

| 产物 | 位置 |
| --- | --- |
| 源码 Editor | `godot/bin/godot.linuxbsd.editor.x86_64` |
| 源码引擎库 | `godot/bin/libgodot.linuxbsd.template_release.x86_64.library.so` |
| JavaFX SDK | `jfx/build/sdk/lib/` |
| 暂存模块和依赖清单 | `artifacts/godot-library/` |
| 完整 VFX 应用 | `artifacts/vfx/libs/vfx-demo.jar` |

graphics 和 media 的 Maven 平台分类名为 `linux`。graphics JAR 根目录的引擎名为 `libgodot.so`。两个独立 Demo 各自通过 Gradle 调用源码 Editor 导出场景。

```bash
./jfx/gradlew -g .gradle-cache -p demo/001-3d-in-javafx --no-daemon :shadowJar
./jfx/gradlew -g .gradle-cache -p demo/002-3d-contains-javafx --no-daemon :shadowJar
```

JAR 分别位于两个示例自己的 `build/libs/`。 随后要在隔离 Wayland 会话内使用同一个 Gradle 缓存时，`--no-daemon` 可让本次构建在结束后释放缓存锁。本机曾遇到外层空闲 Gradle 进程仍持有 `journal-1.lock`，隔离网络中的 Shadow 打包因等锁超时失败。

需要清理时，先用 `python3 scripts/clean.py --dry-run` 查看完整范围。单项预览可执行 `python3 scripts/clean.py --target godot-library --dry-run`。Linux 原生目标使用与构建相同的架构、驱动和模块选项，JFX 使用同一仓库的 Gradle `cleanAll`。全量清理会删除 `artifacts/reference/` 和 Godot 的 `bin/`，验收报告应事先归档。

## 在 WSLg 上选择 Intel GPU

此机通过 `/dev/dxg` 访问 Intel Arc B390。默认 Vulkan 加载器找到八份系统驱动清单，包括 `lvp_icd.json`，其中没有 dzn。同一个枚举程序在默认环境只返回 llvmpipe；经 `scripts/wsl-gpu.sh vulkan` 启动后返回 Intel Arc B390（厂商 ID `8086`、设备 ID `b080`）。此前在同一份发布库上直接启动 VFX，也复现了默认选用 llvmpipe、显式选择 dzn 后使用 B390 的差异。应用对照记录在 `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/vulkan-selection.json`。

Ubuntu x64 的 WSL2 有 `/dev/dxg` 时，运行 `python3 scripts/setup-env.py` 即可准备 dzn。首次运行用临时 APT 配置从 Kisak Mesa PPA 获取当前 Ubuntu 代号对应的 `mesa-vulkan-drivers`，校验仓库签名与软件包摘要，然后只将 dzn 清单、共享库和版权文件放入项目目录。此步骤以普通用户运行，已有驱动直接复用。其他 WSL 发行版可通过 `WSL_DZN_ROOT` 提供兼容驱动。

包装脚本为 Vulkan 子进程指定私有 dzn 清单和库目录。默认目录为 `.tools/linux/dzn/mesa`，可用 `WSL_DZN_ROOT` 指向同样保留 `usr/share`、`usr/lib` 布局的目录。OpenGL 子进程通过 `GALLIUM_DRIVER=d3d12` 和 `MESA_D3D12_DEFAULT_ADAPTER_NAME` 选择适配器，缺省匹配 Intel。本次 Wayland 回归从运行中的 JVM 核实：Vulkan 的缩放测试加载了 `libvulkan_dzn.so`，OpenGL 的像素读回测试加载了 Mesa EGL 和 Gallium。两者均加载 WSL 的 D3D12 运行库和 Intel 驱动。进程映射、同 PID 的 Godot 日志和枚举结果在 LCD 发布归档的 `wayland-toolkit-publication-QI3DyI7e/gpu-route/`。

在 Linux 上检测到 `/dev/dxg` 时，Demo 启动脚本会按所选驱动自动调用 `wsl-gpu.sh`。默认使用 Vulkan。直接连接 WSLg 的 Wayland 套接字时，Vulkan 启动器默认设置 `GODOT_JFX_VSYNC_FALLBACK=0`，保留初始垂直同步。要在同一窗口环境中试用自动帧率策略，可运行 `GODOT_JFX_VSYNC_FALLBACK=1 scripts/run-vfx-demo.sh`。私有 Wayland 和 OpenGL 沿用各自的启动设置。

```bash
scripts/run-vfx-demo.sh --smoke
scripts/run-vfx-demo.sh --driver opengl --disable-vsync --max-fps 60 --smoke
```

在隔离会话外也可以核对 VFX 实际加载的驱动文件。将 `vfx_pid` 设为 WSL 发行版中运行 VFX 的 Java 进程号。

```bash
rg 'libvulkan_dzn|libd3d12core|libigd12um|libgodot\.so' "/proc/$vfx_pid/maps"
```

本机 12 轮验证期间，Vulkan 进程同时加载了私有 Mesa 的 `libvulkan_dzn.so`、WSL 的 `libd3d12core.so` 及 Intel 用户态驱动 `libigd12um64xe3.so`，并持有打开的 `/dev/dxg`。同一进程的 Godot 日志报告 `Wayland`、`Forward Mobile` 和 B390。文件映射、设备描述符及核验过的发布库摘要记录在 `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/extended/vulkan-runtime-stack.json`。

去掉 `--smoke` 可持续运行 Demo。OpenGL 命令采用本机验过的 60 FPS CPU 限帧。GPU 类型可从运行日志核对。Vulkan 行应包含 `Forward Mobile` 和 B390，OpenGL 行应包含 `Compatibility` 和 B390。使用普通 Java 应用 JAR 时，JVM 属性位于 `-jar` 前，例如 `scripts/wsl-gpu.sh opengl "$JAVA_HOME/bin/java" -Djavafx.godot.driver=opengl -jar app.jar`。

Wayland 版共享库的 Robot 后端需要 `wayland-scanner`、`wayland-client` 和 `xkbcommon` 开发文件。SCons 从模块中的 XML 生成 C 接口。输出布局和图像复制协议来自 wayland-protocols，虚拟指针来自 wlr-protocols，虚拟键盘使用 wlroots 采用的 virtual-keyboard-unstable-v1。各 XML 保留上游许可。运行时需要合成器公布相应协议，虚拟键盘还需要 XKB 的 evdev/pc105/us 键盘数据。

## Wayland 原生窗口验证

从副本的源码 Editor 运行以下两条命令。脚本移除 `DISPLAY`、显式选择 Wayland，分别检查 Vulkan/mobile、OpenGL/gl_compatibility。探针检查四个不同的原生窗口表面，并读回父窗口、所属子窗口和无关窗口的不同颜色。隐藏并重新显示子窗口、销毁父子窗口后，无关窗口继续绘制。在本机的协议日志中可见子窗口通过 `xdg_toplevel.set_parent` 绑定到父窗口。

```bash
WAYLAND_DEBUG=client scripts/wsl-gpu.sh vulkan scripts/test-wayland-windows.sh vulkan
WAYLAND_DEBUG=client scripts/wsl-gpu.sh opengl scripts/test-wayland-windows.sh opengl
```

B390 上两种驱动各连续三轮通过窗口断言、协议检查和正常退出。跟踪记录显示父窗口发出 `xdg_toplevel.set_minimized`；xdg-shell 不提供查询实际最小化状态或主动取消最小化的接口。修复前，退出线程可能在显示连接上无限等待。修复后用独立管道唤醒该线程。使用项目 graphics JAR 的 JVM 也在两个后端获得 Wayland 表面并读回绿色像素。两个独立 Demo 和 VFX JAR 均从这份共享库重新打包并核对了库的 SHA-256。Wayland 拖放目标使用 wl_data_device 和 wl_data_offer。独立 Weston 上的跨进程外拖、回到本应用后放下，以及接收端拒绝都已通过两个后端。详细范围见 [Wayland 拖放记录](glass-godot.md#drag-and-drop-on-linux-wayland)。VFX 完整 JAR 在取消 DISPLAY 的会话中已分别通过两种驱动的启动和关闭检查。启动专项通过两种驱动的 logo、hidden 和对应取消模式。

私有 Weston 的 `--no-input` 参数创建无原生输入设备的测试桌面，用于完全由 Godot 合成输入的拖动、调整大小和悬停用例。NonRobot 分组在私有 Weston 上自动为这些用例选择这个设置。[拖动测试命令](../TESTS.md#快速拖出窗口测试的当前验证)

父子 Stage 在同一轮 JavaFX 事件中显示时，宿主会等父窗口首次映射，再发送所属关系并让子窗口提交首帧。在隔离 labwc 上，Vulkan 和 OpenGL 均通过了重叠像素和实际点击检查。点击父窗口露出的部分后，重叠区域仍由子窗口接收点击。运行方法见 [WaylandOwnedStack 用例](../TESTS.md)。

### Wayland 窗口管理限制

隔离 Weston 的 VFX 窗口控件在还原最大化子窗口时停在第 2 步：窗口已回到普通模式，但仍占用 3120×2080 像素，原始尺寸是 800×600。xdg-shell 的 configure 每个尺寸分量都允许为零，表示由客户端决定。副本的 Wayland 后端现在保存普通窗口的逻辑尺寸，在收到零分量时用于还原，并优先采用合成器明确给出的尺寸。源码 Editor 的子窗口探针新增了最大化、还原尺寸及还原后像素检查。重建后的源码 Editor 在两个驱动上都将子窗口恢复到测试前的 320×200 物理像素，绿色内容读回通过。VFX 控件随后在隔离 Weston 的 Vulkan 和 OpenGL 用例中恢复到原始的 800×600 物理像素，通过最大化和还原检查。后续最小化请求已发出，应用请求还原时仍停在第 4 步。详见 `wayland-egl-check-ed9P5d30/extra/011-test-vfx-window-controls/`。

2026 年 11 月 23 日，第一轮隔离回归在第 266 项被 Windows 窗口监控中止，前 265 项有 230 项通过、35 项失败。Windows 系统日志显示 19:10:22 进入新型待机，19:52:37 退出，19:53:00 监控检测到两扇窗口短时间内最小化。监控没有记录动作发起者。这些时间戳对应本次停测，无法据此认定此前所有窗口最小化的原因。接续回归使用下文的 `--isolate-wslg` 命名空间隔离方式。

| 能力 | 协议与本机实测 |
| --- | --- |
| 顶层窗口图标 | 本机 WSLg 和隔离 Weston 14 均未公布可选的 `xdg_toplevel_icon_manager_v1`。支持该接口的合成器可接收方形共享内存图像。两种本机会话都无法用该协议设置任务栏图标。 在独立的 labwc 0.9.3 中，两种驱动的默认和 runtime 图标用例共 4 项通过，记录了逐窗口设置、更新和清除图标的原生请求。 |
| 跨 Wayland 连接的文件选择器所属关系 | 本机两种会话均未公布 xdg-foreign v1/v2 的 exporter、importer。无所属窗口的 GTK 选择器已在隔离 Weston 显示并取消。有所属窗口的 GTK 选择器依赖合成器支持导出和导入父窗口句柄。 labwc 0.9.3 上，Vulkan 与 OpenGL 均通过主 Stage 和次级 Stage 的真实 GTK 面板验证，独立桌面观察器确认面板的父窗口，Alt+F4 关闭后 Java 收到取消结果。 |
| 顶层窗口的全局位置、排序、强制置底 | 标准 xdg-shell 由合成器放置顶层窗口，提供 `set_parent` 表达所属关系。它没有读取全局层级或强制置底的客户端接口。私有 Weston 14 的 `test-native-order` 在两种驱动的默认和 runtime 档均在查询原生层级时失败。所属关系另有协议跟踪和像素验收。 三层非模态窗口在 labwc 0.9.3 上还有一处差异：点击中间层会把它提升到最内层之上。相同布局的原生 GTK 3 Wayland 对照复现了这个行为。[labwc 的窗口提升实现](https://github.com/labwc/labwc/blob/0.9.3/src/view.c#L2103-L2115) |
| 最小化与恢复 | `xdg_toplevel.set_minimized` 只发送请求，协议没有状态查询或取消最小化的请求。原生窗口桥接用例在 Weston 14 上请求恢复时超时，在 labwc 0.9.3 上通过了两个驱动的验证。快速最小化后立即恢复的原生 Stage 用例在两种合成器上都停在第 12 步。在 labwc 上，桌面窗口列表显示所属父窗与子窗都已最小化。应用向子窗发出激活请求后，两窗仍处于最小化状态。模拟任务栏选择该子窗后，两窗恢复，Vulkan 和 OpenGL 都通过了后续的窗口尺寸、内容和关闭断言。该桌面操作单独记录，原用例保留失败。 |
| 主动请求键盘焦点 | 可选的 `xdg_activation_v1` 支持发起请求，合成器决定是否授予焦点。本机 WSLg 1.0.73 与隔离 Weston 14 都没有公布这个接口。隔离用例在子窗口请求将焦点切回主窗口时停在第 1 步。 |

以上失败保留在 `agentdir/artifacts/wayland-full-GRn6iHqe/tests/results.csv`。协议依据见仓库内的 [xdg-shell](../godot/thirdparty/wayland-protocols/stable/xdg-shell/xdg-shell.xml) 和 [xdg-activation](../godot/thirdparty/wayland-protocols/staging/xdg-activation/xdg-activation-v1.xml)。

## 回归与已知限制

隔离的 labwc 0.9.3 公开了 `xdg_activation_v1`。请求恢复最小化窗口时，Godot 使用同一座席事件的序号和来源表面申请激活，并等待目标表面实际取得焦点或收到激活通知。Vulkan、OpenGL 的 VFX 窗口控件及各自的 runtime 变体共 4 项通过；跟踪均收到目标表面的键盘焦点事件。原生 Stage 输入的两个用例也通过。Weston 14 的四项任务切换器恢复仍通过。合成器能按自己的策略拒绝激活。原生跟踪、截图和两份额外 Demo 的构建记录位于 `agentdir/artifacts/wayland-activation-aPQfvnC7/`。运行入口见 [Wayland 测试说明](../TESTS.md#linux-原生-wayland-窗口)。

WSLg 的全局接口来自只读注册表探针 `agentdir/artifacts/wayland-egl-check-ed9P5d30/wslg-registry.log`。隔离 Weston 的对应记录在 `agentdir/artifacts/wayland-rebuild-UCYJ3nrm/nonrobot-tail/033-test-wayland-windows/wayland-windows-vulkan.log`。两者分别公布 xdg-shell v1 和 v5，均公布 wl_data_device_manager v3 和 text-input v1。

```bash
python3 scripts/run-linux-tests.py --group NonRobot --driver all --list
scripts/wsl-wayland-session.sh --isolate-wslg scripts/run-linux-tests.py --group NonRobot --driver all
```

WSLg 上直接启动 Demo 使用已有的桌面。要运行独立 Wayland 测试桌面，Ubuntu 26.04 需先安装系统 Weston 14 和相关工具：`sudo apt install weston libweston-14-dev libwayland-dev libpixman-1-dev libxkbcommon-dev dbus-daemon bubblewrap`。默认使用 `/usr/bin/weston`。在 Weston 中运行基本 Robot 用例还需执行 `sudo apt install labwc wlr-randr`，并保持 `GODOT_JFX_LABWC_ROOT` 未设置，以使用系统 labwc。外部拖放注入用例还需要 Weston 14 开发头。环境变量和测试模块的用途见 [Wayland 测试说明](../TESTS.md#linux-原生-wayland-窗口)。

分组入口在 WSL2 自动为带 `--driver` 的用例选择对应的 GPU 环境，并写入 `agentdir/logs/`。窗口激活、焦点恢复和最小化取决于 Wayland 合成器。用私有 Weston 运行全组，再用 labwc 对照窗口行为。已获授权的 Robot 用例在隔离的 labwc 和 niri 会话中串行运行。[原生 Wayland 测试命令](../TESTS.md#linux-原生-wayland-窗口)

两个额外 Demo 的 Linux JAR 均已在独立 Wayland 桌面、B390 上通过 Vulkan/mobile 和 OpenGL/gl_compatibility 验证。三棱锥暂停时模型区域连续两帧完全一致，拖动后两种驱动分别有 22,264 和 23,030 个模型像素变化。恢复旋转后坐标轴保持静止，关闭窗口后进程正常退出。房间 Demo 在两种驱动上均完成墙面设备交互、鼠标捕获和释放，输出 `ROOM_SMOKE_PASS`。本次发行包的两份场景 PCK 与构建输出逐字节一致。记录位于 `agentdir/artifacts/wayland-interaction-hQ6x4vwN/verified-release-lZUp7QMq/` 下的 `demos/`、`restart-suite-n8jhXQQK/geometry/` 和 `restart-suite-n8jhXQQK/package-content.json`。

B390 的 dzn 驱动为彩色和深度帧缓冲公布的采样次数均为 1 和 4。房间请求 2× 多重采样抗锯齿时，Godot 在创建视口渲染缓冲前选用 4× 并输出提示。旧版将 Vulkan 附件降到单采样，却继续生成多采样解析操作，引发设备移除。独立立方体场景的 Vulkan 校验层记录了 `VUID-VkSubpassDescription2-externalFormatResolve-09338`。修复后的同一场景正确读回红色像素，这条错误已消失。日志另有图像上传粒度和交换链色彩空间扩展的校验消息，详见 `agentdir/artifacts/wayland-material-comparison-8Qv64YvC/msaa/`。

完整验收状态分别记录在 [VFX 验收](vfx-demo.md)、[窗口状态](glass-godot.md#window-stacking-and-focus-on-wsl2) 和[帧率测试](frame-benchmark.md)。

`--isolate-wslg` 使用 bubblewrap 创建私有进程、网络和 IPC 命名空间，隔离宿主显示、WSL 互操作套接字和输入设备。进程保留 `/dev/dxg`、可用的 DRM 设备及用于 Media 的音频套接字。Godot 在 Weston 创建 Wayland 表面。测试使用 Weston 的 headless 输出，普通座席通过测试模块提供键盘和指针。

### WSLg 显示缩放与 COPY MODE

VFX Intro 的 Stage 请求 1280×800 逻辑像素。本机 Windows 桌面为 3120×2080、192 DPI（200%）。修复后，Wayland 的 `set_window_geometry` 为 1280×800，Windows 客户区为 2560×1600 物理像素。Vulkan/mobile 和 OpenGL/gl_compatibility 均以真实 Demo JAR 复测。Glass 提供物理像素尺寸，Wayland 宿主在首个表面进入屏幕前就要按已公布的输出比例换算。启动测试在主窗口首次显示、重新显示和次级窗口显示时检查逻辑尺寸。

在已有 Godot 场景中添加 JavaFXHost 时，次级 Stage 也会提交物理像素尺寸，且夹具默认没有 `--javafx-startup` 参数。Wayland 创建窗口时通过关联的 JavaFXNativeWindow 识别这一情况。对话框用例检查 VDialog 的逻辑宽度 900 和 SimpleAlert 的逻辑宽度 720，并在点击前核对目标是否在布局期间发生变化。隔离 Weston 的 Vulkan 复测中，两种窗口的截图宽度分别为 1800 和 1440 物理像素，五步点击均完成。该次进程在清理未使用的全局输入钩子时以 1 退出。修复钩子清理后，常规用例在两种驱动上都完成五步点击并正常退出。故障注入变体通过 Vulkan。OpenGL 首轮在清理时发生 SIGSEGV，修复 EGL 表面销毁时的当前上下文后，常规和注入变体连续三轮正常退出。见 `wayland-egl-check-ed9P5d30/{dialog,opengl-2,opengl-3}/`。

若 Windows 窗口标题出现 `[WARN:COPY MODE]`，可查 `/mnt/wslg/weston.log`。本机发生时，Weston 打开 `/mnt/shared_memory` 下共享文件返回 I/O 错误，随后记录 `use_gfxredir = 0`。重启整个 WSL 后可见 `use_gfxredir = 1` 及客户端协商记录。一次后续会话再次出现同一错误，重启属于临时恢复。整机 WSL 重启会结束所有运行中的发行版。
