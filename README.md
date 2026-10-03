# AprilShot

一个轻量、原生 Swift / AppKit 的 macOS 菜单栏截图 MVP。

按 **⌘⇧2（Command + Shift + 2）**，拖选屏幕区域，默认矩形框选，也可画笔或文字标注，再复制图片路径或保存 PNG。关闭标注窗口后，App 仍驻留菜单栏。

## 已实现

- 菜单栏常驻，无 Dock 图标；自绘取景框图标适配浅 / 深色，简洁菜单保留全部入口
- 菜单和全局快捷键均可开始截图，默认 ⌘⇧2；可在“设置…”更改，菜单同步显示当前生效的快捷键
- 调用 macOS 自带区域选择器，支持 Esc 取消；重复快捷键不会启动重叠捕获
- 紧凑分组工具栏：图标、当前工具高亮、原生颜色选择；按工具显示粗细或字号
- 画布直达窗口底部；复制路径 / 保存结果直接在按钮上短暂提示
- 默认“框选”矩形框标注、画笔、颜色、粗细；文字、字号、中文输入与换行
- 以整个矩形 / 整条画笔 / 整段文字为单位撤销和重做
- 复制路径：先将标注 PNG 持久保存到本机，再把绝对文件路径作为文本放入剪贴板，方便粘贴给本机 Codex CLI
- 已复制图片默认保留最近 3 天，过期移入废纸篓；可选 1 / 3 / 7 / 30 天或不自动清理，菜单可预览数量后手动清理
- 正在剪贴板中引用及最近 5 分钟生成的图片暂不清理；“保存”自行选择的文件不参与清理
- 预览按窗口缩放，导出保留截图原始像素尺寸
- 多个截图窗口互不覆盖；新截图暂时隐藏所有 AprilShot 窗口
- 未复制 / 未保存时关闭或退出会提示；取消保存不丢失编辑
- 临时截图在读取后删除，不上传图片，无网络请求和遥测
- 零第三方应用依赖，附 macOS 构建 / 测试脚本与 GitHub Actions

## 环境要求

- macOS 13 Ventura 或更新
- Apple Silicon 或 Intel Mac
- Xcode Command Line Tools（或完整 Xcode），Swift 5.7 及以上

先在终端安装 Apple 的开发工具（如已安装可跳过）：

```sh
xcode-select --install
```

然后在源码目录运行：

```sh
./scripts/build.sh
./scripts/test.sh
open build/AprilShot.app
```

也可执行 `./scripts/run.sh` 一步构建并打开。必须用 `open` / Finder 启动完整 `.app`，不要直接运行 `Contents/MacOS/AprilShot`，否则系统权限可能归属到终端。

构建产物为 `build/AprilShot.app`，默认针对本机 CPU。另一个架构可用 `ARCH=x86_64 ./scripts/build.sh` 或 `ARCH=arm64 ./scripts/build.sh` 交叉构建；只可在对应架构或支持转译的 Mac 上运行。默认是本地 ad-hoc 签名，**未经 Developer ID 签名或 Apple 公证，不是已验证的发布安装包**。

如需固定放在应用程序目录，可在 Finder 中复制 `build/AprilShot.app` 到“应用程序”，以后从同一位置启动。更新前先退出旧实例。

开发者如已有自己的签名身份，可选择：

```sh
SIGN_IDENTITY='Apple Development: Your Name (TEAMID)' ./scripts/build.sh
```

脚本不会创建证书、登录账号或自动访问任何人的签名凭据。不要把证书、私钥或其他凭据提交进仓库。

## 首次权限

首次截图时，macOS 会询问“屏幕录制”权限。请到：

**系统设置 → 隐私与安全性 → 屏幕录制**

较新 macOS 可能称其为“屏幕与系统音频录制”。打开 AprilShot 的授权后，完全退出并重新打开 App，再按 ⌘⇧2。

菜单里的“截图权限…”可快捷跳转。App 不需要辅助功能或输入监控权限，不会自动添加登录项。需要登录后常驻时，可在系统设置的“通用 → 登录项”中手动添加 AprilShot。

本地 ad-hoc 重编译可能让 macOS 重新要求屏幕权限。保持 bundle ID 和安装位置不变有帮助；仍失效时，在系统设置中重新授权，并退出重开。不要为了运行这个 App 关闭 Gatekeeper 或其他系统安全机制。

## 操作

| 操作 | 方法 |
| --- | --- |
| 截取区域 | ⌘⇧2，或菜单栏“截图” |
| 取消系统截图 | Esc |
| 矩形框选（默认） | 点击“框选”或 R，再拖动画矩形框标注 |
| 画笔 | 点击“画笔”或 B，然后拖动；单击绘制圆点 |
| 文字 | 点击“文字”或 T，再点击图片输入；Return 换行 |
| 完成当前文字 | ⌘Return，或点击画布 / 工具按钮 |
| 放弃当前文字 | Esc |
| 撤销 / 重做标注 | ⌘Z / ⇧⌘Z |
| 保存标注图并复制路径 | ⇧⌘C，或工具栏“复制路径”；非文字编辑时也支持 ⌘C |
| 查看已复制图片 | 菜单栏“图片文件夹” |
| 手动清理图片 | 菜单栏“清理…”；确认数量后移入废纸篓 |
| 快捷键 / 保留策略 | 菜单栏“设置…”或 App 活跃时 ⌘, |
| 保存 PNG | ⌘S，或工具栏“保存” |
| 关闭编辑窗口 | 窗口关闭按钮或 ⌘W |
| 退出 App | 菜单栏“退出”或 App 活跃时 ⌘Q |

输入文字时，⌘C / ⌘Z 等保留系统文字编辑含义。颜色、矩形 / 画笔粗细和字号仅影响新标注。尺寸按原图像素计算；在大尺寸 / Retina 截图中，可提高字号和粗细。

复制路径或保存后窗口保持打开，可以继续标注。只有当前版本成功复制或保存后，关闭时才不提示丢弃。

### 在本机 Codex CLI 中使用

1. 在图片上完成矩形 / 画笔 / 文字标注，点击“复制路径”或按 ⇧⌘C；当前仍在输入的文字、矩形和未结束的笔画也会包含在 PNG 内。
2. 在同一台 Mac 的 Codex CLI 提示输入区粘贴，例如输入“请查看这张图片：”再按 ⌘V。得到的是 `/Users/你的用户名/Library/Application Support/AprilShot/Exports/AprilShot_日期时间_UUID.png` 这样的绝对路径文本，不是 `file://` URL，也不是图片剪贴板格式。
3. PNG 保留原始像素尺寸。每次复制生成独立文件，不会覆盖旧图片；关闭编辑器不删除图片。旧图片按设置的保留策略清理，长期需要的文件请用“保存”另存。

图片存放于 `~/Library/Application Support/AprilShot/Exports`；可以从菜单“图片文件夹”进入 Finder。文件可能包含屏幕上的私密信息，**只存本机，不自动上传**。复制失败会显示原因，磁盘写入失败时剪贴板不变。

### 设置与清理

- “设置…”可选择截图按键及修饰键，默认 ⌘⇧2。支持字母、数字和 F1–F12；按键按美式键盘的物理位置识别，至少两个修饰键且包含 Command 或 Control。保留常用编辑 / 系统组合，注册冲突会显示原因并保留原快捷键。保存后立即生效，重新打开 App 仍保留设置
- 设置窗口中的“恢复默认”只重置尚未保存的快捷键选择；“取消”或关闭窗口不应用修改。重复打开已显示的设置窗口不会丢失尚未保存的选择
- 默认保留最近 **3 × 24 小时**；可选择 1 / 3 / 7 / 30 天或“不自动清理”。启动、保存设置和运行期间每小时检查；超过保留时间才移入废纸篓，正好达到时限仍保留
- “清理…”会预览可清理数量与大小，确认后将所列图片移入废纸篓，不永久删除。清理后的旧路径失效，可从废纸篓恢复；取消不会变更文件
- 当前剪贴板中绝对路径引用的图片、最近 5 分钟生成的图片均跳过，避免刚复制就失效。该保护不是永久保存：剪贴板换成其它内容且达到保留期限后，旧图片仍可能被清理
- 新版仅清理它登记过、身份与大小 / 修改时间未变化的独立常规文件，不递归子目录，不处理符号链接、硬链接、未知文件或手动另存图片；文件夹路径本身包含符号链接时停止清理
- 兼容旧版残留时，首次登记只识别专用目录内严格符合旧版 `AprilShot_日期时间_UUID.png` 格式且通过 PNG 完整性检查的独立常规文件。这是基于旧版命名约定的兼容判定。之后出现的未登记文件不会因同名格式被自动收纳；编辑或替换过的文件保留
- 清理失败会保留未成功移动的文件并提示。配置损坏时暂停自动清理，直到重新保存有效设置；注册失败仍能从菜单截图。若已保存快捷键在启动时冲突，会尝试临时使用默认快捷键并明确提示实际状态

路径用于 Codex 的对话提示，不是可执行命令。若自己将它用作终端命令参数，请按 shell 规则给带空格的路径加引号。运行在 SSH、容器或云端的 Codex 无法直接访问这台 Mac 的路径，需要另行传输文件。Codex 是否可以读到文件仍受它的工作环境和访问权限限制。

## MVP 边界

- 矩形、笔画与文字提交后不能重新选择或移动，可撤销后重画 / 重写；“框选”是矩形框标注，没有裁剪、箭头、马赛克或贴图
- 预览为适应窗口，没有独立缩放 / 平移工具；超出图片边缘的标注会被裁掉
- 使用系统 `screencapture` 交互选择器。按住 Control 可能改为系统剪贴板输出，此时无文件就不会打开编辑器
- 受系统保护的内容可能被屏蔽；不绕过 macOS 截图限制
- 不自动恢复未导出的截图，不自动登录启动，不自动检查更新
- 非 App Sandbox 应用；上架 Mac App Store 或改成 ScreenCaptureKit 是后续工作
- 没有发布签名 / 公证，也没有实机 UI 验收结论

## 验证与 CI

`./scripts/test.sh` 运行真实 Swift 断言测试，覆盖历史记录分支、导出状态恢复、画布坐标变换、边界拖动、PNG 尺寸与方向、线条 / 单点 / 中文文字绘制。

另有截图生命周期回归：将合成彩色 PNG 走实际截图加载器，删除临时文件后再首次绘制真实 `CanvasView`，检查底图像素、方向、窗口缩放、重复截图、画笔、撤销 / 重做与原图尺寸导出；独立覆盖先导出路径，以及损坏 / 不完整文件。CI 保存合成源图、编辑器画面和导出 PNG，可下载检查。测试不会读取或上传用户截图。

工具栏回归额外实例化真实编辑器，检查浅 / 深色、最小 / 大窗口布局、无底部信息栏、工具选中态、设置与历史操作，并生成合成预览图供目视检查。

菜单栏回归检查简短菜单标题、快捷键、每个入口的动作路由，以及截图忙碌状态；图标回归检查 1× / 2× / 3× 像素、边缘留白和四角轮廓，并生成真实 AppKit 浅色 / 深色 / 选中态按钮预览。按钮预览为合成测试，不是系统菜单弹出的实机截图。

复制路径回归覆盖真实 AppKit 输入、PNG 落盘与系统剪贴板：未结束的笔画、输入中的中文文字、文件像素和尺寸、重复复制唯一性、Unicode / 空格路径、关闭后保留、独立本地进程读取，以及存储 / 剪贴板失败和恢复。它不等于实际 Codex CLI 的端到端粘贴验收。

`.github/workflows/macos.yml` 会在 push / pull request 时于 macOS runner 编译完整 App、执行这些测试，并提供 7 天保留的开发版构建产物和渲染证据。CI 不代表屏幕授权或全局热键等交互验收；CI 产物也未经公证。

这份源码最初在 Linux 工作区编写，该环境无 Swift / Xcode / macOS SDK。交付时的实际检查状态见 [VALIDATION.md](VALIDATION.md)，不要把测试脚本的存在理解为已通过 macOS 运行测试。

## 文件结构

- `Sources/AppDelegate.swift`：菜单栏、权限和截图 / 窗口生命周期
- `Sources/StatusMenu.swift`：自绘矢量菜单栏图标、简洁原生菜单和帮助文案
- `Sources/HotKeyManager.swift`：可回滚的 Carbon 全局快捷键
- `Sources/AppPreferences.swift`：快捷键验证与版本化设置持久化
- `Sources/SettingsWindowController.swift`：快捷键与保留策略设置窗口
- `Sources/ExportCleanup.swift`：文件归属、旧版兼容与废纸篓清理
- `Sources/ScreenshotCapture.swift`：系统区域截图和临时文件清理
- `Sources/CanvasView.swift`：矩形、画笔、内联文本和画布事件
- `Sources/EditorWindowController.swift`：工具栏布局、复制、保存和防丢失提示
- `Sources/ImagePathCopier.swift`：持久 PNG 保存和纯文本绝对路径复制
- `Sources/EditorToolbar.swift`：原生工具按钮、分组外观与选中态
- `Sources/Annotation.swift`：共享预览 / PNG 绘制器
- `Sources/Core/`：可测试的坐标与撤销历史
- `Tests/CoreTests.swift`：核心自动断言测试
- `Tests/CaptureRenderingTests.swift`：文件清理后的真实 AppKit 画布与 PNG 回归
- `Tests/EditorToolbarTests.swift`：工具栏布局、交互、快捷键、剪贴板与浅 / 深色合成预览
- `Tests/StatusMenuTests.swift`：图标像素与 AppKit 渲染、菜单标题 / 快捷键 / 忙碌状态回归
- `Tests/CopyPathTests.swift`：持久文件、当前标注、失败重试与路径剪贴板回归
- `Tests/RectangleTests.swift`：默认矩形、边界 / 反向拖动、历史与原图导出
- `Tests/HotKeyPreferencesTests.swift`：快捷键冲突、原子回退、持久化与损坏设置
- `Tests/SettingsWindowTests.swift`：设置保存 / 取消 / 重复打开及真实 AppKit 浅深色预览
- `Tests/ExportCleanupTests.swift`：清理边界、归属保护、旧版兼容、符号链接与失败恢复
- `Resources/Info.plist`：菜单栏 App bundle 配置
- `scripts/`：构建、运行与测试入口

## Apple 参考

- [Screen capture permission preflight](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess())
- [Request screen capture access](https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess())
- [LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)
- [Apple DTS：ad-hoc 重编译与 TCC 授权](https://developer.apple.com/forums/thread/819406)

区域选择器参数请在目标 Mac 用 `man screencapture` 核对；截图权限和快捷键行为请按验证清单做实机确认。
