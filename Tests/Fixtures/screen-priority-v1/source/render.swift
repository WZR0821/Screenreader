// Renders each phone mock-up (402 x 874 pt) to a 1206 x 2622 PNG, the size of
// an iPhone 16 Pro screenshot. Offscreen window, no Dock icon, no focus change.
import AppKit
import WebKit

let args = CommandLine.arguments
let htmlDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])
let names = Array(args.dropFirst(3))

final class Loader: NSObject, WKNavigationDelegate {
    var done: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done?() }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1206, height: 2622),
                      styleMask: [.borderless], backing: .buffered, defer: false)
let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1206, height: 2622))
view.pageZoom = 3
window.contentView = view
let loader = Loader()
view.navigationDelegate = loader

func render(_ index: Int) {
    guard index < names.count else { exit(0) }
    let name = names[index]
    let file = htmlDir.appendingPathComponent(name + ".html")
    loader.done = {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let config = WKSnapshotConfiguration()
            config.rect = NSRect(x: 0, y: 0, width: 1206, height: 2622)
            view.takeSnapshot(with: config) { image, error in
                guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    print("snapshot failed \(name): \(String(describing: error))"); exit(1)
                }
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                let context = CGContext(data: nil, width: 1206, height: 2622, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                context.interpolationQuality = .high
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 1206, height: 2622))
                let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
                let data = rep.representation(using: .png, properties: [:])!
                try! data.write(to: outDir.appendingPathComponent(name + ".png"))
                print("rendered \(name) from \(cg.width)x\(cg.height), \(data.count) bytes")
                render(index + 1)
            }
        }
    }
    view.loadFileURL(file, allowingReadAccessTo: htmlDir)
}

DispatchQueue.main.async { render(0) }
app.run()
