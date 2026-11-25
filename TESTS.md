# 测试指南

## 跨平台待验证项的维护规则

Linux x64 用 `python3 scripts/run-linux-tests.py --group NonRobot --driver all --list`
列出 Vulkan/OpenGL 矩阵；去掉 `--list` 后按顺序执行，可用 `--test NAME`
只运行指定脚本。Robot 组同样支持列出用例，但实际操作桌面前仍需授权。
列出不代表通过；部分外部桌面互操作探针还需要 Linux 对端。

VFX 源码构建后，可以在独立 Wayland 会话验证动画的首帧、跨段计时和反向播放。用例在 JavaFX 应用线程上传入固定的纳秒时间戳，失败会抛出断言并以非零状态退出。

```sh
driver=vulkan  # 或 opengl
scripts/wsl-wayland-session.sh --isolate-wslg scripts/wsl-gpu.sh "$driver" \
    "$JAVA_HOME/bin/java" --enable-native-access=ALL-UNNAMED "-Djavafx.godot.driver=$driver" \
    -cp artifacts/vfx/classes/java/test:artifacts/vfx/libs/vfx-demo.jar \
    io.vproxy.vfx.test.TestMain io.vproxy.vfx.test.AnimationTimingTest
```

Linux 的独立 Robot 用例 `WaylandVStageGeometry` 启动 VFX Intro，通过标题栏移动窗口，再向外和向内拖右下角。每一步都从合成器的输出图像测量四条窗口边界。它需要已构建的 VFX JAR 和提供虚拟指针与输出捕获协议的隔离 labwc。两种驱动串行执行。

```sh
mkdir -p artifacts/reference/vstage-geometry
jar=artifacts/vfx/libs/vfx-demo.jar
"$JAVA_HOME/bin/javac" -cp "$jar" -d artifacts/reference/vstage-geometry tests/reference/WaylandVStageGeometry.java
for driver in vulkan opengl; do
    scripts/wsl-wayland-session.sh --isolate-wslg --compositor labwc --test-layout 1920x1200+60+80 \
        scripts/wsl-gpu.sh "$driver" "$JAVA_HOME/bin/java" --enable-native-access=ALL-UNNAMED \
        "-Djavafx.godot.driver=$driver" -cp "artifacts/reference/vstage-geometry:$jar" WaylandVStageGeometry || exit 1
done
```

`WaylandOwnedStack` 在同一轮 JavaFX 事件处理中依次显示父窗口和所属子窗口。从隔离桌面取样父窗口独有、交叠、子窗口独有的三个区域，再点击交叠处检查哪个窗口收到了事件。用例还覆盖点击父窗口，以及隐藏和重新显示子窗口。

```sh
jar=artifacts/vfx/libs/vfx-demo.jar
mkdir -p artifacts/reference/owned-stack
"$JAVA_HOME/bin/javac" -cp "$jar" -d artifacts/reference/owned-stack tests/reference/WaylandOwnedStack.java
for driver in vulkan opengl; do
    scripts/wsl-wayland-session.sh --isolate-wslg --compositor labwc --test-layout 1920x1200+490+230 \
        scripts/wsl-gpu.sh "$driver" "$JAVA_HOME/bin/java" --enable-native-access=ALL-UNNAMED \
        "-Djavafx.godot.driver=$driver" -cp "artifacts/reference/owned-stack:$jar" WaylandOwnedStack || exit 1
done
```

Linux 的 `test-clipboard-encoding.sh` 还会在内存中往返 Wayland MIME 数据，检查混合 URI 列表、无效路径、仅 URL 的格式枚举和半透明 PNG。该用例清除显示地址，验证格式转换可独立于图形环境运行。

Linux 的 `test-clipboard.sh` 使用独立的 GTK 3 对端。它读取 JavaFX 发布的中文、HTML、RTF、URL、文件、PNG 和自定义 MIME，再发布两组数据供 JavaFX 读取。Wayland 模式需要两个客户端在同一个 seat 上依次获得键盘焦点。直接在 WSLg 上执行时，这些测试窗口会出现在 Windows 桌面上。

`scripts/linux-clipboard-interop.sh` 另用两个 JVM 验证所有权转移和非法写入。两个进程各自通过发行库创建 Wayland 窗口。可用 `--jdk DIRECTORY` 指定 JDK 25。

本节规则长期保留。开发或修复涉及其他平台、且当前环境无法完成验证时，执行工作的开发者或代理必须在本文件的“跨平台待验证清单”中记录目标平台、受影响行为、验证入口与参数、通过条件和已知限制。

在目标平台用包含对应改动的源码产物完成验证后，执行验证的开发者或代理应在同一次工作中自动删除已满足全部通过条件的待办条目，无需另行请求确认；同时同步其他文档和脚本注释中对应的待验证状态。部分通过时仅删除已验证的范围，保留剩余平台、后端或场景。验证证据记录到对应验收文档，包含源码版本及本地差异、平台、后端、命令、日志和必要的图像。上游旧版本的通过记录、其他平台通过、跳过或仅编译成功均不足以删除条目。清单清空时保留本规则和清单标题，注明当前无待验证项。

## 跨平台待验证清单

macOS 验证前按 `docs/build-macos.md` 从源码重建对应产物。日常只运行本次改动相关的 Metal 用例；清单中明确要求 OpenGL 或双后端的条目按所列参数验证。GUI 测试使用 safe 模式并串行执行。正向用例须正常退出、退出码为 0，并满足脚本原有 PASS 与错误检查。

| 目标平台与待验证内容 | 验证入口与参数 | 通过条件及已知限制 |
| --- | --- | --- |
| macOS arm64，Retina 与混合缩放多屏下的共享窗口夹具 | 在 Retina 单屏和不同缩放双屏环境运行 `test-logical-windows.sh`、`test-window-order.sh`、`test-window-composition.sh`，将主窗口置于屏幕交界附近，覆盖子窗口落在另一屏的情况；记录各窗口所在屏幕、缩放和位置 | 核对窗口尺寸、相对位置、输入坐标与 GPU 像素。当前部分断言用主窗口屏幕缩放计算子窗口采样点，可能误判；如需修正，应依据各窗口实际坐标与渲染尺寸。缺少对应显示器环境时保留该范围的待办。 |
| macOS arm64，独立 IME 窗口的点击坐标 | 获得 Robot 授权后，在 Retina 屏运行 `./scripts/test-native-ime.sh --driver metal` 和 `--driver opengl` | 从已显示的子窗口尺寸换算点击位置，焦点离开输入框后取消预编辑，按钮动作完成，根文本与资源清理断言通过，并恢复光标。 |

## Viewport＋safe 支持边界

### Linux 原生 Wayland 窗口

在独立桌面运行 `scripts/wsl-wayland-session.sh --isolate-wslg scripts/run-linux-tests.py --group NonRobot --driver all --test test-wayland-msaa` 可验证视口的多重采样抗锯齿。源码 Editor 切换单采样、请求 2×、再恢复单采样，检查中心颜色、边缘像素变化以及恢复后逐字节一致的画面。两种后端均检查 3D 边缘。Vulkan 还检查 2D 三角形的边缘。OpenGL 的 2D 多重采样在 Godot GLES3 中尚未实现，单独验证明确警告及逐字节保持单采样的图像。设备、驱动、渲染方法和像素计数写入 `agentdir/logs/wayland-msaa-{vulkan,opengl}.log`。

在 WSLg 中依次运行 `scripts/wsl-gpu.sh vulkan scripts/test-wayland-windows.sh vulkan` 和 `scripts/wsl-gpu.sh opengl scripts/test-wayland-windows.sh opengl`。测试使用源码 Editor 和 Wayland，核对独立窗口的表面、像素、子窗口隐藏重显、所属关系、最小化请求的目标及进程正常退出。脚本把完整协议跟踪写到 `agentdir/logs/wayland-windows-{vulkan,opengl}.log`。设置 `WAYLAND_DEBUG=client` 也会在标准输出打印跟踪。在 Wayland 会话中用 `scripts/run-linux-tests.py --group NonRobot --driver all --test test-wayland-windows` 可以串行运行这两项。xdg-shell 允许客户端请求最小化；合成器不向应用报告实际最小化状态，也没有由客户端取消最小化的请求。JavaFX 宿主测试另外检查发行库的 `GODOT_LIBRARY_DISPLAY_DRIVER Wayland` 日志。

发行包测试还用上游 JavaFX GTK/Prism ES2 生成独立的像素对照。对照进程需要自己的图形环境，并采用 Wayland 输出的缩放比例。

在 Ubuntu 26.04 的独立桌面运行测试前，先安装 Weston 14 和隔离会话依赖：

```bash
sudo apt install weston libweston-14-dev libwayland-dev libpixman-1-dev libxkbcommon-dev dbus-daemon bubblewrap
```

保持 `GODOT_JFX_WESTON_ROOT` 未设置，脚本就会从 `PATH` 启动系统 Weston。若仍导出了旧临时目录，先运行 `unset GODOT_JFX_WESTON_ROOT`。普通用例可直接连接 Weston。下方基本 Robot 用例在 Weston 内启动 labwc，由 labwc 提供虚拟输入，`wlr-randr` 设置测试用的屏幕尺寸。Ubuntu 26.04 安装这两个工具的命令如下。

```bash
sudo apt install labwc wlr-randr
```

使用系统安装版时，保持 `GODOT_JFX_LABWC_ROOT` 未设置。系统 Weston 14.0.2 和 labwc 0.9.3 下的基本 `test-robot` 已在 Vulkan、OpenGL 上分别通过。

```sh
scripts/wsl-wayland-session.sh scripts/run-linux-tests.py --group NonRobot --driver all --test test-vfx-animation
```

大表格拖动可以和 VFX 菜单中的黑洞透镜一起测量。默认的 96 次应用内拖动同时更新表格位置和透镜中心。用例检查菜单选项、实际挂载的效果、滚动位移和退出清理。去掉 `--blackhole` 可以取得同后端的无透镜对照。默认纵拖表体。在命令前加 `GODOT_JFX_DRAG_AXIS=h` 横拖整张表；核对日志的 `VFX_TABLE_AXIS h` 和 `displaced_px`。两个驱动串行运行。

```sh
scripts/wsl-wayland-session.sh --isolate-wslg scripts/wsl-gpu.sh vulkan scripts/test-vfx-table-scroll.sh --driver vulkan --blackhole --profile
scripts/wsl-wayland-session.sh --isolate-wslg scripts/wsl-gpu.sh opengl scripts/test-vfx-table-scroll.sh --driver opengl --blackhole --profile
```

这个入口创建 Weston 的 headless 输出和仅属于本次测试的虚拟键鼠。客户端连接私有 Wayland 套接字。窗口管理行为以该 Weston 会话为准，WSLg 和 Windows 桌面的前台切换需要单独验收。

可选的 `--compositor labwc` 在该私有 Weston 桌面内启动 labwc，供应用连接其原生 Wayland 显示。需要已安装的 labwc，或用 `GODOT_JFX_LABWC_ROOT` 指向按 Ubuntu 软件包布局解包的 labwc 及依赖。此模式可以验证支持 `xdg-toplevel-icon-v1` 和 `xdg-activation-v1` 的桌面。两种协议的可用性取决于合成器。

```sh
scripts/wsl-wayland-session.sh --isolate-wslg --compositor labwc scripts/run-linux-tests.py --group NonRobot --driver all --test test-window-icon test-vfx-window-controls
```

私有 labwc 的默认服务端装饰会占用最大化窗口的客户区。本机在 1280×720 输出上测得 1280×694。VFX 自绘标题栏用例需要核对完整工作区，可用下面的命令为夹具选择客户端装饰，同时保留尺寸、最小化和恢复断言。

```sh
scripts/wsl-wayland-session.sh --isolate-wslg --compositor labwc --test-layout 1280x720+0+0 scripts/run-linux-tests.py --group NonRobot --driver all --test test-vfx-window-controls
```

在 labwc 的 `test-wayland-windows` 中，原生子窗口在首次显示后开启模态，隐藏、重显后再取消。脚本校验两个原生表面的角色申请、模态设置和销毁，成功时输出 `WAYLAND_DIALOG_ROLE_PASS`。缺少 xdg-dialog-v1 的合成器仍执行父子关系、窗口寿命、尺寸与 GPU 像素检查。

隔离会话没有外网。用 `test-godot-library` 和 `test-shadow-jar` 验证发行包时，可从已校验的本地缓存准备公共 Maven/Gradle 插件及其依赖的文件镜像。Maven 用当前进程的 `MAVEN_ARGS=-s <settings.xml>` 将 `central` 指向镜像；Gradle 在会话私有的 `init.d` 下通过 `beforeSettings` 将该镜像加入 `pluginManagement.repositories`。镜像排除项目发行模块。Maven 用例仍用全新的本地仓库从夹具的回环 HTTP 服务解析模块并核对哈希，Shadow 用例仍从本次暂存仓库构建 JAR。11 月 24 日的镜像配置与用例日志位于 `agentdir/artifacts/wayland-release-nOfa55Xe/`。

在 WSL2 中给该入口加 `--isolate-wslg` 会使用 bubblewrap 隔离宿主显示和输入设备。运行前可用 `scripts/run-linux-tests.py --group Robot --driver all --list` 查看 22 项清单。默认的私有 Weston 14 缺少公共 Robot 所需的虚拟输入和截图协议。获得桌面输入授权后，可按下列 labwc 和 niri 分组串行执行整份清单。虚拟键盘用例检查未支持请求的日志和后续宿主帧，两项 PASS 仅覆盖这个约定。Robot 指针、按键、像素采样与跨窗口拖放有各自的检查。

在提供虚拟指针、虚拟键盘和输出图像复制的 labwc 上，公共 JavaFX Robot 可以驱动 Wayland 图形测试。桌面坐标用例依赖窗口的实际位置。下面的命令在私有合成器中设置 2560×1800、1 倍缩放的输出，并把窗口放到用例请求的逻辑坐标。每条命令使用新的桌面，保留原有动作、像素和资源断言。使用单独解包的 labwc 时，`GODOT_JFX_LABWC_ROOT` 指向包含 `usr/bin/labwc`、`wlr-randr` 和依赖库的目录。

```bash
scripts/wsl-wayland-session.sh --isolate-wslg --compositor labwc --test-layout 2560x1800+40+80 scripts/run-linux-tests.py --group Robot --driver all --test test-drag-drop
for driver in vulkan opengl; do
    for cases in default variants; do
        scripts/wsl-wayland-session.sh --isolate-wslg --compositor labwc --test-layout 2560x1800+80+80 scripts/run-linux-tests.py --group Robot --driver "$driver" --cases "$cases" --test test-robot
    done
done
scripts/wsl-wayland-session.sh --isolate-wslg --compositor labwc --test-layout 2560x1800+640+333 scripts/run-linux-tests.py --group Robot --driver all --test test-vfx-table-scroll test-hover-demo
scripts/wsl-wayland-session.sh --isolate-wslg --compositor labwc --test-layout 2560x1800+120+120 scripts/run-linux-tests.py --group Robot --driver all --test test-hover-flicker
scripts/wsl-wayland-session.sh --isolate-wslg --compositor labwc scripts/run-linux-tests.py --group Robot --driver all --test test-native-ime test-virtual-keyboard
scripts/wsl-wayland-session.sh --isolate-wslg --compositor labwc --test-layout 2560x1800+300+300 scripts/run-linux-tests.py --group Robot --driver all --test test-physical-drag
```

跨进程 GTK 拖放的四个 Robot 用例可以在私有 Weston 内另启 niri。已验证的 niri 版本为 `02ee0585`，支持 Esc 取消原生拖放、虚拟指针和键盘，以及输出图像复制。准备该可执行文件、GTK 3、grim 和 Pillow。若 niri 和依赖单独解包，设置 `GODOT_JFX_NIRI_BIN` 和 `GODOT_JFX_NIRI_LIBRARY_PATH`。下列命令在同一私有桌面依次运行两个驱动的默认和 runtime 用例。

```sh
scripts/wsl-wayland-session.sh --isolate-wslg tests/wayland/niri-external-drag.sh --driver all
```

GTK 对端在拖动时用 grim 连同光标截图。测试光标在中心四周各有一个可见标记，留出中央像素测量半透明的 8×6 拖动预览。脚本同时校验四个标记、图像尺寸和颜色。JavaFX 拖出、GTK 拖入及 Esc 取消各有独立断言。labwc 0.9.3 在 Esc 后释放按钮时仍完成 COPY，详情见[原生拖放的实测记录](docs/glass-godot.md#drag-and-drop-on-linux-wayland)。

Wayland 的外部拖放注入用例需要 Weston 14 开发头、Wayland Server、pixman 和 xkbcommon 开发头。若 Weston 头文件单独解包，使用 `GODOT_JFX_WESTON_INCLUDE` 指向包含 `libweston/libweston.h` 的目录。`test-drag-drop-ole-inject.sh` 在临时 Weston 中加载测试模块，按夹具 PID 和标题选取接收表面，通过原生 `wl_data_offer.receive` 管道交付文本、URL、文件、HTML、RTF 和自定义格式。成功的复制需要收到 `wl_data_offer.finish`。Java 观察器校验每种格式，等待宿主读到成功标题后关闭 Stage。超时变体还要求阻塞的 FX 线程拒绝前一个请求。测试模块仅使用私有显示。隔离 Weston 的外拖手势、拒收和返回本应用的专项结果见 [Wayland 拖放记录](docs/glass-godot.md#drag-and-drop-on-linux-wayland)。标准 JavaFX Robot 组另有独立结果。

授权使用隔离输入后，可以用 Weston 的任务切换器恢复 VFX 子窗口。在私有 Weston 会话中，测试先选择主窗口，确认 JavaFX 子窗口仍为最小化，再选回子窗口，核对 Wayland 座席焦点、原窗口尺寸、VFX 关闭按钮和资源清理。可分别选择 `vulkan`、`opengl`，加 `--runtime` 验证独立夹具项目。普通 `test-vfx-window-controls.sh` 继续单独检查应用请求恢复的行为。

```sh
scripts/wsl-wayland-session.sh --isolate-wslg scripts/wsl-gpu.sh vulkan scripts/test-vfx-window-controls.sh --driver vulkan --weston-restore
```

Linux 的 `test-startup.sh` 在原生 Wayland 上以 xdg_toplevel 和对应 wl_surface 的有效缓冲提交检查首次显示、实际标题、隐藏重显和次级窗口映射。logo、hidden 和各自的取消场景
还会在 Godot 内检查首帧及启动动画。

Linux 的 `test-native-stage.sh` 还会在同一次 FX 回调里依次请求最小化与恢复、
最大化与恢复。窗口管理器处理完请求后，用例核对 JavaFX Stage 属性、Godot
原生窗口模式、原始位置和尺寸，以及子窗口实际呈现的颜色。

### 安装开发测试的 Maven Local 依赖

编好本平台的 Godot 共享库和带 Media 的 JFX SDK 后运行安装命令。Windows 用 `python scripts/maven_local.py install`，macOS 用 `./scripts/maven_local.py install`。默认使用本平台的暂存脚本，将当前构建产物重新打包到 `artifacts/godot-library` 后安装。传入 `--runtime <目录>` 会直接安装该目录里已有的发行包。安装器使用 PATH 中的 Maven 或仓库的 `.tools/apache-maven-3.9.9`，也可传 `--maven <可执行文件>`。安装和解析命令都显式传入 `-Dmaven.repo.local=<项目根目录>/.m2/repository`，构件和首次下载的 Maven 插件均保存在项目内。

安装器将六个 POM、六个普通 JAR 和本平台的两个 classifier JAR 安装到 Maven Local，并核对 Maven 解析的 JAR 与 staging 文件的内容。重新编译 SDK 或 Godot 共享库后再执行一次安装，即使版本号相同也如此。公共场景启动器和 `test-scroll-settings`、`test-screen-layout`、`test-render-command-validation` 根据根配置版本和当前平台直接在项目的 `.m2/repository` 中定位六个运行时 JAR。graphics 和 media 选用平台 JAR，其余四个模块选用普通 JAR。查看当前选择时，把对应平台安装命令中的 `install` 换成 `module-path`。其他场景的 Java 观察器仍按各自脚本编译。模块路径和 Shadow 发布验收继续从显式指定的 staging 仓库读取本次发行包。

### Windows 库模式的独立验收

Windows 场景入口和性能脚本由 JDK 直接启动测试进程，classpath 包含本次 Maven 发布的 Windows graphics、media 平台 JAR、其余 JavaFX 模块和应用观察器。`GodotSceneFixture` 调用 JavaFX 原生库加载器，核对进程中加载的引擎文件与 JAR 中 `godot.dll` 的 SHA-256，并输出 PID 和库路径。场景夹具继续选择 Java 观察器并检查窗口、像素和资源回收，二者共用该 JVM。普通应用启动与退出另外由模块路径和 Shadow 用例覆盖。源码 Editor 只用于预先导入或导出资源。独立 C++/Java 单元测试、刻意破坏依赖的负向测试和显式 D3D 对照保留各自的被测对象。

完整 VFX Demo 构建后，在 macOS 上运行 `./scripts/test-vfx-demo-jar.py`，在 Windows 上运行 `python scripts/test-vfx-demo-jar.py`，检查 Intro 类和资源，拒绝含 JVM 动态库的 JAR，并用已安装的 JDK 25 在只含该 JAR 的临时目录启动。Windows 使用普通交互入口，连续观察可见的 VFX Intro 窗口至少 20 秒，出现系统替代窗口即失败。读取该 Java 进程实际映射的模块，核对引擎 DLL 的构建缓存路径和 JAR 内资源哈希。随后向原窗口投递最大化和还原命令，每次均验证窗口状态发生预期变化，最后发送原生关闭消息。macOS 使用 `--smoke` 验证 Stage、菜单和关闭事件，并从该 Java PID 的映射文件核对 dylib 的缓存路径和 SHA-256。两端均检查退出状态和目录内仅余原始 JAR。普通交互启动用 `java -jar artifacts/vfx/libs/vfx-demo.jar`。

从仓库根目录构建并准备发行包后，使用 JDK 25、Python 和 Maven 3.9 运行下列命令。首次解析 Maven 插件需要联网。消费工程从本机回环地址读取本次发行的 Maven 仓库，Java 子进程的 PATH 只包含 JDK 和 Windows 系统目录。

```powershell
.\scripts\stage-godot-library.ps1 -Destination 'D:\Godot JavaFX'
python scripts/test-godot-library.py --runtime 'D:\Godot JavaFX' --maven 'D:\tools\apache-maven\bin\mvn.cmd'
python scripts/test-shadow-jar.py --runtime 'D:\Godot JavaFX'
```

默认依次执行启动、失败处理和绘制三组。可用 `--group launch`、`--group failures` 或 `--group render` 单独复测。绘制组包含 Oracle 与 Lk 两个媒体用例，`--group media` 可单独运行这两个用例。两个视频都由 `scripts/setup-env.py` 准备。默认使用新的临时目录，控制台的 `Evidence` 行给出位置。`results.json` 记录子进程命令、退出码、耗时、JAR 哈希和受检查的 DLL 路径，工作目录下的 `artifacts/reference` 分别保存 `media*.png` 和 `media-lk*.png`。

`postSceneMessage` 的独立用例包含在 render 组和默认 NonRobot 回归中。从仓库根目录执行以下命令可单独验证：

```sh
python scripts/test-godot-library.py --runtime artifacts/godot-library --group scene-message
```

Java 发送端使用发行模块的公开 API，检查非 FX 线程、空引用、空字符串和超长主题的拒绝行为。Godot 场景根节点检查主线程、五条消息的主题与整数值、重复消息和顺序，覆盖 128 个 UTF-16 码元的主题及 32 位整数上下界。通过时输出 `PASS scene-message`，证据目录中的 `scene-message.log` 记录两端标记及应用退出标记。

启动组覆盖显式与自动初始化、无 main 的类、模块化入口、并发、配置冲突、隐藏最后窗口后再次显示以及退出。失败组要求重复初始化和等待者观察到同一错误，约定退出码为 31；显式退出用例应保留 37。启动组的 `exit-toolkit` 在 JVM 关闭钩子中等候宿主开始停止，然后调用 `Platform.isFxApplicationThread()`。钩子须取得已有 Toolkit，报告 `SHUTDOWN_TOOLKIT_PASS` 并保留退出码 37；显式重启宿主仍须被拒绝。绘制组使用 Godot 合成输入、独立 Stage、GodotView 像素、Node Shader 原有断言及 Effect 的 D3D 参考图，还验证本地视频的暂停、seek、重播和释放。

Shadow 脚本通过 Gradle Wrapper 和 Shadow 插件在独立目录构建消费应用。首次构建需要联网解析插件。它把单 JAR 复制到空目录，清理启动环境，核对应用 PID、实际映射的 DLL 与 JAR 资源哈希、Stage、外来工程隔离和视频；另构建带场景包和带损坏包的 JAR，检查 GodotView 合成像素、第二个 Stage、引擎合成输入和启动失败。控制台输出日志和截图目录。用相同 Maven 版本号重新发布后，两条验收命令均使用新的工作目录，避免上次的 release 缓存参加验证。

当前宿主只支持 Viewport＋safe；渲染器仍可选择 mobile 或 gl_compatibility。
RD-direct 实现、编译开关、专用探针和 separate 专用运行路径已删除。
`test-render-mode-rejection.ps1 -Driver opengl` 故意直接传入 Godot 的 separate 参数，要求
宿主在登记 JavaFX 桥接和启动应用前拒绝，输出唯一的预期错误，并释放全部宿主资源。
此负向夹具仅适用于 OpenGL。直接运行时省略驱动会报告 SKIP。
其他测试的 `-RenderThread` 仅接受 safe；`-RD` 与 `-JavaFXRDDirect` 已移除。
历史日志中的 RD/separate 结果不能作为本次构建的验收证据。


## VFX Godot 后端检测

构建 JFX 和 VFX 后运行 `scripts/test-prism-godot-detection.ps1`。
隔离类加载器分别验证标记类型缺失、字段缺失、类型错误、非静态/私有字段、
false/true 值，以及 true/false 结果缓存。需 `PRISM_GODOT_DETECTION_PASS`。
`test-vfx-blackhole.ps1` 及其 `-NativeD3D` 档验证真实后端下的开关显隐。
首次检测应在 JavaFX 启动后；启动前的 false 也会被缓存。

## VFX 黑洞特效

先执行 `build-vfx.ps1` 更新 Demo 类（包括内嵌着色器），再运行
`test-vfx-blackhole.ps1`（默认 mobile/safe/Viewport）；
`-Driver opengl` 验证 OpenGL；仅支持 safe 线程模式。
需要源码 Editor、SDK、已发布的 Windows 平台 JAR 和 VFX 产物，不需要真实键鼠授权。

夹具在 Intro 菜单抽屉从场景图移除后采集基线，检查菜单末尾的复选框、效果只附着于内容 VSceneGroup、
标题栏和底部导航不变、开关恢复、鼠标移动/拖动和缩放后的
位置映射、鼠标位于组外时对组内边缘图形的扭曲，并读回 GPU 图像断言可见特效、鼠标静止时的画面稳定性、范围外不变和
透明边缘保持；退出后检查窗口与
宿主资源释放。必须同时有 `VFX_BLACKHOLE_PROBE_PASS`、`GODOT_VFX_BLACKHOLE_PASS`
且无异常或着色器错误。`-NativeD3D` 只验证原生对照中不添加该选项，不代表 Godot
特效通过。日志和逐步截图使用 `vfx-blackhole-<driver>-safe` 前缀。 Linux 的 `scripts/test-vfx-blackhole.sh --profile --driver vulkan|opengl` 还会在相同页面移动镜头，记录 90 个脉冲间隔，再继续原有像素检查。

## 运行前

工具路径可通过 `JAVA_HOME`、`MSYS2_ROOT`、`VSINSTALLDIR` 配置，默认值和参数优先级见 [构建说明](docs/build-windows.md)。剪贴板文件列表中的路径是虚构测试数据；Java 观察器与 PowerShell 校验使用相同值，不依赖开发者的实际工作目录。

Windows 命令在仓库根目录用 PowerShell 7.4.1 或更高版本（`pwsh`）执行。分组测试用同一份 `pwsh` 启动各 PowerShell 用例。macOS arm64 的 shell 入口见下文“macOS arm64 入口”一节。脚本自行编译 Java/C++ 测试观察器，但通常**不会重新构建生产 SDK 或 Godot**。修改生产代码后先构建对应产物，协议变化必须同时更新宿主和 SDK。重新链接共享库前先结束使用该文件的进程。

表中前置条件缩写：

| 标记 | 需要准备什么 |
| --- | --- |
| G | 源码 Godot Editor（仅导入测试资源）、`godot-library` 共享库、`stage-godot-library.ps1` 发布的 Windows 平台 JAR，以及可用的 Windows 图形桌面与 GPU 驱动 |
| J | JDK 25（默认 `$env:JAVA_HOME`，可用 `-Jdk` 覆盖）和 `jfx/build/sdk`；必须是本仓库源码 SDK |
| M | `build-windows.ps1 -Target jfx` 生成的 SDK 包含 jfxmedia/glib-lite/gstreamer-lite/fxplugins 原生库 |
| V | 执行 `build-vfx.ps1`，准备 `artifacts/vfx` 的主类、测试类、资源和依赖 |
| Runtime | Windows 上以隔离目录中的项目和默认主场景运行同一个 DLL；Editor 负责资源导入 |

J-only 测试不需要启动 Godot，但其内部 API/模块补丁依赖本地 SDK。Windows 的 G-only 场景也由 Java 加载引擎，可在场景内单独验证没有 JavaFX 应用连接时的行为。首次构建需要的工具安装、下载与路径见 [build-windows.md](docs/build-windows.md)。

GPU/GUI 测试串行执行；性能测试期间保持窗口前台，不进行其他操作，不同时构建或运行重负载。多数功能测试使用宿主注入输入，不需要人工点按钮，也不能据此宣布真实鼠标/IME/触摸验收完成。

| 平台 | 单项测试与 Demo 的驱动参数 | 省略时 | 完整回归矩阵 |
| --- | --- | --- | --- |
| Windows | `-Driver d3d12`、`-Driver vulkan`、`-Driver opengl` | D3D12 | `run-windows-tests.ps1 -Driver all` |
| macOS | `--driver metal`、`--driver opengl` | Metal | `run-macos-tests.py --driver all` |
| Linux x64（Wayland） | `--driver vulkan`、`--driver opengl` | Vulkan | `run-linux-tests.py --driver all`，WSL2 使用[隔离桌面](#linux-原生-wayland-窗口) |

Demo、Shader 和 Effect 观察器，以及 Unicode 路径的目录和 PCK 验收，均由标准 JavaFX 入口自动启动 Godot。仅 `LibraryLifecycle` 的专用 API 用例显式初始化，以检查重复调用、并发、失败传播和冲突配置。

Python 发布验收脚本在三个平台均使用 `--driver`。普通 JavaFX 应用使用 `-Djavafx.godot.driver=<驱动>`，Demo JAR 也接受 `-jar vfx-demo.jar --driver <驱动>`。引擎日志使用 Godot 原生名称，`opengl` 对应 `opengl3`。原生 JavaFX 对照通过 `-NativeD3D` 或 `-Backend d3d` 启动，该档省略 Godot 的 `-Driver`。

Windows DLL 回归用 `./scripts/run-windows-tests.ps1 -Group NonRobot` 或获得授权后的 `-Group Robot`。两组都支持 `-List` 预览。Robot 组包含系统虚拟键盘、原生 IME、文件对话框、外部拖放和显式物理输入档，即使没有移动鼠标，只要入口会唤起触摸键盘也归入这一组。虚拟键盘的 `-CompileOnly` 只编译，`test-tabtip-result.cmd` 使用模拟接口，均不请求系统键盘。NonRobot 也运行上节的模块路径、Shadow 和完整 Demo JAR 三个 Python 验收入口。

**Windows 回归耗时较长。除非明确指定，优先用 `-Test` 选择与改动相关的用例，只跑 Godot D3D12。** NonRobot、Robot 和适用的单项渲染测试均默认只跑 D3D12。显式传 `-Driver vulkan` 或 `-Driver opengl` 可单测其他驱动，`-Driver all` 才会把适用的场景、模块路径绘制、Shadow 消费者和隔离 Demo JAR 在三个驱动上串行各跑一次。D3D12 和 Vulkan 使用 `mobile`，OpenGL 使用 `gl_compatibility`。完整分组中的无 GPU 单元测试和启动/故障契约只跑一次。OpenGL 启动契约和 separate 负向用例随 OpenGL 或完整矩阵运行。原生 JavaFX 的 D3D 对照只提供参考图。

```powershell
.\scripts\run-windows-tests.ps1 -Group NonRobot -List
.\scripts\run-windows-tests.ps1 -Group NonRobot -Test test-godot-view
.\scripts\run-windows-tests.ps1 -Group NonRobot -Test test-godot-view -Driver vulkan
.\scripts\run-windows-tests.ps1 -Group NonRobot -Test test-godot-view -Driver opengl
.\scripts\run-windows-tests.ps1 -Group NonRobot -Driver all
.\scripts\run-windows-tests.ps1 -Group Robot -Driver all  # 须先获真实输入授权
```

默认的 `-Cases All` 还覆盖支持 `-Runtime` 的独立项目和专项渲染场景，包括 GodotView 变换、命令批次边界、快照读回、媒体样本和窗口生命周期。用 `-Cases Default` 或 `-Cases Variants` 可分别运行基础用例或专项用例；`-List` 打印实际参数。可调的循环次数、采样时长和性能分析开关沿用各入口的专项说明。

运行前重新构建并发布 Godot 共享库，然后用 `python scripts/maven_local.py install --runtime artifacts/godot-library` 刷新本地测试模块。场景夹具、模块路径应用、Shadow 消费者和 Demo JAR 均用 JVM 属性 `-Djavafx.godot.driver=<驱动>` 选择驱动。脚本的 `-Driver` 或 `--driver` 会传入该属性；单项脚本与回归运行器共用同一启动入口。回归运行器从本用例新写入的场景日志逐份检查 `Using Device` 行，同一用例启动多个夹具时分别核对。用例日志保留设备原文。模块路径、Shadow 和 Demo JAR 测试直接核对各自 JVM 的启动日志。原生 JavaFX 对照、纯 CPU 测试和引擎启动前即被拒绝的配置无需设备行。结果目录的 `results.csv` 按用例和驱动记录退出码、耗时及日志位置；场景日志和截图按驱动分别留存。三个 Python 发布测试的日志给出各自的验收位置。

**前台与真实输入要求要分别判断**：Godot 合成输入和模块测试钩子不占用真实键鼠，但是否允许失焦取决于夹具；只有明确注明免前台的测试（如 ole-inject）才可据此后台运行。性能比较始终要求保持焦点并避免其他重负载。Robot 物理夹具会占用输入设备，须先获得用户授权、保持桌面空闲；同一会话中已有明确授权且未撤销时不必重复询问，开始前说明会操作真实输入。原生 IME 夹具（`test-native-ime.ps1` / `test-native-ime.sh`）调用 `DisplayServer.warp_mouse` 移动系统光标，运行非物理输入测试时须排除整个入口。文件对话框专项使用限定本轮进程/标题的系统消息驱动，具体方式见该节。GPU/GUI 测试仍串行执行。

在 Windows 上直接运行适用的场景脚本（例如 `.\scripts\test-godot-view.ps1`）默认使用 D3D12，包括带 `-Runtime` 的独立项目。单项可直接传 `-Driver vulkan` 或 `-Driver opengl`。用回归运行器的 `-Test` 配合 `-Driver all` 可让同一单项跑三后端。**可选参数以表中“可选公共参数”及后文该测试的专项说明为准**：`-RenderThread safe`、`-Runtime` 并非所有脚本支持。`-Jdk` 用于覆盖 JDK 路径。RenderThread 固定为 safe。

## 驱动配置验收

在仓库根目录运行 `python scripts/maven_local.py install --runtime artifacts/godot-library` 准备本平台的发布模块，使用 JDK 25。Windows 用 `python`，macOS 和 Linux 可用 `python3`。

```sh
python scripts/test-driver-config.py
python scripts/test-driver-config.py --driver opengl
python scripts/test-driver-config.py --driver all
```

**三个平台均以 Godot 的 `Using Device` 设备行判定实际驱动。** 每次需要验收驱动的引擎启动都须输出一条设备行。行首的 `D3D12`、`Vulkan`、`Metal`、`OpenGL API` 分别对应 `d3d12`、`vulkan`、`metal`、`opengl`。设备行缺失、重复、API 无法识别、与预期不符，或宿主标记 `GODOT_LIBRARY_DRIVER` 缺失或不一致，均判失败。M1、网格变换、生成着色器、渲染线程退出和 Demo 启动脚本单独运行时也执行这项检查。

驱动配置专测为每种配置启动一个新的普通 JavaFX 应用 JVM，同时核对窗口启动与关闭。控制台的 `actual` 来自设备行。例如 `OpenGL API … - Using Device: …` 对应 `actual=opengl`，宿主标记应为 `opengl3`。

应用显示窗口后，测试用 JDK 25 的 `jcmd <PID> VM.dynlibs` 读取该 JVM 已加载的动态库，完整清单保存在同一日志目录的 `<配置>-modules.txt`。Windows 还要求存在 `godot.dll` 和对应的 API 库（`D3D12.dll`、`vulkan-1.dll` 或 `opengl32.dll`）；macOS 检查 `libgodot.dylib` 并列出观察到的 Metal/OpenGL 框架，Linux 检查 `libgodot.so`。多个 API 库可以同时出现，活动后端由 `Using Device` 行判定。macOS 真机复测时也需核对动态库清单。

无参数时只测平台默认后端，同时覆盖省略 JVM 属性、显式传入默认值和拒绝无效值。单选其他驱动只启动一次。`--driver all` 在 Windows 上覆盖 D3D12、Vulkan、OpenGL，在 macOS 上覆盖 Metal 和 OpenGL，在 Linux 上覆盖 Vulkan 和 OpenGL。三个平台的 NonRobot 组均包含此用例。WSL2 可用 `scripts/wsl-wayland-session.sh --isolate-wslg scripts/run-linux-tests.py --test test-driver-config --driver all`，由运行器为每个驱动选择对应的 GPU 环境。macOS 真机验收需运行全驱动命令并核对本机 GPU。

## macOS arm64 入口

**macOS 回归耗时较长。NonRobot、Robot 和适用的单项测试默认只跑 Metal。** 平时从仓库根目录直接运行与改动相关的单项。需要 OpenGL 时，分组和单项均用 `--driver opengl`。OpenGL 专用的 separate 拒绝测试须显式运行 `./scripts/test-render-mode-rejection.sh --driver opengl`；无参数时报告 SKIP。

```sh
./scripts/run-macos-tests.py --group NonRobot
./scripts/run-macos-tests.py --group Robot

# 完整双后端回归，逐组串行执行；Robot 需要真实输入授权
./scripts/run-macos-tests.py --group NonRobot --driver all
./scripts/run-macos-tests.py --group Robot --driver all
```

NonRobot 包括模块路径、独立 Shadow 消费者和完整 VFX Demo JAR。Robot 包括真实跨应用拖放、IME 光标、桌面像素和 VFX 表格拖动。运行 Robot 须授权真实输入，并给启动 Java 的应用辅助功能和屏幕录制权限。每组的结果在 `agentdir/logs/macos-<分组>-<时间>/results.csv`。可加 `--list` 预览计划，或用 `--test test-godot-view` 选择脚本。用 `--cases default` 选择各脚本的基础用例，或用 `--cases variants` 只运行附加参数组合（例如 `--runtime`、`--transform`）。默认 `--cases all` 执行两组。双后端运行时，不依赖渲染驱动的单项脚本只列一次。每项测试的原始宿主日志与 CSV 放在同一结果目录内。

macOS 上每个测试的入口是与 Windows 版同名的 `scripts/test-*.sh`（`test-protocol.cmd`/`test-bounded-lru.cmd` 的对应物为同名 `.sh`，用 clang 代替 MSVC），在仓库根目录用 sh 执行。判定标记、日志位置与通过语义和对应 ps1 完全一致；前文各表的用途说明、断言与限制仍然适用，本节只列差异。

前置条件与上文缩写表对应：G 为本机发布的 `mac-aarch64` 平台 JAR 和导入测试资源的源码编辑器，`--runtime` 档从隔离的项目目录加载同一引擎库；J 为 `JAVA_HOME` 指向的 JDK 25（可用 `--jdk DIRECTORY` 为本次调用覆盖；两者均缺失时报错）和本仓库 `jfx/build/sdk`（mac 的 dylib 在 `lib/`）；M 已并入 mac 的单次 Gradle SDK 构建（AVFoundation 后端，见 [build-macos.md](docs/build-macos.md)），没有单独的 Media 构建脚本；V 为 `./scripts/build-vfx.sh` 的产物。`--driver metal` 在本机 M1 的共享库中报告 Metal 3.1，`--driver opengl` 走 OpenGL 4.1；未构建 Vulkan（未安装 MoltenVK）。

PowerShell 开关对应小写长选项：`-Driver d3d12` → `--driver metal`、`-RenderThread safe` → `--render-thread safe`、`-Runtime` → `--runtime`、`-Jdk DIRECTORY` → `--jdk DIRECTORY`。场景测试的 `--runtime` 使用单独导入的项目。`test-media-video.sh`、`test-media-churn.sh`、`test-vfx-blackhole.sh` 和 `test-vfx-ripple.sh` 的 `--native` 使用本机 SDK 的 Mac Glass 和 Prism Metal，可与同一 Java 探针的 Godot 结果对照。Windows 句柄分类和 Media Foundation provider 统计依赖 Windows API。

以下为 macOS 的夹具行为和实机观察。当前 JAR 构建的结果见[验收记录](docs/acceptance-status.md#macos-arm64-verification-scope)。

- `test-window-icon.sh` 驱动两个 Stage 完成七轮设置、替换和清除图标，检查每一步的宿主查询均返回 `installed=false`，并检查窗口和资源回收。Dock 图标由 NSApplication 管理。
- `test-scroll-pan.sh`（macOS、Linux，无 Windows 对应）：触控板 pan 流契约探针。Godot 侧按阶段标题注入 `InputEventPanGesture` 流（向下、过冲、向上、过冲、松手静置），Java 探针断言 vvalue 单调、两端精确钳制、松手后不再移动，并比对注入数与 ScrollEvent 数精确相等（exactly-once；上游 Godot 对手势事件双重派发，本 fork 已修复为单次）。双渲染器通过。
- 四个原生组件测试有同名 `.sh` 入口。`test-clipboard-ownership` 检查 Java 文本复制及拒绝无效输入时的 NSPasteboard 所有权，`test-dnd-drag-image` 检查 Cocoa 拖动预览的像素和锚点，`test-dnd-helper-lifetime` 检查 JNI 回调失败及关闭竞争（支持 `--asan`），`test-tabtip-result` 检查 macOS 键盘请求与释放返回不支持。`test-virtual-keyboard.sh --robot` 使用同一个 Java 探针，检查请求和释放后的宿主 tick、警告和清理。
- Robot 物理夹具在 macOS 的运行现状（均需用户授权、保持桌面空闲，启动 Java 的应用需辅助功能与屏幕录制权限）：`test-robot.sh`、`test-drag-drop.sh --robot`、`test-physical-drag.sh --robot`、`test-hover-flicker.sh --robot`、`test-hover-demo.sh`、`test-drag-drop-external.sh` 均已用本机发布的 dylib 在两个渲染器下运行。hover-flicker mobile 曾偶发 Fusion 定居亮度抖动（单帧 502/584 不亮），修复后复跑 3 次全部通过，按环境性抖动记录、机制未定位。hover-demo 的 GAP 像素判定曾按帧数跳过过渡期（31 帧），但 VFX 退出过渡是墙钟驱动、帧率下降时跨越更多帧，GAP 按墙钟留出 500ms 过渡。观察器在鼠标进入空白区后标记 GAP，在移向按钮前结束 GAP；5% 亮度误差阈值沿用原值。Robot 坐标在 macOS 走真实 CGEvent；窗口允许置于菜单栏之上（与 Windows 离屏一致），macOS 原生边缘缩放在 FX 宿主窗口关闭（热区会吞掉角落按下，FX 缩放把手收不到事件），本机 scale=1，HiDPI 未验证。
- `test-clipboard.sh` 用 macOS 原生对端直接读写共享 NSPasteboard，校验两个方向的实际格式交换。
- Temurin 25.0.5 aarch64 的 FFM downcall 会随机导致 JVM 崩溃（C2 相关，可在 Godot 之外独立复现）；churn/soak 探针改用 `ps` 采样 RSS、以 `/dev/fd` 计数代替句柄类型统计，判定标准不变。
- 历史窗口组诊断在 macOS 的现状：`test-window-commands.sh`、`test-window-resize.sh`、`test-popup-edge.sh` 在双渲染器通过。`test-window-resize.sh` 修复了两个真实缺陷（判定未变）：宿主 resize 命令原先可能在 `frame_post_draw` 应用，根渲染目标在该帧绘制之后重建导致读回空帧，现含 resize 的批次推迟到下一帧绘制前应用；Metal 上 FX 视口随窗口 resize 立即重建纹理，而根视口每帧先于 FX 视口绘制，会采到一空帧，现 resize 推迟到该尺寸的下一帧 present 并以视口交换过渡（旧视口纹理继续呈现到新视口首帧绘制完成），对 Windows 同为改进。`test-popup-edge.sh` 是探针就绪条件缺陷：FX 先设标题后发原生窗口配置，看到标题当帧原生窗口仍不可见，合成点击落到根窗口触发 autoHide；现等待原生窗口可见再点击。`test-logical-windows.sh`、`test-window-composition.sh`、`test-window-order.sh` 的早期记录来自历史嵌入模型；迁移至独立原生 Stage 后，三个入口均已在 macOS 的两个渲染器通过，包括十个阶段的窗口层序和六个阶段的合成像素。`test-window-lifecycle.sh` 在双渲染器通过：macOS 隐藏最后一个可见 FX Stage 会 orderOut 根 NSWindow，`DisplayServerMacOS::window_can_draw` 随之关闭，Godot 跳过 `RenderingServer.draw`、`frame_post_draw` 不再触发（Windows 隐藏窗口继续绘制）；场景等待改为绘制信号与短定时器竞速避免挂起，隐藏态像素断言在 macOS 跳过（隐藏窗口不参与绘制、像素本质不可观测），状态覆盖、清理与资源断言不变。


### macOS 构建与诊断脚本对照

其余同名测试使用 `.sh`，发布与日志分析中的 `.py` 脚本可在两端直接运行。下面列出使用不同入口或系统工具的项目。

| Windows 入口 | macOS 入口与用途 |
| --- | --- |
| `build-windows.ps1`、`build-jfx-media.ps1` | `build-macos.sh --target godot-editor\|godot-library\|jfx`，其中 `jfx` 同时构建 SDK 和 AVFoundation Media |
| `build-makedepend.ps1` | `setup-env.py` 准备本地构建工具。macOS Media 使用 Xcode 工具链处理原生源码依赖 |
| `run-windows-tests.ps1` | `run-macos-tests.py --group NonRobot\|Robot --driver metal\|opengl\|all` |
| `godot-fixture.ps1`、`native-output.ps1` | `godot-fixture.py` 与 shell 的标准输出及退出状态。原生构建日志在 `agentdir/logs/build-macos-*.log` |
| `benchmark-vfx-frames.ps1`、`benchmark-vfx-transitions.ps1` | `profile-vfx.py frames`、`profile-vfx.py transitions`。可用 `--driver` 选择后端。`frames --native` 使用原生 Mac Glass 和 Prism Metal |
| `profile-vfx-gpu.ps1`、`profile-vfx-menu.ps1`、`profile-vfx-loading.ps1` | `profile-vfx.py gpu`、`profile-vfx.py menu`、`profile-vfx.py loading`，分别采集 GPU、菜单和加载测量。Linux 菜单用例可加 `--host120` 对照 CPU 限帧时的交互表现。 |
| `make-media-fixture.ps1`、`benchmark-media-frames.ps1` | `make-media-fixture.py` 通过 ffmpeg 生成并读回 960 帧 1080p60 H.264 视频。`benchmark-media-frames.py --native60` 验证清单和哈希后测量帧率，也可使用默认 Oracle 样本 |
| `capture-vfx-reference.ps1` | `capture-vfx-reference.py` 截取原生 JavaFX 页面。Linux ES2 基线保存在 `agentdir/artifacts/vfx-pages-es2/`（冻结动画时为 `vfx-pages-es2-frozen/`），比较脚本从同一位置读取。macOS 使用 Mac Glass / Metal。支持 `--freeze-fusion`、`--page-limit`。使用 `.tools/pyenv/bin/python scripts/compare-vfx-pages.py --driver metal` 对比页面 |
| `repro-hover-manual.ps1` | `repro-hover-manual.py` 启动带 hover 采样的窗口，关闭后分析停顿与亮度。传入 `--log-path` 可分析已有记录 |

## 拖放专项

```powershell
.\scripts\test-drag-drop.ps1 -Driver d3d12
.\scripts\test-drag-drop.ps1 -Driver opengl -RenderThread safe
```

前置条件为 G+J，需要构建修改后的 OpenJFX SDK。脚本使用 Godot 输入注入（按窗口 ID 投递，不要求窗口前台或置顶，可在其他应用持焦点时后台运行），不修改系统剪贴板；不需要创建拖放文件，文件列表只传递路径，不读取文件内容。可选参数为 `-Jdk`、`-Driver`、`-RenderThread`、`-Robot`。

观察器验证 COPY/MOVE/LINK、同窗口及独立 Stage 间传输，核对中文文本、HTML、RTF、URL、文件列表和自定义格式；同时检查拒绝、Escape 取消、源窗口/目标窗口隐藏时的完成事件及最终资源清理。首个用例将后续移动和释放放在同一批宿主输入中，以检验嵌套拖放循环不会遗失已排队事件。脚本必须同时获得 `DRAG_DROP_PROBE_PASS` 和 `GODOT_DRAG_DROP_PASS`，无异常或 ERROR。

加 `-Robot` 时，Java 观察器通过标准 Robot 调用 Windows 输入合成，宿主停止注入事件；同样的七个用例必须通过。该模式会移动系统鼠标，使用置顶测试窗口，结束或断言失败后释放按键并恢复鼠标位置；请勿同时操作其他窗口。默认注入模式仍用于同批事件边界测试。

跨进程 OLE 拖放有独立夹具：

```powershell
.\scripts\test-drag-drop-external.ps1
.\scripts\test-drag-drop-external.ps1 -Driver opengl
.\scripts\test-drag-drop-external.ps1 -Runtime
```

前置条件为 G+J。`-Runtime` 从隔离的场景目录启动同一 DLL。脚本编译并启动两个由 `tests/native/dnd_helper.cpp` 编译到 `artifacts/native-tests/dnd_helper.exe` 的 Win32 OLE 端点（一个接受放入的 IDropTarget，一个在按下时发起 DoDragDrop 的源），由 Java 观察器用 Robot 驱动真实鼠标完成三个阶段：向外部进程拖出 text+URL+文件列表、从外部进程拖入三格式数据、Escape 取消拖出。helper 窗口按系统 DPI 缩放放置（FX 逻辑坐标 × 缩放 = 物理像素），均为置顶窗口。观察器在拖出时设置 `Dragboard.setDragView(8×6, 偏移 5,3)`，判定要求 helper 日志记录的放入负载与预期完全一致（含 `application/x-godot-custom-*` 自定义格式双向负载）、DragEnter 日志包含与设置一致的 shell `DragImageBits`（尺寸与偏移，证明拖放预览图经 IDragSourceHelper 注册并可跨进程观察）、源端完成效果为 COPY、观察器打印 `EXTERNAL_DRAG_PROBE_PASS`、宿主打印 `GODOT_EXTERNAL_DRAG_PASS` 且无 ERROR。`-RenderThread`/`-Driver` 与 `-Jdk` 可用。

外部探针的 FX 驱动调用设有 10 秒超时，回调异常会使测试失败；退出时停止并回收驱动线程，逐项尝试释放输入、恢复原鼠标位置和关闭窗口，清理失败不输出 PASS。脚本恢复调用前的 helper 坐标环境变量。实际运行仍需有效用户授权和空闲桌面；不据此证明所有外部应用兼容。

macOS 等价入口（同样三阶段、同样需要授权与空闲桌面）：

```sh
./scripts/test-drag-drop-external.sh --driver metal
./scripts/test-drag-drop-external.sh --driver opengl
```

脚本编译 `tests/native/dnd_helper_macos.mm` 为 Cocoa helper（一个 NSPasteboard 放入目标、一个 mouseDragged 起拖源，均为无边框置顶 NSPanel），探针同为 `ExternalDragProbe`。macOS 与 Windows 的机制差异已在实现侧对齐：AppKit 只在真实 mouseDragged 事件分发内启动的 `NSDraggingSession` 才能跟踪物理按键，因此宿主的拖出会话推迟到下一次真实拖动事件启动（探针在 OLE 交接位置后多走两步微小移动触发，Windows 下为无害空操作）；若按键在任何拖动事件前释放，挂起的启动被取消并回报 effect 0。自定义格式在拖放路径发布为 UTI 孪生名 `application.x-godot-custom-*`（macOS 26 的 NSPasteboardItem 拒绝含 `/` 的非 UTI 类型串），入站提取时解码回 MIME 名；文件以 per-item NSURL writer 承载，跨进程序列化会静默丢弃路径不存在的文件项，脚本因此在 /tmp 下创建真实夹具文件并在退出时删除（Windows 可用不存在的 C:/ 路径）。helper 判定串与 Windows 相同（放入负载完全一致、DragEnter 观察到 8×6 预览图、源端 COPY）；预览偏移在 NSDraggingInfo 不可观测，mac 判定只覆盖尺寸。

不需要物理输入的 OLE 负载路径组件测试：

```powershell
.\scripts\test-drag-drop-ole-inject.ps1
```

前置条件为 G+J，不移动系统鼠标、不要求测试窗口前台（窗口仍需可见、会话解锁）。宿主用模块自己的 OLE 源 `DataObject` 装入 text/URL/文件列表/自定义格式负载，直接调用真实的入站拖放委托（DragEnter→Drop），观察器断言 Dragboard 读回与写入完全一致（`OLE_INJECT_PROBE_PASS` + `GODOT_OLE_INJECT_PASS`，无 ERROR）。它验证 OLE DataObject 的格式暴露、`extract`/自定义格式发现（EnumFormatEtc 枚举）和 FX 分发；跨进程 COM 封送和模态 OLE 循环仍由上面的 Robot 夹具负责。可选参数为 `-Jdk`、`-Driver`、`-RenderThread`。

macOS 等价入口为 `sh scripts/test-drag-drop-ole-inject.sh`（`--driver`、`--render-thread`、`--timeout` 参数同名小写），夹具与判定标记不变；宿主改用私有 NSPasteboard 发布负载并驱动同一入站状态机。它不验证真实 NSDraggingSession 跨进程手势。

Linux 的跨进程 Robot 入口为 `scripts/test-drag-drop-external.sh --driver vulkan|opengl`。在隔离 labwc 上，使用 `--test-layout 2560x1800+300+300` 放置三个原生窗口，GTK 目标在真实拖动时调用 grim 读取光标周围的像素，用 Pillow 测量预览图像的宽高并检查半透明颜色。应在合成器所在系统安装 grim，或通过 `GODOT_JFX_LABWC_ROOT` 提供。两种渲染驱动都检查拖入的 COPY 回复。完整用例还检查 Escape 取消。本机 WSLg 未公布这些 Robot 用例需要的虚拟输入和输出图像复制协议；独立 niri 的完整用例运行方式见上文。

拖放预览图注册机制的原生组件测试：

```powershell
.\scripts\test-dnd-drag-image.cmd
```

前置条件为 MSVC（与 test-protocol.cmd 相同）和 `JAVA_HOME` 指向的 JDK（提供 jni.h 头）。测试构造带 8×6 拖拽图（偏移 5,3）的源 DataObject，调用与真实拖出相同的 `apply_drag_image` 注册路径，断言 shell 拖拽图像助手接受该对象并写入 `DragImageBits`，且存储的尺寸/偏移与源一致、shell 附带格式可经 `SetData`/`GetData`/`EnumFormatEtc` 往返（`DND_DRAG_IMAGE_TEST_PASS`）。测试还注入 STL 分配失败，检查查询不构造文件/自定义格式负载、失败 SetData 保留调用方所有权、复制/替换释放、GetData/枚举/克隆的错误边界，以及 Next 参数失败不推进位置。还验证内置格式替换后读取新值且只枚举一次，以及旧 medium 的释放回调重入读取并追加 64 个格式后仍正确完成替换。读取侧额外要求 `DND_EXTRACTION_FAILURE_CLEANUP_PASS`：分配失败后 HGLOBAL 解锁、STGMEDIUM/枚举器释放，DragEnter/Drop 边界清空旧载荷并返回拒绝效果；会打印两条预期的 allocation failed 诊断。另以模拟 JNI 在包含两项自定义格式的载荷中逐一注入 23 个操作失败点，要求 `DND_JNI_FAILURE_CLEANUP_PASS`：异常后不继续转换、不回调半成品数据、局部引用与线程附加状态均清理。另要求 `DND_JNI_SHUTDOWN_GATE_PASS`：在附加线程前暂停时销毁入口仍被锁保护，已进入调用正常清理，关闭后不再调用 JNI。它不模拟真实 JVM 堆耗尽，也不穷举系统退出时序。它不启动 Godot/JVM、不需要交互输入；屏幕上的预览渲染与跨进程封送仍由 Robot 夹具验证。

应用内两种模式不覆盖 Windows 桌面/其他进程拖入拖出；跨进程夹具通过 `DragImageBits` 证明 OLE 拖出段的拖放预览图已注册，但不像素级检查屏幕上的预览渲染，也不覆盖指针仍在宿主窗口内的本地段预览（当前不绘制）或真实鼠标硬件。这些仍属于拖放收尾范围，不能用单侧 PASS 代替。

## Robot 桌面专项

```powershell
.\scripts\test-robot.ps1 -Driver d3d12
.\scripts\test-robot.ps1 -Driver opengl
.\scripts\test-robot.ps1 -Driver d3d12 -Runtime
```

前置：G+J，Runtime 模式额外准备 Runtime。必须是已解锁的交互桌面；测试使用置顶窗口并移动系统鼠标，期间不要操作其他窗口。它使用真实 Windows 输入合成，不是 Godot 注入，不修改剪贴板。测试结束释放按键/鼠标按钮并恢复原鼠标位置。可选参数：`-Jdk`、`-Driver`、`-RenderThread`、`-Runtime`。

测试验证 Shift+A 输入、Enter 提交后保持 A、Escape 关闭可能遮挡按钮的 IME 候选界面、按钮点击、滚轮方向、鼠标坐标、桌面像素、HiDPI 下缩放/原生尺寸截图、目标图像复用、100 次重复截图、非法参数拒绝以及 FX 线程约束。验收要求 `ROBOT_PROBE_PASS` 和 `GODOT_ROBOT_PASS`，无错误；查看 `artifacts/reference/robot-desktop.png`，应有 A、按钮、蓝色方块。日志为 `robot-<driver>-<thread>[-runtime].log`。

Windows 可能拒绝后台进程抢前台，`Stage.isFocused()` 单独不能证明系统输入会送给测试窗口。测试在输入前检查桌面色块；候选界面遮挡、其他置顶窗口或锁屏可能导致失败，不能改用宿主注入来冒充通过。当前记录为单屏 2× DPI，不代表混合 DPI、真实键盘/触摸或全部 IME 行为通过。

macOS 入口为 `./scripts/test-robot.sh [--driver metal|opengl]`（小写长选项），双渲染器均已通过。macOS 侧鼠标移动经真实 CGEvent 投递（Glass MacRobot），按 `com.apple.swipescrolldirection` 补偿自然滚动，目标坐标钳制到显示器边界；按键只用静态 US QWERTY 表以避免非主线程 TSM 调用。需要终端具备辅助功能与屏幕录制权限；本机验证时 scale=1，HiDPI（2x）下的截图/坐标路径未验证。

## Windows 原生文件对话框专项

```powershell
.\scripts\test-file-dialog.ps1 -Driver d3d12
.\scripts\test-file-dialog.ps1 -Driver opengl
.\scripts\test-file-dialog.ps1 -Driver d3d12 -Runtime
.\scripts\test-file-dialog.ps1 -Driver d3d12 -StopHost
```

两种场景档均需要 G+J 和可显示系统对话框的 Windows 交互桌面。可选参数：`-Jdk`、`-Driver`、`-RenderThread`、`-Runtime`、`-StopHost`。串行运行，不要手动关闭或操作测试对话框。

常规模式验证单选、多选、保存路径、目录选择、无 owner 取消和关闭 owner 后取消。检查扩展名过滤器对象、打开期间 Pulse 继续、原生窗口所属关系、整个 owner 链禁用及恢复、最终资源清零。脚本在 `artifacts/reference/dialog-fixtures` 创建 a.txt/b.txt 测试文件；保存用例只选择 chosen.new 路径，不写入该文件，该路径应不存在。

原生驱动仅操作带本轮随机标题且属于测试进程的 Windows 对话框，通过按钮通知确认或取消；这不代表物理鼠标验收。StopHost 模式先确认原生对话框出现，再停止宿主，要求取消返回和资源清理完成。必须同时获得 `FILE_DIALOG_PROBE_PASS`、`FILE_DIALOG_NATIVE_PASS`、`GODOT_FILE_DIALOG_PASS`，StopHost 还要求 `FILE_DIALOG_HOST_STOP_RETURNED`；进程正常退出且无异常或 ERROR。日志为 `file-dialog-<driver>-<thread>[-runtime][-stop].log`，以及 `.native` 和 `.stderr` 附属文件。

当前只允许同时存在一个文件/目录选择器，重入调用会明确抛出异常；此测试不证明并发选择器、所有 Shell 扩展或物理输入兼容性。

macOS 等价入口为 `sh scripts/test-file-dialog.sh`（`--driver`、`--render-thread`、`--stop-host`）。真实面板需要辅助功能权限和真实键盘输入，因此该脚本启用模块测试钩子（`GODOT_JFX_DIALOG_HOOK=1`），由宿主按同一 submit/poll/cancel 契约确定性地应答；FileDialogProbe 的 Java 断言（结果路径、过滤器身份、取消语义、模态期间 FX 循环存活）不变，判定要求 `FILE_DIALOG_PROBE_PASS`、`GODOT_FILE_DIALOG_PASS`，`--stop-host` 另要求 `FILE_DIALOG_HOST_STOP_RETURNED`。它不验证面板外观、sheet 归属或物理键盘操作，也没有 Windows 原生驱动对对话框窗口类和 owner 链的断言。

## 如何判定通过

剪贴板交换通过同步文件协调原生对端与 JavaFX 的读写时序，按双方实际读取的格式和内容判定。

`test-clipboard-ownership.cmd` 包含原生格式枚举错误门禁：用模拟 Win32 调用覆盖
首项失败、中途失败、成功结果伴随无关旧错误码，以及正常空列表/结束。
要求 `CLIPBOARD_ENUMERATION_FAILURE_PASS` 和既有所有权标记；不操作系统剪贴板。
生产 JNI 路径遇到枚举错误应抛出 IllegalStateException，不返回部分自定义格式列表。

`test-clipboard-snapshot-guard.ps1` 还要求枚举失败保护：模拟空列表、完整列表、
首项失败和部分列表后失败，后两者必须拒绝返回快照；检查 P/Invoke 保留错误码。
标记为 `CLIPBOARD_SNAPSHOT_ENUMERATION_FAILURE_PASS`。此测试通过委托注入，
不访问或改写真实剪贴板，也不等同端到端互操作验收。

`test-render-targets.ps1` 在既有 100 轮复制/透明度/资源检查之前，增加 128 次
Viewport 目标提交后立即释放，检查 safe 模式下绘制和资源销毁顺序。
即使最终有 PASS，日志中的失效对象回调 ERROR 仍判失败。此检查不使用真实键鼠。

着色器缓存用例还会让两个离屏目标用同一段代码绘制不同颜色，读回各自的像素，检查实际只创建一个共享程序。释放首个目标后，第二个目标须能继续正确绘制；最后一个目标释放后，共享程序数应回到测试前的值。Linux 的入口为 `scripts/test-shader-cache.sh --driver vulkan|opengl`。

`test-shader-cache.ps1` 还要求 `SAMPLER_MATERIAL_COLLISION_PASS`：夹具创建 96 个
真实纹理目标，在有界的三采样器组合中寻找实际 Dictionary 哈希碰撞，然后验证
同一 pass 内左右区域的不同颜色、连续三轮复用后仍恰好两份材质。找不到碰撞
视为夹具失败，不跳过断言；不通过修改生产 hash 强制制造碰撞。原来的 305 轮
着色器/缓存压力检查继续执行，像素失败会输出实际左右颜色。
压力段读取像素前等待三轮新的 `frame_pre_draw` 和随后到达的 `frame_post_draw`，
最终同步读回取得已提交绘制的结果。
Surface、生成 Shader、RenderTarget、网格变换的
像素夹具也使用这一等待顺序，保持各自原有轮数及像素阈值。这不是 GPU 计时方法，
也不能据此把 `frame_post_draw` 的送达时刻当成物理显示完成时刻。

碰撞夹具还销毁只被第一组引用的纹理，确认对象确已释放，再连续两轮绘制另一组；
颜色必须保持一致、缓存必须仅剩一份材质，覆盖主哈希位置被删除后的查找与复用。

压力段像素失败时，还会保存**同一次读回**的图片到
`artifacts/reference/shader-cache-failure-<PID>-cycle-<轮数>.png`，并输出保存结果。
不会为了截图重新渲染、重读或重试像素判定；保存失败也不改变原测试失败结果。

Media churn 检查 Viewport 材质缓存是否释放已销毁的视频纹理，并校验暖机后的资源上限。

Java 调用、宿主 tick 和清理均通过也不能证明系统键盘已显示或关闭。脚本输出原生 touch keyboard 警告。

审查修复专项（不操作真实键鼠，也不读写剪贴板）：

```powershell
.\scripts\test-render-command-validation.ps1
.\scripts\test-image-pool-reuse.ps1
.\scripts\test-drag-drop-ole-inject.ps1 -Timeout
```

编码器专项前置 J，不启动窗口或 JVM 宿主；重复非法 NaN/Z/溢出变换必须拒绝且不修改帧，之后有效几何必须先注册再引用；还验证调用方数组修改、确定性哈希槽碰撞、1024 条目和 32 MiB 数据上限、闲置释放后重新接纳几何（测试通过反射隔离编码逻辑，不证明 GPU 生命周期），要求 `RENDER_COMMAND_VALIDATION_PASS`。OLE `-Timeout` 前置 G+J，使用已有模块注入入口；阻塞 FX 线程让 Enter/Drop 过期，恢复后不得收到过期事件，随后正常拖放必须仍能通过，额外要求 `OLE_TIMEOUT_CANCEL_PASS`。日志为 `ole-inject-<driver>-<thread>-timeout.log`。这不证明已开始执行的用户事件处理器可被撤销，也不替代真实 OLE 手势验收。

图片池专项前置 J；使用内存中的测试图片和 Renderer，不启动图形设备、不依赖 GC 时机。脚本分别运行 FIFO/LIFO，验证空引用、丢失图片及连续失效条目之后的可用图片仍被复用，并保持相同尺寸图片的选择顺序；还强制先检查失效候选，验证其锁归零、有效图像 checkout/checkIn 锁配对及再次复用；要求不发生额外分配且两次均有 `IMAGE_POOL_REUSE_PASS`。日志 `image-pool-reuse-0.log`（FIFO）、`image-pool-reuse-1.log`（LIFO），支持 `-Jdk`，运行后恢复原 `GODOT_JFX_IMAGE_POOL_LIFO`。

- 以脚本正常返回、对应观察器/宿主完成标记和脚本内断言共同判定。大部分脚本拒绝 ERROR、异常和缺失样本。故障注入测试会特许指定的预期错误，并要求故障后的退出/唤醒证据。
- 主要日志在 `agentdir/logs`，图片/JSON 在 `artifacts/reference`，Runtime 临时项目在 `artifacts/runtime-*`。以脚本最终打印的路径为准；同参数重跑可能覆盖旧日志，做前后对比前先保存旧证据。
- 像素测试应查看实际图像，尤其首次修改渲染路径时。原生 D3D 对照只证明参考后端结果，不是 Godot 通过。随机数据、时间和动画会造成 VFX 图像差异，不能只凭差异率下结论。
- `final_owned=0` 等宿主计数不等于整个进程绝无泄漏。压力测试同时看 Java 堆、自然 GC、进程 private bytes/handles、GPU 计数及时间趋势；不要通过强制 GC 或放宽阈值掩盖问题。
- 性能区分 Pulse、绘制、合成和物理扫描输出；平均 FPS 之外还看 P95/P99、最大帧间隔、背压与焦点丢失。当前物理音画同步未验收。

## 建议的起始回归

已完成构建后，可按下面顺序验证主路径；它不是每次修改都必须全跑的硬性清单：

```powershell
.\scripts\test-protocol.cmd
.\scripts\test-native-stage.ps1 -Driver d3d12
.\scripts\test-effects.ps1 -Driver d3d12
.\scripts\test-godot-view.ps1 -Driver d3d12 -Transform
.\scripts\test-media-planes.ps1 -Driver d3d12
.\scripts\test-media-video.ps1
.\scripts\test-media-churn.ps1 -Cycles 24 -Providers
.\scripts\test-vfx-intro.ps1 -Driver d3d12 -AllPages
```

改动窗口/输入优先查窗口组，改动纹理/着色器优先查 GPU 组，改动 Media 生命周期要跑 churn；只改文档无需重跑整个 GUI 测试集。

## 测试目录

每行说明的是该测试的断言用途；详细用例和阈值仍以对应脚本及它启动的 `tests/reference`、`tests/godot` 探针为准。

### 底层协议、调度与生命周期

`.\scripts\test-clipboard-ownership.cmd` 使用 MSVC、Windows SDK 和默认 JDK 头文件，以 `/W4 /WX` 编译独立原生测试。它分配私有 HGLOBAL 内存，在持有资源时主动抛出分配异常，检查未发布块释放、已转交块保留、借用块解锁且不被释放；另检查 DIB 图片的正/负高度、24 位行补齐、截断尾行、超大宽度/头部、LONG_MIN、可选颜色表的像素起点及截断/超大颜色表；文件列表扫描覆盖 ANSI/UTF-16、奇数字节偏移、缺少列表终止符、截断路径、数量/长度限制和空列表；要求 `CLIPBOARD_OWNERSHIP_PASS` 和退出码 0。不打开或修改系统剪贴板，不需要备份用户内容；不替代真实剪贴板格式互操作测试，也不证明整个 JNI 调用的内存不足行为。

| 启动命令 | 用途 / 特殊前置条件 | 验收方式 | 可选公共参数 |
| --- | --- | --- | --- |
| `.\scripts\test-protocol.cmd` | 批次解码、资源事务、队列背压与并发。前置：MSVC/Windows SDK；无需启动 JVM/GPU。 | 原生断言及 FRAME_PROTOCOL_PASS，包含 10000 并发帧；输入时钟与帧/队列时钟隔离、输入 tick 合并、超时不产生 tick、stop/finish 后输入等待返回终止状态。 | 无 |
| `.\scripts\test-m1.ps1 -Driver d3d12` | Godot 自定义模块基础绘制与资源。前置：G；无 Java 探针。 | GPU 像素、清空命令后保留可复用几何、退出场景树后资源和几何缓存归零（含 100 次创建/销毁），以及 M1 完成标记。 | `-Driver` |
| `.\scripts\test-bridge.ps1 -Driver d3d12` | JVM/JNI、批量命令和纹理通路。前置：G+J；各模式分开运行。 | 检查宿主没有注册旧的 JVM 创建方法，再运行 Java 与宿主双侧断言；Encoded 模式必须实际观察到背压。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-glass-scheduler.ps1` | Glass 事件线程、队列与调度。前置：G+J。 | 线程/执行顺序等探针断言及双侧 PASS；Glass 退出后保持宿主运行，检查输入和帧接收线程均在 2.5 秒内结束，并检查运行时拖入回调已注册、退出后静态引用已解除。独立队列取消夹具在异常路径也停止循环、释放闩锁并等待测试线程退出。 | `-Jdk` |
| `.\scripts\test-glass-window.ps1` | Glass 基础窗口适配。前置：G+J。 | 窗口状态和宿主/Java 完成断言。 | `-Jdk`、`-Runtime` |
| `.\scripts\test-pulse-stop.ps1` | Pulse 停止竞争与关闭后的通知。前置：J；脚本在 artifacts 编译模块补丁。 | 停止语义的 Java 断言；不是 GPU 测试。 | `-Jdk` |
| `.\scripts\test-timer-cadence.ps1` | 定时器节奏与时间计算。前置：J。 | Java 时序断言；不是显示 FPS 测试。 | `-Jdk` |
| `.\scripts\test-host-stop.ps1 -Driver d3d12` | 宿主主动停止时窗口、渲染任务和等待者清理。前置：G+J。 | 窗口 peer 关闭、Application 返回、pipeline pool_bytes=0，无未处理异常。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-host-lifetime.ps1 -Driver d3d12` | 宿主节点与 Java 探针的生命周期。前置：G+J。 | 生命周期及释放断言、双侧 PASS。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-failure-shutdown.ps1 -Driver d3d12` | 注入异常后退出、嵌套事件循环解锁。前置：G+J；预期故障测试。 | 必须观察指定异常和内外层循环返回；脚本排除非预期错误。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-render-thread-shutdown.ps1` | Godot 渲染线程停止和退出。前置：G；可测试 Runtime。 | 脚本逐个运行线程模式，检查退出状态和日志。 | `-Runtime` |
| `.\scripts\test-input-cancel.ps1 -Driver d3d12` | 失焦时取消按键、按钮、触摸保持状态。前置：G+J；按独立原生窗口 ID 和 DPI 缩放后的局部坐标注入，等待焦点就绪。首轮失焦后故意不补发原窗口鼠标释放，检查焦点返回时移动不带旧按钮位；仅在按下前注入定位移动，松开前不额外注入拖动；不操作真实鼠标/键盘。 | 取消/释放事件、无意外拖动、后续点击仍可激活及资源释放断言。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-input-lifecycle.ps1 -Driver d3d12` | 输入对象与窗口生命周期交错。前置：G+J；隐藏/关闭后重建原生 peer，迟到释放送至主窗口，随后恢复手势。 | 事件/lifecycle 断言及双侧 PASS。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-texture-cancellation.ps1` | 宿主已停止时纹理销毁的 Java 账本清理。前置：J；编译 GodotTexture 模块补丁。 | 取消路径不破坏资源池清理的断言。 | `-Jdk` |

### 窗口、屏幕与输入

| 启动命令 | 用途 / 特殊前置条件 | 验收方式 | 可选公共参数 |
| --- | --- | --- | --- |
| `.\scripts\test-native-windows.ps1 -Driver d3d12` | 直接验证 Godot 原生窗口管理。前置：G。 | 创建、属性、所有者及生命周期等宿主断言。 | `-Driver`、`-RenderThread` |
| `.\scripts\test-native-window-bridge.ps1 -Driver d3d12` | JNI 原生窗口请求与状态快照。前置：G+J。 | Java/宿主请求、确认和生命周期断言。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-native-window-pixels.ps1 -Driver d3d12` | 多原生窗口的 GPU 内容。前置：G+J。 | 各窗口像素与资源释放断言。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-native-stage.ps1 -Driver d3d12` | 标准 JavaFX Stage 映射独立原生窗口。前置：G+J。 | 窗口独立性、显示及生命周期断言。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-native-stage-input.ps1 -Driver d3d12` | 窗口身份与重叠 Stage 输入路由。前置：G+J。 | 输入应到达正确 Stage；注入事件，不是物理设备验收。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-native-ime.ps1 -Driver d3d12` | 多个原生窗口的输入法状态隔离；会移动真实光标，须获授权。前置：G+J。 | 组合/提交/取消等注入断言；不证明候选窗口真实位置。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-native-order.ps1 -Driver d3d12` | 原生窗口顺序、所有者和前后关系。前置：G+J。 | 顺序与状态断言，无异常。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-native-exit.ps1 -Driver d3d12` | 重复创建原生窗口后退出。前置：G；12 轮。 | 必须记录 12 个周期及 NATIVE_EXIT_PASS。 | `-Driver`、`-RenderThread` |
| `.\scripts\test-native-churn.ps1 -Driver d3d12` | 隔离 Godot Window/SubViewport 的资源增长。前置：G；Kind 可选 Idle/SubViewport/Window/JavaFXNativeWindow。 | 181 个样本及完成标记；仅传入非负 StaticRangeLimitBytes 才启用静态内存范围门槛。 | `-Driver`、`-RenderThread` |
| `.\scripts\test-stage.ps1 -Driver d3d12` | 普通 Stage/Scene 基础绘图。前置：G+J。 | 画面像素、单窗口基础路径及释放断言。 | `-Jdk`、`-Driver` |
| `.\scripts\test-stage-churn.ps1 -Driver d3d12` | 重复创建销毁 JavaFX Stage。前置：G+J；Cycles 6–1000，HeapMiB 可限 Java 堆。 | Java 周期样本为 Cycles，原生为 Cycles+1；资源/退出断言；无强制 GC。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-transparent-stage.ps1 -Driver d3d12` | 透明 Scene/Stage 的空白区与边缘 alpha。前置：G+J；宿主项目允许逐像素透明。 | GPU alpha 和清理断言；不验收用户放弃的白线。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-render-scale.ps1 -Driver d3d12` | 逻辑尺寸与像素尺寸、渲染缩放。前置：G+J。 | 缩放后布局/像素断言；不代替跨真实显示器移动。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-screens.ps1 -Driver d3d12` | 从宿主枚举屏幕到 JavaFX。前置：G+J。 | 核对屏幕快照、坐标和工作区。超时会记录子窗口的实际及期望坐标、屏幕关联和观察器标题；FX 线程无响应时单独报告。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-screen-layout.ps1` | 屏幕布局计算。前置：J。 | 纯 Java 布局边界断言；不要求真实多显示器。 | `-Jdk` |
| `.\scripts\test-ime.ps1 -Driver d3d12` | 输入法组合文本基础桥接。前置：G+J。 | 合成文本、提交/取消等注入断言。 | `-Jdk`、`-Driver` |
| `.\scripts\test-image-cursor.ps1 -Driver d3d12` | 自定义图像光标与热点。前置：G+J。 | 图像/热点/生命周期断言；`CURSOR_RESTORE_ONCE_PASS` 检查退出后应用新设光标不被宿主析构覆盖。使用合成输入，不移动真实鼠标；不等于所有桌面外观已人工确认。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-resize-cursor.ps1` | JavaFX 光标形状命令与宿主 OS 光标、Viewport 默认光标的同步（resize 把手悬停不还原成箭头）。前置：G+J。 | 按实际窗口尺寸换算 400×300 逻辑场景坐标；悬停/离开的光标形状断言及双侧 PASS。Godot 合成输入，不移动真实鼠标。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-window-drag.ps1` | 标题栏拖拽窗口跟随滞后（输入唤醒 + frame_pre_draw 第二应用点）。前置：G+J。完全合成输入；探针只读光标位置并把测试窗口放到避开光标的屏幕另一侧，不移动鼠标。 | 每步最多等待 40 帧，最终位置误差不超过 3 像素；DRAG_LAG_AVG/MAX 为测量值，没有额外低延迟门槛。双侧 PASS、资源归零，脚本创建输出目录并恢复 JDK 环境变量。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-scroll-wheel.ps1` | 滚轮速率契约：Windows 宿主读取系统 SPI_GETWHEELSCROLLLINES/CHARS，Java 侧按 40px/行换算，与原生 Win Glass 一致；macOS 宿主上报 kind-17 滚动记录（滚轮行 delta / 触控板 pan 点 delta），Java 侧按原生 MacGestureSupport 的 10px 倍率换算，与原生 Mac Glass 一致。前置：G+J。 | 逐事件换算校验，第三次事件分发完成后按三个 delta 累加并限制到可滚动范围，位移误差 ≤0.01 px；要求完整 SCROLL_RESULT、双侧 PASS 且无脚本/Shader 错误。不修改系统滚轮设置。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-physical-drag.ps1` | 按下后指针快速逃出窗口的 press-drag-release 连续性（宿主重放按住按钮位、按住期间抑制进出事件）。前置：G+J。默认合成模式：GDScript 按探针标题指令注入按下/移动/释放（坐标冲出窗口边界，等价于光标逃出），不移动真实鼠标、不需要前台；断言拖动/缩放精确跟随路径和（合成坐标无 OS 屏幕钳制）且无中断手势的无按键 MOUSE_MOVED。加 `-Robot` 走 Glass Robot 物理档（需桌面空闲、窗口前台）：覆盖合成无法到达的 OS 投递语义（光标屏幕边缘钳制、WM 进出通知抑制），期望按钳制后的实际光标位置推导。双侧 PASS。 | PHYS_DRAG/PHYS_RESIZE 事件计数与跟随断言、PHYS_TRACE 无 gesture-killer；FX 调用异常传回驱动线程，超时/中断取消尚未执行的任务，关闭后等待驱动线程停止；带按键 MOUSE_EXITED 是 Quantum 拾取变化的标准合成（原生同款），不算中断。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Robot` |
| `.\scripts\test-window-icon.ps1 -Driver d3d12` | Stage 图标设置、替换和清除。前置：G+J。 | 原生图标像素、透明度、窗口独立性及释放断言。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-clipboard.ps1 -Driver d3d12` | 文本、HTML、RTF、Unicode URL、文件列表(CF_HDROP)、图片(CF_DIB)、ANSI-only URL 回退与自定义格式(application/x-godot-custom-*)的系统剪贴板互通。前置：G+J；见剪贴板特别说明。 | Java 与原生对端的格式、内容断言均通过，宿主正常退出。 | `-Jdk`、`-Driver`、`-Runtime` |
| `.\scripts\test-virtual-keyboard.ps1 -Robot` | 虚拟键盘 `_requestInput`/`_releaseInput` 到 Windows 触摸键盘(TabTip)的调用链路，正常运行会请求系统键盘。前置：G+J；`-CompileOnly` 只需 J，编译后退出，不调用系统键盘。 | Java 调用不抛异常、宿主 tick 必须实际前进、等待 FX 清理完成后输出 `VIRTUAL_KEYBOARD_PASS`；超时/中断取消尚未运行的任务，退出尝试释放输入请求并关闭 Stage，宿主移除后资源归零。原生失败记首次 WARNING；PASS 不证明 OS 调用成功或键盘可见/关闭，须另行设备验收。后续系统链路已运行，关闭请求出现拒绝访问 HRESULT；详见上文记录，不能以 Java PASS 证明键盘实际关闭。 | `-Jdk`、`-CompileOnly` |
| `.\scripts\test-popups.ps1 -Driver d3d12` | 弹出控件的基本显示与交互。前置：G+J。 | Popup 内容、交互和生命周期断言。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-popup-bounds.ps1 -Driver d3d12` | Popup 屏幕边界约束。前置：G+J。 | 按已绘制的帧核对八步几何和像素。最后一次关闭后按主循环检查窗口、合成和资源清理。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-popup-edge.ps1 -Driver d3d12` | 靠近边缘时 Popup 定位与自动修正。前置：G+J。 | 边缘放置和 autoFix 相关断言。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-nested-menu.ps1 -Driver d3d12` | 嵌套菜单与事件循环。前置：G+J。 | 校验子菜单的独立窗口、实际绘制、选择和点击外部关闭。最后一次关闭后按逻辑帧检查宿主退出和窗口、资源清理。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-modals.ps1 -Driver d3d12` | 窗口模态、所有者和交互阻止。前置：G+J。 | 应被阻止/允许的输入与模态释放断言。 | `-Jdk`、`-Driver`、`-RenderThread` |

### 历史窗口与底层合成诊断

| 启动命令 | 用途 / 特殊前置条件 | 验收方式 | 可选公共参数 |
| --- | --- | --- | --- |
| `.\scripts\test-logical-windows.ps1 -Driver d3d12` | 主窗与次级原生 Stage 的独立画面、按窗口寻址输入、位置及透明度。前置：G+J。 | 验证两个窗口的 GPU 像素、动作计数、隐藏与重显及清理。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-window-layers.ps1 -Driver d3d12` | 原生窗口层绘制基础。前置：G；底层诊断。 | 图层像素/顺序及清理断言。 | `-Driver`、`-RenderThread` |
| `.\scripts\test-window-commands.ps1 -Driver d3d12` | 窗口相关批次命令。前置：G+J；底层诊断。 | 编码和宿主消费结果断言。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-window-composition.ps1 -Driver d3d12` | 独立原生窗口接收 Prism Presentable。前置：G+J。 | 合成内容、保留/释放等断言。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-window-lifecycle.ps1 -Driver d3d12` | 窗口发布、隐藏和销毁。前置：G+J；历史/底层覆盖。 | 生命周期与清理断言。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-window-order.ps1 -Driver d3d12` | 重叠的独立 Stage 的系统层序及顶层窗口像素。前置：G+J。 | 逐阶段验证十次原生窗口层序和顶层颜色，并核对资源清理。新窗口首帧若仍为项目清屏色，最多等待一秒。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-window-resize.ps1 -Driver d3d12` | 发布目标随窗口尺寸变化。前置：G+J；底层覆盖。 | 连续 resize 的画面/资源断言。 | `-Jdk`、`-Driver`、`-RenderThread` |

### GPU 绘制、Shader、Effect 与嵌入场景

| 启动命令 | 用途 / 特殊前置条件 | 验收方式 | 可选公共参数 |
| --- | --- | --- | --- |
| `.\scripts\test-shaders.ps1 -Driver d3d12` | 生成 Shader 的完整性与 Godot 解析。前置：G+J；需要 JFX 构建生成资源。 | 与 D3D 变体集合及 SDK 内容一致；全部解析，部分像素检查，退出场景树后资源及几何缓存归零。 | `-Driver` |
| `.\scripts\test-shader-state.ps1` | Java Shader 描述符、常量与快照。前置：J。 | ShaderStateProbe 断言；不证明所有 GPU shader 编译成功。 | `-Jdk` |
| `.\scripts\test-shader-source-cache.ps1` | Shader 源码编码缓存。前置：J。 | 缓存命中/边界等 Java 断言。 | `-Jdk` |
| `test-render-command-validation.sh` / `.ps1` | 从项目 Maven Local 加载发行模块，在两个独立 JVM 中分别关闭和开启 shader 状态去重。使用 JDK 25。 | 检查相同常量的编码字节数，并验证哈希碰撞、常量类型、采样纹理更新、目标切换及多个编码器。两次结果分别写入 `agentdir/logs/shader-state-suppression-{0,1}.log`。 | `--jdk` / `-Jdk` |
| `.\scripts\test-texture-lookup.ps1 -Driver d3d12` | Godot 纹理查询/生命周期诊断。前置：G。 | TEXTURE_LOOKUP_PASS 及无非预期错误。 | `-Driver`、`-RenderThread` |
| `.\scripts\test-render-targets.ps1 -Driver d3d12` | 离屏渲染目标、采样和释放。前置：G。 | GPU 颜色/复制及生命周期断言。 | `-Driver`、`-RenderThread` |
| `.\scripts\test-mesh-transform.ps1 -Driver d3d12` | QUADS 局部顶点随变换命令绘制（离屏 pass 与 surface 共享命令项两条路径，含变换复位）。前置：G；无 Java 探针。 | MESH_TRANSFORM_PROBE_PASS 与像素边界断言。 | `-Driver` |
| `.\scripts\test-blit.ps1 -Driver d3d12` | GPU 目标间复制。前置：G+J。 | 复制区域和目标像素断言。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-composite.ps1 -Driver d3d12` | 透明度与合成模式。前置：G+J。 | 对照合成公式的颜色/alpha 及清理断言。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-composite-edges.ps1 -Driver d3d12` | 抗锯齿/像素边缘合成对照。前置：G+J；会先运行原生 D3D。 | 20 组布局一致、每个像素在脚本容差内。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-effects.ps1 -Driver d3d12` | JavaFX Effect 与原生输出对照。前置：G+J；先运行 D3D 参考。 | 效果集合、图像容差和宿主完成断言。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-readback.ps1 -Driver d3d12` | 显式 GPU 读回、snapshot 与停止。前置：G+J；特殊模式见下文。 | 像素、buffer、snapshot 或中断路径对应断言。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-node-shaders.ps1 -Driver d3d12` | 指定 Node/子树的 Godot Shader。前置：G+J。 | uniform、裁剪、透明度、子树隔离及 GPU 像素断言。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-scene-views.ps1 -Driver d3d12` | Godot SubViewport 场景原生基础。前置：G。 | 场景渲染、混合和生命周期断言。 | `-Driver` |
| `.\scripts\test-scene-textures.ps1 -Driver d3d12` | 场景纹理命令、resize 和加载失败。前置：G+J；MissingScene 是预期故障模式。 | 正常像素/身份保持；等待只统计实际推进的 host tick，每段 10 秒总期限；故障模式要求明确失败传播标记。 | `-Jdk`、`-Driver`、`-Resize`、`-MissingScene` |
| `.\scripts\test-hover-flicker.ps1 -Driver d3d12` | Viewport 呈现侧悬停回归。前置：G+J+V（探针使用 FusionButton）。默认合成模式：GDScript 按探针标题注入 motion 事件（HOLD 停按钮中心、GAP 移出窗口），不动真实鼠标、不需要置顶；加 `-Robot` 走 Glass Robot 物理档（真实 OS 光标停留在按钮，需桌面空闲、窗口置顶，运行期间勿操作鼠标）。 | 逐帧采样画面，普通按钮悬停色缺失帧 >5% 失败；FusionButton 要求六轮 HOLD/GAP 各有越过 23 帧过渡期的样本，稳定期亮/暗错误比例 >5% 失败。按当前屏幕缩放映射坐标；120 秒宿主期限、Java 侧每次 FX 调用 10 秒超时；FX 异常向主线程传播，退出时停止动画、尝试恢复 Robot 原光标位置并关闭窗口，清理成功后才输出 Java PASS；宿主节点移除后资源必须为零，要求 HOVER_RESOURCE_CLEANUP_PASS。JVM 失败和日志 ERROR/SHADER ERROR 均失败，要求 HOVER_FUSION_PIXEL_PASS。批量提交期呈现竞态（悬停闪回/拖动顿挫同类）回归门。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Robot` |
| `.\scripts\repro-hover-manual.ps1` | 带 HOVER_TAP/HOVER_SAMPLE 启动 VFX，用户操作并关窗后汇总；前置 G+J+V。`-LogPath` 只分析已有日志，无窗口/构建依赖。 | 诊断入口，无功能 PASS；恒定亮度可能是静态内容，时间相近也不能单独证明因果。原生非零退出或错误日志明确失败。 | `-Jdk`、`-Driver`、`-RenderThread`、`-NoSample`、`-LogPath` |
| `.\scripts\test-godot-view.ps1 -Driver d3d12` | JavaFX GodotView 布局、场景与输入。前置：G+J；Transform 模式另跑 D3D 参考。 | 场景像素、透明度/裁剪、输入坐标和资源释放断言。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-fxml.ps1 -Driver d3d12` | FXML 加载与标准控件集成。前置：G+J；FXML 资源由脚本安排。 | 控制器、include、资源、输入、多窗口及画面断言。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |

### Media

| 启动命令 | 用途 / 特殊前置条件 | 验收方式 | 可选公共参数 |
| --- | --- | --- | --- |
| `.\scripts\test-media-planes.ps1 -Driver d3d12` | YUV/R8、alpha、stride、padding 与 packed 上传。前置：G+J；合成帧，不需真实 MP4。 | GPU 色值、透明度、可见边界和 hold/release 断言。 | `-Jdk`、`-Driver` |
| `.\scripts\test-media-audio.ps1 -Driver d3d12` | 音频播放控制。前置：G+J+M；WAV 由 Python 生成两秒静音，`-Codec mp3/aiff/all` 改用 MSVC 编译的 `tests/native/make_audio_fixture.cpp` 本地编码 2 秒 440 Hz 样本（MP3 走 Media Foundation，AIFF 为手写容器）。 | 有限元数据时长(±容差，MP3 允许编码器 padding)、AudioTrack、暂停、有限播放时钟、seek、结束与销毁；回调/清理异常导致失败，AIFF 写入及关闭错误不输出生成 PASS。全程静音，不证明实际听感。 | `-Jdk`、`-Driver`、`-Runtime`、`-Codec` |
| `.\scripts\test-media-video.ps1 -Driver d3d12` | 真实 MP4 播放和 MediaView 控制。前置：G+J+M，运行 `python scripts/setup-env.py` 准备样本。默认使用 Oracle，另可选用 1080p 无音轨的 Lk。 | 画面、暂停/seek/EOS/stop/replay、逐像素缩放、裁剪、半透明与清理断言。 | `-Jdk`、`-Driver`、`-Runtime`、`-NativeD3D`、`-Sample oracle\|lk` |
| `.\scripts\test-media-churn.ps1 -Driver d3d12` | 循环创建/销毁播放器和视频纹理。前置：G+J+M；先准备 MP4，或 AudioOnly 自动生成 PCM。 | 样本数、播放和清理检查；Providers 增加 AAC 稳定断言，进程内存另做趋势分析。 | `-Jdk`、`-Driver`、`-Runtime` |

### VFX 真实 Demo

| 启动命令 | 用途 / 特殊前置条件 | 验收方式 | 可选公共参数 |
| --- | --- | --- | --- |
| `.\scripts\test-vfx-intro.ps1 -Driver d3d12` | 真实 Demo 启动、导航和页面截图。前置：G+J+V。 | 导航/画面观察器与宿主完成；AllPages 产出页面 manifest，截图还需审查。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-vfx-dialog.ps1 -Driver d3d12` | 真实 Demo 对话框及故障退出。前置：G+J+V；InjectFailure 为预期异常。 | 普通交互/清理断言，或指定故障和退出路径通过。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-vfx-stage.ps1 -Driver d3d12` | 真实 Demo 的 Stage 与退出。前置：G+J+V；Abrupt 检查提前退出。 | 窗口行为或突然退出的专用标记，无意外异常。 | `-Jdk`、`-Driver`、`-RenderThread` |
| `.\scripts\test-vfx-window-controls.ps1 -Driver d3d12` | Demo 窗口按钮、尺寸与状态。前置：G+J+V。 | 点击原始按钮后核对原生窗口状态、最大化边界、还原后的原始位置和尺寸，以及关闭后的资源清理。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-vfx-table.ps1 -Driver d3d12` | Demo 表格添加、选择与文本编辑。前置：G+J+V。 | 行数、编辑内容、焦点及画面相关断言。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-vfx-table-scroll.ps1 -Driver d3d12` | 大表格页（50 行×7 列）拖拽滚动性能夹具：空闲窗口 + 默认 96 脉冲锯齿拖动；`-Sweeps 3..30` 每次往返方向段包含 32 脉冲，最多 960，保留全部帧间隔。默认直接驱动视口自身的 DragHandler（不用 OS 输入）；`GODOT_JFX_DRAG_MODE=real` 走完整合成输入管线（`GODOT_JFX_REAL_EVENTS`/帧 可调），`=robot` 用 Glass Robot 移动物理光标（需窗口前台，仅诊断用）。前置：G+J+V。 | `VFX_TABLE_SCROLL(_IDLE)` 排序后帧间隔分位数（GAPS_MS 保留采样时间顺序）；可选 GODOT_JFX_STACK_SAMPLE 必须为正整数毫秒，启用时只作诊断；位移断言（≥200px）、`VFX_TABLE_SCROLL(_IDLE)_STATS` 宿主计数（离屏 pass/encode/presentations/quads 命中，`-Profile` 时含命令级分解）、资源清零。空闲/拖动分别报告 measured_ticks 与 unfocused_ticks；GROWTH 每 8 个拖动 tick 采样并包含首尾。lifetime_max_* 为进程累计最大值，不是区间差值。旧版 unfocused_ticks 只计空闲阶段，不能证明拖动阶段后台运行；robot 模式仍须前台，退出/失败时尝试释放按钮并恢复光标；执行前须获得用户许可，并保持桌面空闲；已有授权仅适用于相应会话，其他会话需确认授权仍有效。GODOT_JFX_DRAG_AXIS=h 选择水平可滚动视口，direct/real 均沿 X 轴驱动；默认纵向。两轴都要求所选轴累计位移 ≥200px。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Profile`、`-Sweeps` |
| `.\scripts\test-vfx-scroll.ps1 -Driver d3d12` | Demo 横向拖动和表格滚动。前置：G+J+V。 | 滚动位置、几何、像素变化和恢复断言。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-vfx-loading.ps1 -Driver d3d12` | Demo 后台加载、完成与取消。前置：G+J+V；Cancel 选择取消分支。 | 原始进度/完成或取消消息、独立窗口及关闭后状态断言。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-vfx-animation.ps1 -Driver d3d12` | Demo 动画图选择、播放与停止。前置：G+J+V；TimingOnly 不验 GPU 运动。 | 正常模式必须有 GPU 运动证据和端点断言；计时模式只证明其计时路径。 | `-Jdk`、`-Driver`、`-RenderThread`、`-Runtime` |
| `.\scripts\test-vfx-soak.ps1 -Driver d3d12` | 真实 Demo 多轮前进/后退导航与内存采样。前置：G+J+V；Rounds 1–20，HeapMiB 128–4096；会启动并监视进程，超时/异常清理可终止自身测试进程。 | 完整导航样本、完成及清理；内存是否稳定还须分析 JSON。 | `-Jdk`、`-Driver` |

## 特殊模式与前置条件

### 桥接、读回与故障测试

下列是分别执行的命令，不要把所有开关堆在一次运行中：

```powershell
.\scripts\test-bridge.ps1 -Encoded -Driver d3d12
.\scripts\test-bridge.ps1 -StopFromHost -Driver d3d12
.\scripts\test-bridge.ps1 -Textures -Driver d3d12
.\scripts\test-bridge.ps1 -PrismTextures -Driver d3d12
.\scripts\test-bridge.ps1 -ShaderStates -Driver d3d12
.\scripts\test-bridge.ps1 -PrismContext -Driver d3d12
.\scripts\test-readback.ps1 -Driver d3d12 -Snapshot
.\scripts\test-readback.ps1 -Driver d3d12 -SnapshotStress
.\scripts\test-readback.ps1 -Driver d3d12 -StopDuringRead
.\scripts\test-scene-textures.ps1 -Driver d3d12 -Resize
.\scripts\test-scene-textures.ps1 -Driver d3d12 -MissingScene
.\scripts\test-failure-shutdown.ps1 -Driver d3d12 -Probe FailureApplicationProbe
.\scripts\test-vfx-dialog.ps1 -Driver d3d12 -InjectFailure
.\scripts\test-vfx-stage.ps1 -Driver d3d12 -Abrupt
```

`Encoded` 验批量编码与背压；`Textures` 验原生命令纹理路径；`PrismTextures` 验生产 Prism Texture；`ShaderStates` 验绘制状态；`PrismContext` 验 Graphics 绘制。读回的 `SnapshotStress` 隐含 `Snapshot`，不能与 `StopDuringRead` 组合。`FailureShutdownProbe` 是 failure-shutdown 的默认 Probe，另一个 Probe 用于 Application 异常路径。故障测试应由脚本的白名单判断，不能看到 ERROR 就直接认定失败，也不能忽略额外异常。

### 剪贴板

`.\scripts\test-clipboard-encoding.ps1` 使用源码 SDK 与默认 JDK，在 `-Xmx32m` / `MaxDirectMemorySize=96m` 下检查自定义格式 UTF-8、NUL、缓冲区位置/范围保持、只读短序列化字符串、长序列化字符串、伪造长度拒绝，以及 64 MiB 直接缓冲区在复制前被拒绝。还调用 Java 图片尺寸预检，覆盖无效尺寸、16384 单边上限及包含 40 字节 DIB 头的 64 MiB 预算，不实际分配大图片。要求 `CLIPBOARD_ENCODING_PASS`、`CLIPBOARD_IMAGE_BUDGET_PASS` 和正常退出；不启动 Godot、不访问系统剪贴板，不替代实际格式互操作验证。

`.\scripts\test-clipboard-snapshot-guard.ps1` 编译快照辅助类，测试注册格式白名单、空 owner、序列号保护和 256 MiB 总预算（精确上限、超限、空块、溢出）；还用一个 4 KiB 临时 HGLOBAL 和抛错字典验证跟踪失败会释放原生块。要求 `CLIPBOARD_SNAPSHOT_GUARD_PASS`、`CLIPBOARD_SNAPSHOT_BUDGET_PASS`、`CLIPBOARD_SNAPSHOT_ALLOCATION_FAILURE_PASS`。需要 Windows 和 PowerShell Add-Type/C# 编译支持，只操作该临时内存，不打开或读写剪贴板，也不启动 Godot；不能据此宣称实际备份恢复通过。

`test-clipboard.ps1` 在 Windows Forms STA 线程与 JavaFX 之间直接交换文本、HTML、RTF、URL、文件、图片和自定义格式。测试会覆盖现有系统剪贴板，结束后保留测试内容；无需备份、恢复或预先复制纯文本。验收要求两个方向的数据断言、Java 和宿主 PASS 标记及正常退出。

### Media 数据与生命周期

```powershell
# 环境准备时下载两个 MP4，后续复用通过 SHA-256 校验的文件
python scripts/setup-env.py
# 检查视频播放
.\scripts\test-media-video.ps1
# 单独运行 Lk 缩放和播放回归。macOS 使用 ./scripts/test-media-video.sh --sample lk
.\scripts\test-media-video.ps1 -Sample lk
# 正常视频生命周期 + AAC 注册稳定断言
.\scripts\test-media-churn.ps1 -Cycles 24 -Providers
# 扩展观察，仍不是无限时长泄漏证明
.\scripts\test-media-churn.ps1 -Cycles 120 -SettleSeconds 30 -Providers
# 纯音频隔离（首次生成 PCM，之后复用 agentdir/media/media-churn-silence.wav），以及原生 D3D 对照
.\scripts\test-media-churn.ps1 -AudioOnly -Cycles 24 -HandleTypes
.\scripts\test-media-churn.ps1 -NativeD3D -Cycles 24 -Providers
# Runtime 验证
.\scripts\test-media-video.ps1 -Runtime
.\scripts\test-media-churn.ps1 -Runtime -Cycles 24 -Providers
```

`Cycles` 为 24–240，`SettleSeconds` 只接受 0/30/60；等待阶段不强制 GC。`HandleTypes` 用当前进程的 Windows 句柄类型统计，`Providers` 隐含它，并只读查询 ETW 注册信息、检查 AAC provider 是否累计，不启动追踪会话。`NativeD3D` 与 `Runtime` 互斥。普通视频 churn 要先有正确 MP4；音频模式不需要 MP4。

播放器测试和命令行脚本曾被杀毒软件删除。遇到文件突然消失，记录文件缺失/隔离现象，不要把它当成测试成功，也不要自动关闭防护。当前 Media churn 使用直接运行和应用自行退出，不通过外部强杀获得通过。

### VFX 页面与交互

```powershell
.\scripts\test-vfx-intro.ps1 -AllPages -Driver d3d12
.\scripts\test-vfx-intro.ps1 -AllPages -PageLimit 5 -Driver d3d12
.\scripts\test-vfx-loading.ps1 -Cancel -Driver d3d12 -RenderThread safe
.\scripts\test-vfx-animation.ps1 -Driver d3d12 -RenderThread safe
.\scripts\test-vfx-animation.ps1 -TimingOnly -Driver d3d12 -RenderThread safe
.\scripts\test-vfx-soak.ps1 -Driver d3d12 -Rounds 3 -HeapMiB 256
```

`PageLimit` 要求 `AllPages`，且不能少于 3 或大于实际页数。`FreezeFusion` 仅是冻结 Fusion 动画的图像差异诊断，不可代替真实动画验收；若使用它，参考截图也必须相同设置。`TimingOnly` 明确不验 GPU 运动。soak 会生成进程、Java 和原生资源报告，但“导航通过”不等于“内存趋势通过”；脚本还会在超时/异常清理时结束自己启动的测试进程，需与不强杀的 Media churn 区分。

### 原生资源隔离与有限 Java 堆

```powershell
.\scripts\test-native-churn.ps1 -Kind Idle -Driver d3d12
.\scripts\test-native-churn.ps1 -Kind SubViewport -Driver d3d12
.\scripts\test-native-churn.ps1 -Kind Window -Driver d3d12
.\scripts\test-native-churn.ps1 -Kind JavaFXNativeWindow -Driver d3d12
.\scripts\test-stage-churn.ps1 -Driver d3d12 -Cycles 180 -HeapMiB 128
```

原生 churn 的 `StaticRangeLimitBytes` 默认 -1，不设内存范围门槛；如设置，应根据需要检验的回归定义合理阈值，不能为了通过随意增大。共享库的 release 构建中某些静态内存计数不可用，读到零不代表没有分配。

## 性能、截图与分析工具

切页及表格报告中的 `lifetime_max_*` 为宿主生命周期最大值；`last_offscreen_gpu_us`
为最近一次离屏 GPU 测量值，均不能当作区间差值或平均值。默认直接离屏路径的
GPU 时间戳回收有限制，零值不表示没有 GPU 开销。窗口 GPU 样本由切页夹具直接
读取视口，输出到 `VFX_TRANSITION_GPU`；已删除从未更新的宿主窗口计时字段。
普通累计计数仍按首尾相减，FPS 使用次数除以对应总时长。GPU 诊断可能超过默认
256 个时间戳槽位，配置与限制见 [性能指南](docs/frame-benchmark.md)。

这些不是统一的“全通过”测试；分别记录观测或执行专门门槛。

| 命令 | 用途与特殊前置条件 | 如何验收/解释 |
| --- | --- | --- |
| `.\scripts\make-media-fixture.ps1` | 需要 MSVC、Windows SDK、`jfx/build/windows_tools.properties`；本地编码器生成 16 秒 1920×1080 H.264 60 FPS 样本 | 构建及编码成功；独立 reader 验格式和 960 个样本，生成 MP4/hash JSON；不是播放性能证明 |
| `.\scripts\benchmark-media-frames.ps1 -Native60` | G+J+M；先按上一行准备视频和校验清单；默认 Godot/D3D12/safe、Rate=1 | 实际 Glass/Prism 身份正确、无失焦；Native60/Rate1 要求绘制 ≥55 FPS，Godot 另要求合成 ≥55 FPS 且背压为零 |
| `.\scripts\benchmark-media-frames.ps1 -Native60 -Runtime -ClockSkew -Sample 12` | 追加 Runtime；ClockSkew 测媒体时钟与最新帧时间戳；Sample 0–20 区分文件 | 相同 FPS 门槛；时钟差是软件取样，不是物理音画同步；生成样本没有音轨 |
| `.\scripts\benchmark-media-frames.ps1 -Backend d3d -Native60 -NoVSync -Sample 19` | J+M；原生 JavaFX 对照，NoVSync 传 `prism.vsync=false` | 不能作为 Godot 验收；不同 VSync 条件不能混作公平后端对照 |
| `.\scripts\benchmark-media-frames.ps1 -Rate 2 -Sample 12` | G+J+M；使用 Oracle 30 FPS MP4，加速播放到约 60 FPS | 观察输出，不是原生编码 60 FPS 验收；普通模式没有 Native60 的 ≥55 门槛 |
| `.\scripts\benchmark-vfx-frames.ps1 -Backend safe` | G+J+V；保持前台，默认 Godot D3D12 | 输出十轮动画的 Pulse、P95/P99/最大间隔和宿主合成率；脚本完成不自动保证 ≥60 FPS，应另核对焦点/背压 |
| `.\scripts\benchmark-vfx-frames.ps1 -Backend d3d` | J+V；原生对照 | 原生 Pulse 与 Godot composition 是不同计数，不能直接当相同的物理帧率 |
| `.\scripts\benchmark-vfx-frames.ps1 -Backend safe -Trace` | G+J+V；加入逐帧/原生命令统计 | 要求额外 trace 标记齐全；观测可能扰动性能，需与无 Trace 测量区分 |
| `.\scripts\benchmark-vfx-transitions.ps1 -Driver d3d12 -Backend safe` | G+J+V；35 页前进/后退共 68 次翻页的逐页帧率 | 输出每页脉冲 FPS/p50/p95/max 与汇总及宿主计数；必须有 Godot 后端标记、双侧 PASS、RESOURCE_CLEANUP_PASS（宿主移除后资源归零）和正整数 TARGET_SWITCHES（进程累计，不是计时区间差值）；重表格页受单帧内容成本限制，不是 60 FPS 门槛测试 |
| `.\scripts\profile-vfx-gpu.ps1` | G+J+V；默认 D3D12，可用 `-Driver vulkan` 或 `-Driver opengl` 采样 | 检查 profile 输出，作为瓶颈定位，不是默认性能验收 |
| `.\scripts\capture-vfx-reference.ps1` | J+V；用本地 SDK 的 D3D 捕获基线页面 | 记录 D3D 页面与 manifest，不能证明 Godot 画面对齐 |
| `python scripts/compare-vfx-pages.py --driver d3d12` | Python + Pillow；先完成匹配页数、缩放的 D3D 基线与 Godot AllPages 截图 | 生成配对图和差异统计，人工核对布局/缺失；随机数据和动画不是自动失败依据 |
| `python scripts/analyze-frame-trace.py agentdir/logs/vfx-frame-benchmark-safe-trace.log` | 先完成对应 Trace benchmark | 检查 trace 完整性并统计；计时区间有重叠，不能直接求和 |
| `python scripts/analyze-media-churn.py artifacts/reference/media-churn-mobile-cycles24-process-types-providers.json` | 完成同参数 Media churn；按实际生成文件名调整 | 验样本序号/进程、分段趋势、idle 等；斜率单独不能证明是否泄漏 |
| `python scripts/analyze-media-handles.py agentdir/logs/media-churn-mobile-cycles24-process-types-providers.log --require-stable-aac` | 日志含完整 churn 和 Providers 信息 | AAC 不能比首个采样继续累计；缺少数据或增长会失败，不覆盖所有内存资源 |
| `python scripts/analyze-vfx-soak.py artifacts/reference/vfx-soak-mobile-3-heap256.json` | 完成 soak，需核对其打印的实际 JSON 路径 | 统计各轮/主页/进程趋势；采样 console launcher 而非真实引擎的结果无效 |

Media 性能脚本还支持 `-FramePhases`、`-ClockSkew`、`-NoVSync`；Godot 模式默认使用 D3D12，支持 `-Driver d3d12|vulkan|opengl`。Runtime 不能与 D3D 组合。FramePhases 是 Godot 帧阶段诊断。当前 Native60 样本只有 16 秒，**不要与 Rate=2 组合做十秒测量**：预热后剩余媒体长度不足。VFX 的 `-Host120` 和 `-MailboxFps 60/120/240` 是调度诊断；Mailbox 须显式传 `-Driver vulkan`，不能与 Host120 或 D3D 组合。不要把这些开关作为默认性能条件。

复现前三页的 Fusion 边框诊断时，依次运行 `.\scripts\capture-vfx-reference.ps1 -FreezeFusion -PageLimit 3`、`.\scripts\test-vfx-intro.ps1 -Driver d3d12 -AllPages -FreezeFusion -PageLimit 3` 和 `python scripts/compare-vfx-pages.py --driver d3d12 --frozen`。常规全页验收保留动画。

## 没有包装脚本的诊断探针

一般从上面的脚本进入测试，不要直接运行依赖内部模块导出的 Java 类。下面两类可以单独隔离系统问题：

```powershell
# JDK 25 FFM：当前进程句柄类型和 Media Foundation 创建/释放
& "$env:JAVA_HOME/bin/javac.exe" -d artifacts/reference tests/reference/CurrentProcessHandles.java tests/reference/MediaFoundationLifecycleProbe.java
& "$env:JAVA_HOME/bin/java.exe" --enable-native-access=ALL-UNNAMED -cp artifacts/reference CurrentProcessHandles
& "$env:JAVA_HOME/bin/java.exe" --enable-native-access=ALL-UNNAMED -cp artifacts/reference MediaFoundationLifecycleProbe
& "$env:JAVA_HOME/bin/java.exe" --enable-native-access=ALL-UNNAMED -cp artifacts/reference MediaFoundationLifecycleProbe agentdir/media/media-oracle-sample.mp4

# 只有 Godot 的帧循环，不加载 JavaFX，用于区分宿主自身的节奏
. .\scripts\godot-fixture.ps1
Invoke-GodotFixture -Driver d3d12 --path tests/godot --script res://host_frame_probe.gd --render-thread safe
```

句柄探针打印自进程类型统计；MF 探针无参数时检查 24 对启动/关闭，传文件时增加 Source Reader 创建/释放，要求 HRESULT 成功及 `MF_LIFECYCLE_PROBE_PASS`。它不读取播放中的全部样本，不代表完整解码链路。宿主帧探针输出配置和 `HOST_FRAME_RESULT`；它不是 JavaFX 性能门槛测试。

```powershell
```

桥接预览在一次新的 pre-draw/post-draw 边界后读回，避免独立渲染线程的旧完成通知提前唤醒测试。

## 人工验收与记录

真实设备键鼠/触摸、中文输入法候选、跨显示器/DPI、桌面窗口外观、实际音频与音画同步需要独立验证。保留机器/显示器配置、运行后端、命令、时间、观察结果和图像，失败时记录可重复步骤。GPU 截图不能替代这些证据；用户已忽略的窗口白线不再阻塞。

本指南覆盖 `scripts/test-*` 全部入口，以及基准、参考捕获和分析工具；构建/启动/交付清单命令归 AGENTS.md。新增或改名测试时，应同步本表的用途、特殊参数与验收限制。

### 性能采样器的独立检查

`.\scripts\test-stack-sampler.ps1` 只需要默认 JDK（可用 `-Jdk` 覆盖），不启动 JavaFX/Godot、不操作输入设备。切页和大表滚动诊断共用此有界采样器。它检查非法间隔拒绝、长睡眠的可中断退出、停止后的稳定快照、4096 种调用栈上限及丢弃计数、采样异常报告。验收要求进程成功并出现 `THREAD_STACK_SAMPLER_PASS`，日志为 `agentdir/logs/stack-sampler.log`。

VFX 翻页基准可用 `GODOT_JFX_STACK_SAMPLE` 启用采样；必须是正整数毫秒。关闭时移除该变量，不能设为 `0`（会明确失败）。启用后的输出含 `VFX_TRANSITION_SAMPLING ... diagnostic_only=true`，采样会干扰时序，不应与未采样运行混合作帧率对照。`VFX_TRANSITION_SAMPLE_DROPPED` 表示超过调用栈种类上限的采样次数。

### Mesh 缓存预算与命令保留

- `.\scripts\test-bounded-lru.cmd`：仅需 MSVC。以 `/W4 /WX` 编译独立测试，验证哈希桶碰撞、内容候选拒绝、LRU 淘汰、字节/条目预算、替换计费、资源释放、插入分配失败回滚及整数溢出边界；要求退出码 0 和 `BOUNDED_LRU_PASS`。不启动 GUI。
- `.\scripts\test-mesh-transform.ps1 -CachePressure`（可加 `-Driver opengl`）：前置 G。先提交可见图形，再提交 4097 个不同的屏外图形挤出旧缓存，断言缓存限于 4096 项且最早图形仍正确显示；额外目标必须共享 4096 项预算，销毁额外目标后原目标缓存仍在，最后目标释放后新目标从空缓存开始。要求 `SHARED_TARGET_MESH_CACHE_PASS`、`SHARED_TARGET_MESH_RELEASE_PASS`、`MESH_TRANSFORM_PROBE_PASS` 且无 ERROR。该档强制开启 Mesh 缓存，结束后恢复环境。日志为 `mesh-transform-<driver>-cache-pressure.log`。不操作真实输入设备。

### 原生窗口立即关闭竞态

`.\scripts\test-window-immediate-close.ps1` 默认使用 D3D12 / safe，可选 `-Driver opengl`、`-RenderThread safe`、`-Runtime`。前置条件为 G。Runtime 档在 artifacts 建立独立项目，由源码 Editor 导入后通过发布的 DLL 运行。连续 32 次创建不可聚焦的原生 Window、切换 VSync 并立即关闭，中间不等待帧或渲染同步；随后等待渲染队列消费。必须有 32 个周期记录、`WINDOW_IMMEDIATE_CLOSE_PASS`、退出码 0 且无 ERROR。日志 `window-immediate-close-<driver>-<thread>[-runtime].log`。此测试会短暂创建窗口，但不操作真实鼠标或键盘。

## LCD 着色器加载检查

`.\scripts\test-lcd-shader-load.ps1` 需要 JDK 和源码 SDK（含 `jfx/build/modular-sdk` 的生成资源），无需 Godot、窗口或真实输入。检查普通及 AlphaTest 两种 LCD 着色器，在 `GODOT_JFX_LCD_SCREEN=0/1` 下均正常加载；再通过独立 `--patch-module` 资源目录给声明添加合法空格，验证普通模式仍接受、屏幕采样模式因无法按约定转换而明确报错，不能静默使用已停供的 LCDBuffer。四个进程均须退出 0 并打印 `LCD_SHADER_LOAD_PASS`；日志 `agentdir/logs/lcd-shader-load-*.log`。不改 SDK 资源，退出恢复环境变量；不证明 GPU 画面正确。可选 `-Jdk`。

## LCD 重叠文字对照

`.\scripts\test-lcd-overlap.ps1 [-RenderThread safe]` 需要 G+J，默认使用 D3D12/mobile + Viewport。两次运行分别启用原有 LCDBuffer 路径和屏幕采样路径，绘制同位置错开的蓝/红、绿/黑中英文 LCD 文字。Linux 夹具在相同大小的窗口里额外绘制缓存图层，包含短字符重叠以及带裁剪的字符。屏幕采样的像素仍需与 LCDBuffer 对照一致。两次都是 Godot 后端，不是原生 D3D 对照。脚本要求每次 Java/宿主完成标记及无错误，截图等待新一帧绘制完成，空图像或 PNG 保存失败立即报错；第二次全图 RGBA 差异不超过 2/255、图像包含足够文字像素，并打印 `LCD_OVERLAP_DIFF_PASS`。日志为 `lcd-overlap-<thread>-0/1.log`，截图为 `lcd-overlap-0/1.png`。退出确认使用 Godot 合成点击，不移动真实鼠标或键盘；测试串行运行，期间保持显示缩放和字体环境一致。该夹具覆盖相邻文字节点重叠，不是全部字体或 LCD 兼容性证明。

## 已排队纹理版本

`.\scripts\test-queued-texture-update.ps1 [-RenderThread safe]` 需要 G+J，使用 Viewport＋safe。在一次 Java 命令提交中把红色纹理画入第一目标，结束 pass、将同一逻辑纹理更新为蓝色，再画入第二目标。读回必须分别完整为红/蓝；要求 `QUEUED_TEXTURE_UPDATE_PASS`、`GODOT_QUEUED_TEXTURE_UPDATE_PASS`、正常退出且无错误。日志为 `queued-texture-update-mobile-<thread>.log`。不操作真实输入或系统剪贴板；验证 END_PASS 后尚未消费的纹理版本，不代替所有资源销毁场景。

### 显式 FPS 限制保护

`test-pacing-cap.ps1 -Driver d3d12`（也支持 gl_compatibility、-Jdk）需要源码
G+J。夹具把 Engine.max_fps 设为 30、VSync 设为开启，让 JVM 存活
6.5 秒，超过回退采样周期；要求设置均未被覆盖、无回退日志、Java 与宿主 PASS。
结束恢复夹具原设置，无真实键鼠输入。日志 agentdir/logs/pacing-cap-<driver>-<mode>.log。
`-Mode cap` 为默认；`-Mode restore` 用每帧 40 ms 的受控延迟触发真实回退，要求
Java 结束后及宿主移除后都恢复 max_fps=0、VSync 开启；`-Mode override` 在回退后
主动改成 47 FPS，要求停止后保留 47、恢复 VSync。后两模式需要显示器刷新率
至少 55 Hz、非全屏窗口，必须观察到回退才算通过。这不是 FPS 吞吐基准。

### 网格缓存淘汰后的绘制生命周期

`test-mesh-transform.ps1 -CachePressure`
同时挤出 surface 与离屏 target 的初始网格，再检查它们的像素仍正确。
缓存应保持 4096 项。可在当前进程设置 `GODOT_JFX_SLOT_REUSE=0` 验证不复用槽的
路径，结束后恢复原值；此测试不操作真实键鼠。它覆盖缓存淘汰时的已记录绘制，
不代表 GPU 分配失败测试。

### 编码器线程与提交失败检查

`ENCODER_BATCH_BOUNDARY_PASS` 还验证完整 QUADS（四顶点 176 字节）和缓存引用
（52 字节）的精确容量，以及字节不足/命令数达到 65536 时尝试提交。测试通过
独立 JVM 的未注册 JNI 错误观察提交入口，不发送构造的占位批次到真实宿主。

`test-render-command-validation.ps1` 除几何合法性、数组所有权、哈希碰撞及缓存
预算外，还拒绝外线程写入，并确认拥有者仍能继续编码。独立 JVM 未注册 Godot
JNI，调用 submit 必须抛出 UnsatisfiedLinkError；此后该编码器禁止写入和提交，
完成序号不推进。标记 `ENCODER_OWNERSHIP_FAILURE_PASS`；不启动窗口、不操作键鼠。
它验证提交 Error 的禁用路径，不等同于真实宿主背压超时或停止测试。

### Viewport 实例参数默认值

实例参数默认值回归：

```powershell
.\scripts\test-queued-texture-update.ps1 -RenderThread safe -ViewportState
```

此模式与 -BatchBoundary 互斥，启用 Viewport 实例参数，通过实际
Java/宿主协议连续复用同一离屏目标：显式红色、参数省略后的默认绿色、切换
着色器后的默认蓝色、删除该参数后的固定白色。各轮 256 像素必须完全一致；要求 VIEWPORT_STATE_PASS、
另用八个 shader 验证 float/int 的 1–4 分量（含负数与小数），要求 SHADER_CONSTANT_TYPES_PASS cases=8，退出资源归零。它替代本次调用的默认纹理版本场景；
不操作键鼠，环境变量结束后恢复。
日志 queued-texture-update-mobile-<safe>-viewport-state.log。

### 实际 GPU 跨批次状态

实际 GPU 跨批次验证可运行：

```powershell
.\scripts\test-queued-texture-update.ps1 -RenderThread safe -BatchBoundary
```

沿用该脚本的 G+J 前置条件，固定 Viewport＋safe，覆盖 direct-offscreen 与协议批次边界。
可选模式用真实裁剪命令填满 65536 条命令的批次，观察编码器 count（不修改它），
检查下一次绘制确实自动提交，再读回 16×16 图像逐像素断言红色与透明裁剪区。
要求 BATCH_BOUNDARY_PIXELS_PASS、原纹理版本双侧 PASS 以及退出资源归零。
反射所需 JAVA_TOOL_OPTIONS 仅在运行阶段设置并恢复；不操作真实键鼠。
日志 queued-texture-update-mobile-safe-boundary.log。该模式同时运行字节上限
场景：三次合法 1 MiB 纹理上传后继续填充裁剪命令，确认先到达 4 MiB 字节边界、
未达到命令数上限，再执行相同跨批次像素检查；要求额外的
`BATCH_BYTE_BOUNDARY_PIXELS_PASS`。需在当前 mobile/safe 构建重新验证。

### 协议资源事务的负向检查

`test-protocol.cmd` 的 `FRAME_RESOURCE_TRANSACTION_PASS` 验证同一帧中的纹理
分配、几何注册或释放随后遇到非法几何引用时，资源表、队列与序号均不部分提交。
修正帧可使用原序号重试，失败释放后原几何仍可引用。它直接验证 C++ 队列准入，
不启动 JVM/GPU，也不证明 GPU 分配失败或 Java 编码端的所有行为。

### 快速拖出窗口测试的当前验证

Linux 在私有 Weston 上运行 NonRobot 分组时，`test-physical-drag` 会单独启动没有原生输入设备的 Weston。Godot 仍通过真实 Wayland 窗口接收夹具注入的按下、移动和释放事件。这样，窗口扩大到桌面光标下面时，合成器不会在按住按钮的合成手势中插入来自桌面座位的无按键移动。Java 端仍检查全部 10 次拖动、8 次调整大小、最终几何及释放。单独复现双驱动用例可执行：

```sh
scripts/wsl-wayland-session.sh --isolate-wslg --no-input scripts/run-linux-tests.py --group NonRobot --driver all --test test-physical-drag
```

同组的 `test-hover-flicker` 也使用无原生输入设备的 Weston。该夹具为每次悬停注入一次鼠标移动，再逐帧检查按钮颜色。窗口初次调整大小时，真实座位的指针离开事件可以抵消这次合成移动。单独运行双驱动悬停检查时，将上面命令的 `--test` 参数改为 `test-hover-flicker`。

Robot 用例继续在带输入设备的桌面上运行。

`test-physical-drag.ps1` 的合成输入按初始窗口实际像素尺寸与 420×320 逻辑尺寸
换算，不再固定为 2 倍。真实 Robot 结束时依次尝试释放按键、恢复原光标位置、
销毁 Robot，任一步失败均保留为测试失败；脚本会创建日志和编译输出目录。
跨屏 DPI 和 Robot 清理错误仍需单独验证。

### 原生 JavaFX 大表物理拖动对照

`tests/reference/NativeTableDrag.java` 是原生 Windows Glass 对照，不是 Godot 验收。
前置 J+V、源码 SDK；运行会移动真实鼠标并按住左键，必须先取得用户同意，
要求测试窗口前台。`GODOT_JFX_DRAG_AXIS=h` 为水平，默认垂直。

仅编译（不操作输入）：

```powershell
& "$env:JAVA_HOME/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -cp 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*' -encoding UTF-8 -d artifacts/reference tests/reference/NativeTableDrag.java
```

获得同意后才可运行：

```powershell
& "$env:JAVA_HOME/bin/java.exe" '-Dglass.platform=Win' '-Dprism.order=d3d' --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -cp 'artifacts/reference;artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/resources/main;artifacts/vfx/resources/test;artifacts/vfx/dependencies/*' NativeTableDrag *> agentdir/logs/native-table-drag.log
```

要求退出码 0、原生 WinApplication 标记、完整 96 个间隔、所选轴累计实际位移至少 200 像素、NATIVE_TABLE_DRAG_PASS，
且无异常。失焦、提前关闭、异常或仍有脉冲推进时超过 45 秒均失败；结束时停止
计时器并尝试释放按键、恢复原鼠标位置、销毁 Robot；后台任务清理失败也仍尝试注销
全局监听器。此超时不是 FX 线程完全阻塞时的外部看门狗。
这些 Pulse 采样不包含像素断言或动态注入清理异常。[历次专项验证](agentdir/docs/TESTS.md)。

## 触摸键盘原生返回值

`.\scripts\test-tabtip-result.cmd` 使用 MSVC 编译独立 C++ 测试，无需 Godot/JVM。
用模拟 Windows 接口验证 COM 组件缺失、空接口、Toggle 失败/成功、关闭窗口缺失及消息投递失败；检查 HRESULT 保留和取得的 COM 接口恰好 Release 一次。要求 `TABTIP_RESULT_TEST_PASS` 和退出码 0。不会创建、切换或关闭真实触摸键盘，不覆盖实际 OS 接口可用性。

## 菜单打开后渲染进展

`.\scripts\test-menu-click.ps1 -Driver d3d12 -RenderThread safe` 需要 G+J+V，
固定使用 Viewport＋safe，默认渲染器为 mobile。探针最大化原始 VFX Demo，
浏览六页，然后由 Godot 按当前屏幕缩放合成菜单点击，不操作真实鼠标/键盘。
测试用回调包装器调用原菜单动作并记录其成功次数（必须恰好一次），保持业务
动作不变；六秒后正常结束，宿主还要求完成渲染序号及合成提交数相对点击前增加。
Java/宿主 PASS、退出码 0、无 ERROR/SHADER ERROR/异常才通过。FX 定时器有
45 秒期限，独立宿主循环有 60 秒期限；无阻塞 FX sleep 或后台无限 latch 等待。
日志 `agentdir/logs/menu-click-<driver>-<thread>.log`。它检查菜单动作与后续
渲染进展，不证明菜单所有像素或物理鼠标交互。可选 `-Jdk`、`-Driver`、`-RenderThread`。

窗口拖动夹具 `WindowDragProbe` 为避开实际光标只读取当前位置；成功创建的
Glass Robot 在读取结束或异常时通过 finally 释放。它不移动真实鼠标，实际拖动
由 Godot 注入。2026-11-10 的 GL/safe、mobile/separate 均通过 15 段共 240
物理像素拖动及最终位置/资源计数检查；这些结果不能替代物理拖动验收。

## 真实 Demo 的 LoadingStage 按钮悬停

`.\scripts\test-hover-demo.ps1 -CompileOnly` 仅编译；需要 J+V，不启动窗口或操作输入。
实际运行使用 `.\scripts\test-hover-demo.ps1 -Driver d3d12 -RenderThread safe -Robot`，
前置 G+J+V，**必须事先征得用户同意并保持桌面空闲**。该夹具仍为真实鼠标路径，
不以合成输入替代八轮渐进靠近、2.5 秒保持、渐进移出与 1.2 秒间隔。

Java 侧所有节点访问在 FX 线程，调用等待有 10 秒期限，退出恢复原光标并回收线程；
宿主保留 200 秒期限，采样按当前屏幕缩放映射，要求八轮各有越过过渡期的稳定样本
（HOLD 跳过前 31 帧；GAP 的 VFX 退出过渡是墙钟驱动，按 GAP 标题首次出现后 500ms
跳过，避免帧率下降时过渡跨越更多帧被误判）；固定亮度阈值 0.30、稳定期亮/暗错误
比例不得超过 5%。退出码 0、HOVER_DEMO_PASS、HOVER_DEMO_PIXEL_PASS 及无错误日志才
通过。macOS 入口为 `./scripts/test-hover-demo.sh --driver metal|opengl`
（双渲染器已通过）。日志
`agentdir/logs/hover-demo-<driver>-<thread>.log`，异常亮度图像位于 artifacts/reference。
早期记录仅有编译和解析；后续 `hover-demo-mobile-safe.log` 包含 Java 与像素通过标记（hold=861、gap=511），这不是 separate 模式的证明。逐帧读回/事件日志不能作为 FPS 基准。

Stage 渲染测试 `test-stage.ps1` 的像素映射使用浮点捕获宽度比例，只在图像坐标
边界取整，避免将 125%/150% 缩放截为整数；合成输入保留浮点坐标。2026-11-10
在当前 2× 环境的 mobile/GL 路径通过，尚未实际切换系统到分数 DPI 验收。

## 外部拖放 helper 的 COM 引用计数

`.\scripts\test-dnd-helper-lifetime.cmd` 需要 MSVC/Windows SDK，直接编译实际
`dnd_helper.cpp` 中的四类 COM 对象（不进入窗口主函数），检查 AddRef、
QueryInterface 和逐次 Release，循环释放 4000 个对象；要求退出 0 和
DND_HELPER_LIFETIME_PASS。不启动 helper 窗口、不访问剪贴板、不操作输入设备。

追加 `--asan` 使用 MSVC AddressSanitizer（需安装相应 VS 组件）检测内存非法访问；
当前环境已验证。除引用生命周期外，还检查枚举器 Next 参数错误不推进游标、Skip 恰好到末尾、
Reset/Clone 游标，以及 Clone/EnumFormatEtc 的逐次分配失败；要求额外输出
DND_HELPER_ENUMERATION_PASS。不替代跨进程拖放和其他数据读取/分配失败路径。
普通模式的 PASS 本身不能证明不存在释放后访问。

该 helper 组件测试还要求 DND_HELPER_READ_PASS：进程内伪 IDataObject 返回没有
终止符的 UTF-16/UTF-8 HGLOBAL，或在字符串构造时注入分配失败；检查 Drop
返回错误、effect 为 NONE、pUnkForRelease 恰好释放一次且释放前已 GlobalUnlock。
同时覆盖正常文本/自定义字符串读取，不访问系统剪贴板内容。

DND_HELPER_DATA_PASS 检查 QueryGetData/GetData 对内容类型、介质、索引和目标
设备的判定一致；查询不分配，文件列表分配失败返回 E_OUTOFMEMORY 且输出介质
为空；正常文件列表可读，空列表有双 NUL 终止符。仍为进程内数据对象测试。

DND_HELPER_EFFECT_PASS 验证 helper 的 COPY 能力与源端效果掩码取交集；无文本时
DragOver 仍拒绝，DragLeave/Drop 清除当前接受状态，并检查空参数失败返回。
它不经过真实系统拖放循环，不能替代外部鼠标夹具。

`DND_HELPER_STARTUP_PASS` 覆盖 helper 的启动失败清理：预注册同名窗口类，让
101 次启动在创建窗口前失败；检查日志文件已关闭、测试拥有的窗口类未被误删、
GDI 对象数不增长，以及 OLE 初始化已配对释放。另注入源端回调分配失败，检查
异常不会逃出窗口回调且退出码为 1。该测试不创建窗口、不操作真实输入设备；
不证明实际 DoDragDrop、正常窗口退出或系统消息循环故障路径已经动态验收。

`DND_HELPER_FILES_PASS` 验证 helper 完整读取超过 MAX_PATH 的首个文件名、未对齐
UTF-16 数据、ANSI 多文件和空列表；拒绝缺少列表结束标记、越界偏移和超长单项。
分配失败和 GetData 错误不得变成成功 Drop，介质在失败后也必须解锁并释放。
测试只构造内存中的文件列表，不创建这些路径、不访问剪贴板、不操作鼠标。

`DND_HELPER_OUTPUT_PASS`（helper 生命周期测试）和 `DND_OUTPUT_CONTRACTS_PASS`
（`test-dnd-drag-image.cmd`）使用相同契约检查两个 IDataObject：规范格式输出必须
保留输入字段、清空设备指针，支持输入输出别名；空指针明确失败；不支持订阅时
清空连接编号/枚举器输出。均不操作真实鼠标键盘。

OLE 合成注入观察器会在载荷失败/等待超时后仍请求关窗并退出，保留首个异常；
包装脚本必须同时看到 OLE_INJECT_PROBE_PASS 和 GODOT_OLE_INJECT_PASS。
宿主等待 Java 终态后判定结果，成功路径移除宿主并检查资源归零。`-Timeout`
故意阻塞 FX 线程五秒以验证过期请求取消，不是正常 UI 线程写法。
2026-11-10 另用临时编译的错误自定义载荷期望作负向验证：退出 1、无 PASS，
没有 close timeout 或宿主提前停止导致清理中断；临时类已恢复正常源码版本。

OLE 注入观察器在创建场景前创建并关闭临时 DND ClipboardAssistance，随后验证
正常入站负载与超时取消。该场景旧版本也能通过，因此不能作为“两份剪贴板缓存
不同步导致丢数据”的动态复现证明；缓存改动另依据 Clipboard.remove/get 的生命周期核对。

`./scripts/test-scroll-settings.ps1`：前置 J，验证输入 V2 记录长度、完整 UINT32
滚轮设置往返（含 0、1024、旧打包溢出边界、INT_MAX、0xffffffff 分页值），拒绝
负数、小数、溢出值和 NaN/Infinity。要求 `SCROLL_SETTINGS_PASS`，日志
`agentdir/logs/scroll-settings.log`；支持 `-Jdk`。不启动窗口、不修改系统滚轮
设置，也不操作输入设备；它不证明所有设置下 JavaFX 控件的实际滚动效果。

IME 输入回归的 `test-ime.ps1 -Driver d3d12 -SpacedClick` 在每次合成按钮事件后
等待两帧，用于隔离输入记录/组合文本路径，日志增加 `-spaced` 后缀。默认不加
参数，保留同帧 press/release。2026-11-10 默认路径曾发现焦点/IME 回调重入导致
release 先于 press，现已限制同步 IME 分派范围并通过 mobile/GL 默认回归；
两种模式都要求 IME_MOUSE_ORDER_PASS，分帧模式不能替代默认验收。脚本恢复对应环境
变量，两个模式都不操作真实鼠标键盘。点击坐标按 400×180 逻辑场景换算。

音频脚本 `test-media-audio.ps1 -Codec all` 在一次调用中只编译一次 MP3/AIFF
共用夹具工具；每次脚本调用仍从源码编译，避免复用旧 EXE。编译后立即恢复
PATH/INCLUDE/LIB，播放不继承编译器搜索路径。原来不存在的变量恢复为不存在，
与原来的空字符串值区分；最终 finally 同样保护异常路径。生成的音频和工具
保留在 artifacts，便于复查。2026-11-10 三格式播放与正常/编译失败环境恢复
检查通过，未进行可听声音或真实音频设备验收。

2026-11-11：`test-native-windows.ps1` 额外要求 `NATIVE_UNBOUND_HOST_CURSOR_PASS` 对应
断言：未绑定 Java 应用的宿主离树/析构不能改写应用默认光标。现有总 PASS 只有这些
断言完成后才输出；验证通过向 viewport 投递合成 motion 读取当前形状完成，
不移动系统鼠标。

## 启动窗口

`scripts/test-startup.ps1` 独立验证隐藏启动、首次窗口 logo、无 logo 模式、
延迟首帧和后续窗口；不操作真实键鼠。参数及验收限制见
[启动窗口验证](docs/startup-window.md#validation)。

## Node shader high-DPI regression

`test-node-shaders.ps1 -Jdk D:\jdk-25.0.3+9` also requires the identity shader to
preserve fine black/white stripes at 2x snapshot scale, reporting
`NODE_SHADER_HIDPI_IDENTITY_PASS`. This detects whole-subtree downsampling even
when the shader itself leaves every pixel unchanged. Use `-Driver d3d12` or
`-Driver opengl`; both renderers use Viewport with safe threading.

## VFX click ripple effect

After `build-vfx.ps1`, run `test-vfx-ripple.ps1` (mobile/safe/Viewport), `-Driver opengl`, or `-NativeD3D`. Require `VFX_RIPPLE_PROBE_PASS`
and, for Godot, `GODOT_VFX_RIPPLE_PASS`, with no shader/runtime errors.
The fixture verifies the menu checkbox and Scene-root scope, coexistence with
blackhole, left-only click positions and overlap, idle/expired restoration, GPU animation, transparent corners,
disabling/re-enabling, resize and window-hide cleanup. It uses synthetic mouse events without consuming them; no physical input permission is needed.
Details and artifact paths are in [VFX Demo](docs/vfx-demo.md#ripple-effect-in-the-intro-menu).

## Menu redraw performance and partial texture updates

`./scripts/profile-vfx-menu.ps1` profiles menu opening, ripple animation with the
menu open/closed, and repeated sliding. Use `-FullUploads` for the previous
complete-upload policy; the host supports only safe threading.
Require both `VFX_MENU_PERFORMANCE_PASS` and `GODOT_VFX_MENU_PERFORMANCE_PASS`
for completion. Timing is diagnostic, not a fixed FPS acceptance threshold.
The fixture uses synthetic events and does not operate physical input devices.
See [menu profiling](docs/frame-benchmark.md#menu-redraw-and-ripple-profiling).

`./scripts/profile-vfx-loading.ps1` profiles the LoadingStage demo window and
its completion alert while the ripple effect animates the main window. Require
both `VFX_LOADING_PERF_PASS` and `GODOT_VFX_LOADING_PERF_PASS`; `LOADING_PERF`
reports per-phase pulse rate. The fixture uses synthetic events and does not
operate physical input devices. See
[loading profiling](docs/frame-benchmark.md#loading-window-and-ripple-profiling).

The queued texture test begins with a same-pass sampler revision check.
Before any other encoder is created, it draws two quads
in one pass with the same sampler handle, separated by an upload. All 128
readback pixels must show the original red left half and updated blue right
half (`SAME_PASS_SAMPLER_REVISION_PASS`).

`test-queued-texture-update.ps1` now also requires `PARTIAL_TEXTURE_UPDATE_PASS`:
a partial upload before any draw must preserve untouched pixels, and a second
partial upload must preserve the revision retained by the first queued draw.
Both RGBA8 and floating-point RGBA textures are checked.
This runs in both the default texture case and `-ViewportState`, using safe threading. Add `-Driver opengl -ViewportState` for
OpenGL patch coverage. Region uploads default on; referenced textures still
use the immutable-revision path.
