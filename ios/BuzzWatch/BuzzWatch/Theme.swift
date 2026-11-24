import CoreText
import ImageIO
import SwiftUI

enum Theme {
    static let primary = Color(red: 0xD7 / 255, green: 0xD7 / 255, blue: 0x2E / 255)
    static let surface = Color(red: 0x28 / 255, green: 0x28 / 255, blue: 0x28 / 255)
    static let muted = Color(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xC7 / 255)
    static let pale = Color(red: 0xD7 / 255, green: 0xE7 / 255, blue: 0xF5 / 255)
}

/// The same Tabler artwork the phone app uses (its `BuzzIcons`).
///
/// `Fonts/tabler_icons.ttf` holds only these glyphs, cut from the phone's
/// `assets/fonts/TablerIcons.ttf`; `wear/README.md` says how to add one.
enum BuzzIcon: String {
    case close = "\u{eb55}" // x
    case check = "\u{ea5e}" // check
    case mic = "\u{eaf0}" // microphone
    case smile = "\u{eaf7}" // mood-smile
    case keyboard = "\u{ebd6}" // keyboard
    case chevronDown = "\u{ea5f}" // chevron-down

    private static let registered: Bool = {
        guard let url = Bundle.main.url(forResource: "tabler_icons", withExtension: "ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    func glyph(size: CGFloat) -> Text {
        _ = Self.registered
        return Text(rawValue).font(.custom("tabler-icons", fixedSize: size))
    }
}

/// A round button that is only an icon; `label` is what VoiceOver says.
struct RoundIcon: View {
    let icon: BuzzIcon
    var primary = false
    var size: CGFloat = 44

    var body: some View {
        icon.glyph(size: size * 0.46)
            .foregroundStyle(primary ? Color.black : Color.white)
            .frame(width: size, height: size)
            .background(primary ? Theme.primary : Theme.surface, in: Circle())
    }
}

/// A round picture of an agent; its initial until the picture loads, or if it has none.
struct Avatar: View {
    let choice: Choice?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.4))
            Text(String(choice?.name.prefix(1) ?? "").uppercased())
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
            RemotePicture(url: choice?.picture, maxSide: 96) { $0.resizable().scaledToFill() }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Loads `url` off the main thread, scaled down to what a watch can show.
struct RemotePicture<Content: View>: View {
    let url: String?
    let maxSide: CGFloat
    @ViewBuilder let content: (Image) -> Content
    @EnvironmentObject private var model: WatchModel
    @State private var picture: UIImage?

    var body: some View {
        ZStack {
            if let picture { content(Image(uiImage: picture)) }
        }
        .task(id: url) {
            guard let url, let media = model.media else { return }
            let key = "\(Int(maxSide)) \(url)" as NSString
            if let cached = Pictures.cache.object(forKey: key) {
                picture = cached
                return
            }
            let side = maxSide
            guard let data = await media.fetch(url),
                  let small = await Task.detached(operation: { Pictures.decode(data, maxSide: side) }).value
            else { return }
            Pictures.cache.setObject(small, forKey: key)
            picture = small
        }
    }
}

/// A few recent pictures, so scrolling back does not download them again.
private enum Pictures {
    /// Decodes straight to a small picture, so a large photo never sits in memory at full size.
    static func decode(_ data: Data, maxSide: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide * 2,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image)
    }

    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        return cache
    }()
}
