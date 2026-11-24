import Flutter
import WatchConnectivity

/// Hands a pairing to this phone's Apple Watch. The system delivers it only to
/// this app's own watch app, on a watch paired with this phone. It is sent as
/// a live message, which is never queued or stored on the way: the watch app
/// has to be open to take it.
final class WatchPairingPlugin: NSObject, WCSessionDelegate {
  private let channel: FlutterMethodChannel
  private let session: WCSession? = WCSession.isSupported() ? .default : nil

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "buzz/watch_pairing", binaryMessenger: messenger)
    super.init()
    session?.delegate = self
    session?.activate()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(FlutterMethodNotImplemented) }
      switch call.method {
      // Names of the watches in reach, for the owner to confirm.
      case "watches": result(self.watch == nil ? [String]() : ["Apple Watch"])
      case "pair": self.pair(call.arguments, result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  /// The session, when this phone has a watch with Buzz on it.
  private var watch: WCSession? {
    guard let session, session.activationState == .activated, session.isPaired,
      session.isWatchAppInstalled
    else { return nil }
    return session
  }

  private func pair(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let payload = arguments as? FlutterStandardTypedData,
      var message = try? JSONSerialization.jsonObject(with: payload.data) as? [String: Any]
    else {
      return result(
        FlutterError(code: "invalid_arguments", message: "Expected the pairing bytes.", details: nil))
    }
    guard let watch else {
      return result(FlutterError(code: "no_watch", message: "No watch is connected.", details: nil))
    }
    guard watch.isReachable else {
      return result(
        FlutterError(
          code: "not_sent", message: "Open Buzz on your watch, then try again.", details: nil))
    }
    message["path"] = "/buzz/pair"
    watch.sendMessage(
      message,
      replyHandler: { reply in
        DispatchQueue.main.async {
          if let paired = reply["paired"] as? Int, paired > 0 {
            result(1)
          } else {
            result(
              FlutterError(
                code: "not_sent", message: "The watch did not take the pairing.", details: nil))
          }
        }
      },
      errorHandler: { error in
        DispatchQueue.main.async {
          result(FlutterError(code: "not_sent", message: error.localizedDescription, details: nil))
        }
      })
  }

  func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {}
  func sessionDidBecomeInactive(_ session: WCSession) {}
  // A different watch became the active one; follow it.
  func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
