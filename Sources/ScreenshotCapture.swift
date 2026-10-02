import AppKit
import CoreGraphics
import ImageIO

final class ScreenshotCapture {
    enum Result {
        case captured(CGImage)
        case cancelled
        case failed(String)
    }
    private var process: Process?
    var isRunning: Bool { process != nil }

    // Kept separate so the temporary-file lifetime can be exercised by rendering tests.
    static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func start(completion: @escaping (Result) -> Void) {
        guard process == nil else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AprilShot-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        } catch {
            completion(.failed("无法创建截图临时目录：\(error.localizedDescription)"))
            return
        }
        let output = directory.appendingPathComponent("capture.png")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // Apple's interactive region picker supplies multi-display, Retina and Escape behavior.
        task.arguments = ["-i", "-s", "-x", "-t", "png", output.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] task in
            DispatchQueue.main.async {
                guard let self = self else {
                    try? FileManager.default.removeItem(at: directory)
                    return
                }
                self.process = nil
                defer { try? FileManager.default.removeItem(at: directory) }
                if let image = Self.loadImage(at: output) {
                    completion(.captured(image))
                } else if !FileManager.default.fileExists(atPath: output.path) {
                    // Escape and Control-to-clipboard can both finish without a file.
                    // Apple does not document a stable cancellation exit status.
                    if !CGPreflightScreenCaptureAccess() {
                        completion(.failed("屏幕录制权限未生效或已被撤销。请在系统设置中允许 AprilShot，然后退出并重新打开 App。"))
                    } else {
                        completion(.cancelled)
                    }
                } else {
                    completion(.failed("系统截图没有完成（退出码 \(task.terminationStatus)）。请检查屏幕录制权限后重试。"))
                }
            }
        }
        process = task
        do { try task.run() }
        catch {
            process = nil
            try? FileManager.default.removeItem(at: directory)
            completion(.failed("无法启动系统截图：\(error.localizedDescription)"))
        }
    }
    func cancel() {
        if process?.isRunning == true { process?.terminate() }
    }
    deinit { cancel() }
}
