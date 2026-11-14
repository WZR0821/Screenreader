import XCTest
import SwiftUI
import UIKit
@testable import ScreenTranslate

/// 1.3.2: both main pages on phones this Mac's simulator does not have. The
/// app's own root view is laid out in a window of each phone's size, with that
/// phone's safe area, and each page must come out exactly one screen tall:
/// nothing to scroll, and the last thing on it just above the tab bar.
@MainActor
final class OneScreenSizeTests: XCTestCase {
    private struct Phone {
        var name: String, width: CGFloat, height: CGFloat, top: CGFloat, bottom: CGFloat
    }

    /// Portrait sizes and safe areas of the phones iOS 18 runs on, tallest first.
    private let phones = [
        Phone(name: "16ProMax-440x956", width: 440, height: 956, top: 62, bottom: 34),
        Phone(name: "15ProMax-430x932", width: 430, height: 932, top: 59, bottom: 34),
        Phone(name: "14Plus-428x926", width: 428, height: 926, top: 47, bottom: 34),
        Phone(name: "11-414x896", width: 414, height: 896, top: 48, bottom: 34),
        Phone(name: "16Pro-402x874", width: 402, height: 874, top: 62, bottom: 34),
        Phone(name: "15-393x852", width: 393, height: 852, top: 59, bottom: 34),
        Phone(name: "14-390x844", width: 390, height: 844, top: 47, bottom: 34),
        Phone(name: "13mini-375x812", width: 375, height: 812, top: 50, bottom: 34)
    ]

    private let short = ["咖啡煮好了。", "列车十点到达。"]
    private let long = ["这是一段比较长的译文，用来确认最近翻译在一行放不下的时候怎样显示，而不会把页面撑得需要滚动。",
                        "第二段译文同样超过一行：请在明天上午十点以前把签好字的表格交到三楼的办公室，谢谢配合。"]

    func testTheSettingsPageFillsEveryPhone() throws {
        for phone in phones {
            try with(records: short) { store in
                try check(phone, page: 1, store: store, gap: 6...18, "settings")
            }
        }
    }

    func testTheTranslationPageFillsEveryPhoneWithRecords() throws {
        for phone in phones {
            try with(records: short) { try check(phone, page: 0, store: $0, gap: 8...20, "translation") }
            try with(records: long) { try check(phone, page: 0, store: $0, gap: 8...20, "translation-long") }
        }
    }

    func testTheTranslationPageFillsEveryPhoneWithoutRecords() throws {
        for phone in phones {
            try with(records: []) { try check(phone, page: 0, store: $0, gap: 8...20, "translation-empty") }
            try with(records: [short[0]]) { try check(phone, page: 0, store: $0, gap: 8...20, "translation-one") }
        }
    }

    /// The smallest phone iOS 18 runs on is too short for either page, so they scroll there.
    func testThePagesScrollOnAPhoneTooShortForThem() throws {
        let phone = Phone(name: "SE-375x667", width: 375, height: 667, top: 20, bottom: 0)
        for page in [0, 1] {
            try with(records: short) { store in
                let window = try show(phone, page: page, store: store)
                defer { window.isHidden = true; window.rootViewController = nil }
                let scroll = try pageScroll(in: window)
                XCTAssertGreaterThan(scroll.contentSize.height, room(of: scroll) + 1, "\(phone.name) page \(page)")
                attach(picture(of: window), "1.3.2-size-\(phone.name)-page\(page)")
            }
        }
    }

    /// With the keyboard up the translation page is too tall and scrolls, and
    /// its large title collapses. When the page fits again it is one screen,
    /// and the title comes back without a pull.
    func testAPageThatFitsAgainGetsItsLargeTitleBack() throws {
        let phone = try XCTUnwrap(phones.first { $0.name.hasPrefix("16Pro-") })
        try with(records: short) { store in
            let window = try show(phone, page: 0, store: store)
            defer { window.isHidden = true; window.rootViewController = nil }
            let controller = try XCTUnwrap(window.rootViewController)
            let scroll = try pageScroll(in: window)
            let full = scroll.adjustedContentInset.top
            XCTAssertEqual(scroll.contentSize.height, room(of: scroll), accuracy: 0.5, "one screen to begin with")

            // 300 points less at the bottom stand in for the keyboard.
            controller.additionalSafeAreaInsets.bottom += 300
            wait(1, window)
            XCTAssertGreaterThan(scroll.contentSize.height, room(of: scroll) + 1, "too tall with less room")
            scroll.setContentOffset(CGPoint(x: 0, y: -full + 150), animated: true)
            wait(1.5, window)
            print("ONESCREEN title scrolled: top \(scroll.adjustedContentInset.top) of \(full) offset \(scroll.contentOffset.y)")
            XCTAssertLessThan(scroll.adjustedContentInset.top, full - 1, "scrolling collapses the title")
            attach(picture(of: window), "1.3.2-title-collapsed")

            controller.additionalSafeAreaInsets.bottom -= 300
            // The bar's height on screen a tenth of a second in shows whether the title grows back or jumps.
            RunLoop.main.run(until: Date().addingTimeInterval(0.12))
            let bar = views(in: window, UINavigationBar.self).first
            let growing = bar?.layer.presentation()?.bounds.height ?? -1
            wait(3, window)
            print("ONESCREEN title grows: bar \(growing) on the way to \(bar?.bounds.height ?? -1)")
            print("ONESCREEN title back: top \(scroll.adjustedContentInset.top) of \(full) offset \(scroll.contentOffset.y)"
                  + " content \(scroll.contentSize.height) room \(room(of: scroll))")
            attach(picture(of: window), "1.3.2-title-back")
            XCTAssertEqual(scroll.adjustedContentInset.top, full, accuracy: 0.5, "the large title is back")
            XCTAssertEqual(scroll.contentOffset.y, -full, accuracy: 0.5, "at rest under it")
            XCTAssertEqual(scroll.contentSize.height, room(of: scroll), accuracy: 0.5, "one screen again")
            XCTAssertFalse(scroll.alwaysBounceVertical, "and it does not bounce")
        }
    }

    // MARK: -

    /// Lets layout and animations run for a while.
    private func wait(_ seconds: TimeInterval, _ window: UIWindow) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            window.layoutIfNeeded()
        }
    }

    /// A settings store of its own, with the given translations on record, newest last.
    private func with(records: [String], _ body: (SettingsStore) throws -> Void) throws {
        let suite = "ScreenTranslate.OneScreenSizeTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = SettingsStore(defaults: defaults, directory: directory, keychain: KeychainStore(service: suite))
        for text in records {
            try store.record(TranslationResult(original: "Original", translated: text, sourceLanguages: "英语",
                                               target: "中文", engine: "Test", elapsed: 0.2, mode: .quick))
        }
        try body(store)
    }

    private func check(_ phone: Phone, page: Int, store: SettingsStore, gap: ClosedRange<CGFloat>, _ name: String) throws {
        let window = try show(phone, page: page, store: store)
        defer { window.isHidden = true; window.rootViewController = nil }
        let scroll = try pageScroll(in: window)
        let label = "\(phone.name) \(name)"
        XCTAssertEqual(scroll.contentSize.height, room(of: scroll), accuracy: 0.5, "\(label): content against room")
        XCTAssertFalse(scroll.alwaysBounceVertical, "\(label): a page that fits does not bounce")
        XCTAssertEqual(scroll.contentOffset.y, -scroll.adjustedContentInset.top, accuracy: 0.5, "\(label): at rest under the bars")
        let image = picture(of: window)
        attach(image, "1.3.2-size-\(phone.name)-\(name)")
        let bar = try XCTUnwrap(views(in: window, UITabBar.self).first, label)
        let barTop = bar.convert(bar.bounds, to: window).minY
        XCTAssertEqual(barTop, phone.height - phone.bottom - 49, accuracy: 0.5, "\(label): tab bar")
        let space = try XCTUnwrap(spaceAbove(barTop, in: image), label)
        XCTAssertTrue(gap.contains(space), "\(label): \(space) points between the page and the tab bar")
    }

    /// The app's root view in a window the size of the phone, with the phone's safe area.
    private func show(_ phone: Phone, page: Int, store: SettingsStore) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: phone.width, height: phone.height)
        // The window has this simulator's safe area. A plain controller shows
        // what that is, so the page gets the phone's from its first layout on:
        // it remembers the tallest bars it has been under.
        let plain = UIViewController()
        window.rootViewController = plain
        window.isHidden = false
        window.layoutIfNeeded()
        let own = plain.view.safeAreaInsets
        let controller = UIHostingController(rootView: RootView(store: store, selection: page))
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: phone.top - own.top, left: 0,
                                                           bottom: phone.bottom - own.bottom, right: 0)
        window.rootViewController = controller
        // Layout settles over a few turns of the run loop.
        let deadline = Date().addingTimeInterval(4)
        var steady = 0, last = CGFloat.nan
        while steady < 4, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            window.layoutIfNeeded()
            let height = (try? pageScroll(in: window))?.contentSize.height ?? .nan
            steady = height == last ? steady + 1 : 0
            last = height
        }
        XCTAssertEqual(controller.view.safeAreaInsets.top, phone.top, accuracy: 0.5, "\(phone.name): top safe area")
        XCTAssertEqual(controller.view.safeAreaInsets.bottom, phone.bottom, accuracy: 0.5, "\(phone.name): bottom safe area")
        XCTAssertEqual(controller.view.bounds.size, CGSize(width: phone.width, height: phone.height), phone.name)
        return window
    }

    private func views<Kind: UIView>(in view: UIView, _ kind: Kind.Type) -> [Kind] {
        ((view as? Kind).map { [$0] } ?? []) + view.subviews.flatMap { views(in: $0, kind) }
    }

    /// The scroll view that holds the page: the tallest one that is not a text editor.
    private func pageScroll(in window: UIWindow) throws -> UIScrollView {
        let found = views(in: window, UIScrollView.self).filter { !($0 is UITextView) && $0.bounds.height > 300 }
        return try XCTUnwrap(found.max { $0.bounds.height < $1.bounds.height }, "no page scroll view")
    }

    /// The height the scroll view shows between the bars.
    private func room(of scroll: UIScrollView) -> CGFloat {
        scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom
    }

    private func picture(of window: UIWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2; format.opaque = true
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            UIColor.systemBackground.setFill(); context.fill(window.bounds)
            window.layer.render(in: context.cgContext)
        }
    }

    private func attach(_ image: UIImage, _ name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// How many points of plain background lie between the lowest thing drawn
    /// on the page and the tab bar.
    private func spaceAbove(_ barTop: CGFloat, in image: UIImage) -> CGFloat? {
        guard let source = image.cgImage else { return nil }
        let width = source.width, height = source.height, scale = CGFloat(height) / image.size.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Rows are stored top first. The page background shows at the left edge of every row.
        let first = Int((barTop * scale).rounded()) - 1
        for y in stride(from: min(first, height - 1), through: 0, by: -1) {
            let reference = (y * width + 2) * 4
            for x in 0..<width {
                let pixel = (y * width + x) * 4
                if (0..<3).contains(where: { abs(Int(pixels[pixel + $0]) - Int(pixels[reference + $0])) > 5 }) {
                    return CGFloat(first - y) / scale
                }
            }
        }
        return nil
    }
}
