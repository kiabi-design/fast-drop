import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, UIDropInteractionDelegate {
  private var dropChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      dropChannel = FlutterMethodChannel(
        name: "fastdrop/drop",
        binaryMessenger: controller.binaryMessenger
      )
      controller.view.addInteraction(UIDropInteraction(delegate: self))
    }
    return result
  }

  func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
    return true
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
    dropChannel?.invokeMethod("hover", arguments: true)
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
    return UIDropProposal(operation: .copy)
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
    dropChannel?.invokeMethod("hover", arguments: false)
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
    dropChannel?.invokeMethod("hover", arguments: false)
  }

  func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
    let fileManager = FileManager.default
    let stamp = Int(Date().timeIntervalSince1970)
    let dir = fileManager.temporaryDirectory.appendingPathComponent("fastdrop_drop_\(stamp)", isDirectory: true)
    try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

    let group = DispatchGroup()
    let lock = NSLock()
    var paths: [String] = []

    for item in session.items {
      let provider = item.itemProvider
      group.enter()
      provider.loadFileRepresentation(forTypeIdentifier: "public.item") { url, error in
        if let url = url {
          let dest = dir.appendingPathComponent(url.lastPathComponent)
          do {
            if fileManager.fileExists(atPath: dest.path) {
              try fileManager.removeItem(at: dest)
            }
            try fileManager.copyItem(at: url, to: dest)
            lock.lock()
            paths.append(dest.path)
            lock.unlock()
          } catch {
            // файл не удалось скопировать — пропускаем
          }
        }
        group.leave()
      }
    }

    group.notify(queue: .main) { [weak self] in
      self?.dropChannel?.invokeMethod("dropped", arguments: paths)
    }
  }
}