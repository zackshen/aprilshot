# AprilShot

一个轻量、原生 Swift / AppKit 的 macOS 菜单栏截图 MVP。

按 **⌘⇧2（Command + Shift + 2）**，拖选屏幕区域，立即画笔或文字标注，再复制或保存 PNG。关闭标注窗口后，App 仍驻留菜单栏。

## 已实现

- 菜单栏常驻，无 Dock 图标；菜单和全局快捷键均可开始截图
- 调用 macOS 自带区域选择器，支持 Esc 取消；重复快捷键不会启动重叠捕获
- 画笔、颜色、粗细；文字、字号、中文输入与换行
- 以整条画笔 / 整段文字为单位撤销和重做
- 复制 PNG + TIFF 到剪贴板；PNG 保存对话框支持选择位置
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

菜单里的“屏幕录制设置…”可快捷跳转。App 不需要辅助功能或输入监控权限，不会自动添加登录项。需要登录后常驻时，可在系统设置的“通用 → 登录项”中手动添加 AprilShot。

本地 ad-hoc 重编译可能让 macOS 重新要求屏幕权限。保持 bundle ID 和安装位置不变有帮助；仍失效时，在系统设置中重新授权，并退出重开。不要为了运行这个 App 关闭 Gatekeeper 或其他系统安全机制。

## 操作

| 操作 | 方法 |
| --- | --- |
| 截取区域 | ⌘⇧2，或菜单栏“截取区域” |
| 取消系统截图 | Esc |
| 画笔 | 点击“画笔”或 B，然后拖动；单击绘制圆点 |
| 文字 | 点击“文字”或 T，再点击图片输入；Return 换行 |
| 完成当前文字 | ⌘Return，或点击画布 / 工具按钮 |
| 放弃当前文字 | Esc |
| 撤销 / 重做标注 | ⌘Z / ⇧⌘Z |
| 复制整张标注图 | ⇧⌘C，或“复制图片”；非文字编辑时也支持 ⌘C |
| 保存 PNG | ⌘S，或“保存 PNG…” |
| 关闭编辑窗口 | 窗口关闭按钮或 ⌘W |
| 退出 App | 菜单栏“退出 AprilShot”或 App 活跃时 ⌘Q |

输入文字时，⌘C / ⌘Z 等保留系统文字编辑含义。颜色、画笔粗细和字号仅影响新标注。尺寸按原图像素计算；在大尺寸 / Retina 截图中，可提高字号和粗细。

复制或保存后窗口保持打开，可以继续标注。只有当前版本成功复制或保存后，关闭时才不提示丢弃。

## MVP 边界

- 固定 ⌘⇧2，暂不提供快捷键自定义；冲突时会提示，仍可从菜单截图
- 文字提交后不能重新选择或移动，可撤销后重写；没有箭头、马赛克、裁剪或贴图
- 预览为适应窗口，没有独立缩放 / 平移工具；超出图片边缘的标注会被裁掉
- 使用系统 `screencapture` 交互选择器。按住 Control 可能改为系统剪贴板输出，此时无文件就不会打开编辑器
- 受系统保护的内容可能被屏蔽；不绕过 macOS 截图限制
- 不自动恢复未导出的截图，不自动登录启动，不自动检查更新
- 非 App Sandbox 应用；上架 Mac App Store 或改成 ScreenCaptureKit 是后续工作
- 没有发布签名 / 公证，也没有实机 UI 验收结论

## 验证与 CI

`./scripts/test.sh` 运行真实 Swift 断言测试，覆盖历史记录分支、导出状态恢复、画布坐标变换、边界拖动、PNG 尺寸与方向、线条 / 单点 / 中文文字绘制。

另有截图生命周期回归：将合成彩色 PNG 走实际截图加载器，删除临时文件后再首次绘制真实 `CanvasView`，检查底图像素、方向、窗口缩放、重复截图、画笔、撤销 / 重做与原图尺寸导出；独立覆盖先导出路径，以及损坏 / 不完整文件。CI 保存合成源图、编辑器画面和导出 PNG，可下载检查。测试不会读取或上传用户截图。

`.github/workflows/macos.yml` 会在 push / pull request 时于 macOS runner 编译完整 App、执行这些测试，并提供 7 天保留的开发版构建产物和渲染证据。CI 不代表屏幕授权或全局热键等交互验收；CI 产物也未经公证。

这份源码最初在 Linux 工作区编写，该环境无 Swift / Xcode / macOS SDK。交付时的实际检查状态见 [VALIDATION.md](VALIDATION.md)，不要把测试脚本的存在理解为已通过 macOS 运行测试。

## 文件结构

- `Sources/AppDelegate.swift`：菜单栏、权限和截图 / 窗口生命周期
- `Sources/HotKeyManager.swift`：Carbon 全局快捷键
- `Sources/ScreenshotCapture.swift`：系统区域截图和临时文件清理
- `Sources/CanvasView.swift`：画笔、内联文本和画布事件
- `Sources/EditorWindowController.swift`：工具栏、复制、保存和防丢失提示
- `Sources/Annotation.swift`：共享预览 / PNG 绘制器
- `Sources/Core/`：可测试的坐标与撤销历史
- `Tests/CoreTests.swift`：核心自动断言测试
- `Tests/CaptureRenderingTests.swift`：文件清理后的真实 AppKit 画布与 PNG 回归
- `Resources/Info.plist`：菜单栏 App bundle 配置
- `scripts/`：构建、运行与测试入口

## Apple 参考

- [Screen capture permission preflight](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess())
- [Request screen capture access](https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess())
- [LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)
- [Apple DTS：ad-hoc 重编译与 TCC 授权](https://developer.apple.com/forums/thread/819406)

区域选择器参数请在目标 Mac 用 `man screencapture` 核对；截图权限和快捷键行为请按验证清单做实机确认。
