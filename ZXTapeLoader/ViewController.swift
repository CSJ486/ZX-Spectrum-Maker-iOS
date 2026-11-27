import UIKit
import WebKit

/// Hosts the single-file ZX Spectrum Tape Loader web app (index.html) in a WKWebView.
/// - Works offline from the app bundle.
/// - Blob / data downloads (.TAP, .TZX, .WAV, .BAS, listings) are saved to the app's Documents folder
///   (visible in the Files app) and offered through the share sheet.
/// - Targets iOS 11+; Liquid Glass is used for the toast only on iOS 26+ when built with Xcode 26.
final class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

    private var webView: WKWebView!
    private let splash = UIImageView(image: UIImage(named: "Splash"))
    private var splashHidden = false
    private let startTime = Date()
    private let minSplashSeconds = 1.4

    /// Catches the web app's <a download href="blob:..."> clicks and passes the bytes to Swift.
    private let downloadHookJS = """
    (function () {
      if (window.__zxDlHook) return;
      window.__zxDlHook = true;
      function send(name, blob) {
        var r = new FileReader();
        r.onloadend = function () {
          var s = String(r.result || '');
          var i = s.indexOf(',');
          window.webkit.messageHandlers.saveFile.postMessage({
            name: name || 'download.bin',
            data: i >= 0 ? s.slice(i + 1) : ''
          });
        };
        r.readAsDataURL(blob);
      }
      document.addEventListener('click', function (ev) {
        var a = ev.target && ev.target.closest ? ev.target.closest('a[download]') : null;
        if (!a) return;
        var href = a.href || '';
        if (href.indexOf('blob:') !== 0 && href.indexOf('data:') !== 0) return;
        ev.preventDefault();
        ev.stopPropagation();
        fetch(href).then(function (res) { return res.blob(); })
          .then(function (blob) { send(a.getAttribute('download'), blob); })
          .catch(function (e) { console.error('iOS download failed', e); });
      }, true);
    })();
    """

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let controller = WKUserContentController()
        controller.add(self, name: "saveFile")
        controller.addUserScript(WKUserScript(source: downloadHookJS,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        config.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.backgroundColor = .white
        webView.isOpaque = true
        webView.scrollView.bounces = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        // iOS 11+: respect the safe area (notch, Dynamic Island, home indicator)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: guide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: guide.trailingAnchor)
        ])

        // Full-screen splash overlay that fades out once the page has loaded
        splash.contentMode = .scaleAspectFill
        splash.clipsToBounds = true
        splash.backgroundColor = .white
        splash.frame = view.bounds
        splash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(splash)

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        // Safety net: never leave the splash up for more than 6 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.hideSplash() }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { return .default }

    private func hideSplash() {
        if splashHidden { return }
        let remaining = max(0, minSplashSeconds - Date().timeIntervalSince(startTime))
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self = self, !self.splashHidden else { return }
            self.splashHidden = true
            UIView.animate(withDuration: 0.35, animations: { self.splash.alpha = 0 }) { _ in
                self.splash.removeFromSuperview()
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideSplash()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "mailto" {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // target="_blank" links (social links in the About tab) open in the browser
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return nil
    }

    // MARK: - WKUIDelegate (JS dialogs, in case a future build uses them)

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    // MARK: - Downloads (JS -> Swift)

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "saveFile",
              let body = message.body as? [String: Any],
              let rawName = body["name"] as? String,
              let base64 = body["data"] as? String,
              let data = Data(base64Encoded: base64) else { return }
        saveAndShare(name: rawName, data: data)
    }

    private func saveAndShare(name rawName: String, data: Data) {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var name = rawName.components(separatedBy: bad).joined(separator: "_")
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = "download.bin" }

        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        var url = docs.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            let ext = (name as NSString).pathExtension
            let base = (name as NSString).deletingPathExtension
            let numbered = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            url = docs.appendingPathComponent(numbered)
            n += 1
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            showToast("Save failed: \(error.localizedDescription)")
            return
        }

        showToast("Saved \(url.lastPathComponent)")

        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = share.popoverPresentationController {   // iPad needs an anchor
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        present(share, animated: true)
    }

    // MARK: - Toast (Liquid Glass on iOS 26+, blur on older versions)

    private func makeToastBackground() -> UIVisualEffectView {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            return UIVisualEffectView(effect: UIGlassEffect())
        }
        #endif
        let style: UIBlurEffect.Style
        if #available(iOS 13.0, *) { style = .systemMaterial } else { style = .extraLight }
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    private func showToast(_ text: String) {
        let background = makeToastBackground()
        background.translatesAutoresizingMaskIntoConstraints = false
        background.layer.cornerRadius = 20
        background.clipsToBounds = true
        background.alpha = 0

        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .black
        label.numberOfLines = 2
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        background.contentView.addSubview(label)

        view.addSubview(background)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: background.contentView.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -18),
            background.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            background.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -24),
            background.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48)
        ])

        UIView.animate(withDuration: 0.25, animations: { background.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.35, delay: 2.4, options: [], animations: { background.alpha = 0 }) { _ in
                background.removeFromSuperview()
            }
        }
    }
}
