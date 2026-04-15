import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var shieldView: UIVisualEffectView?

  private func updateScreenShield() {
    let captured = UIScreen.main.isCaptured
    if captured {
      if shieldView == nil, let window = self.window {
        let blur = UIBlurEffect(style: .systemChromeMaterialDark)
        let view = UIVisualEffectView(effect: blur)
        view.frame = window.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = true

        let label = UILabel()
        label.text = "Screen recording is not allowed."
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.addSubview(label)
        NSLayoutConstraint.activate([
          label.centerXAnchor.constraint(equalTo: view.contentView.centerXAnchor),
          label.centerYAnchor.constraint(equalTo: view.contentView.centerYAnchor)
        ])

        window.addSubview(view)
        shieldView = view
      }
    } else {
      shieldView?.removeFromSuperview()
      shieldView = nil
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenCaptureChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.updateScreenShield()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc private func screenCaptureChanged() {
    updateScreenShield()
  }
}
