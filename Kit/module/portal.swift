//
//  portal.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 17/02/2023
//  Using Swift 5.0
//  Running on macOS 13.2
//
//  Copyright © 2023 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public protocol Portal_p: NSView {
    var name: String { get }
    var height: CGFloat { get }
}

open class PortalWrapper: NSStackView, Portal_p {
    public var name: String
    public var height: CGFloat
    
    private let header: PortalHeader
    public let body: NSStackView
    
    public init(_ type: ModuleType, height: CGFloat = 100) {
        self.name = type.stringValue
        self.height = 20 + Constants.Popup.spacing + height
        
        self.header = PortalHeader(type.stringValue)
        self.body = {
            let view = NSStackView()
            
            view.orientation = .horizontal
            view.distribution = .fillEqually
            
            view.spacing = Constants.Popup.spacing*2
            view.edgeInsets = NSEdgeInsets(
                top: Constants.Popup.spacing,
                left: Constants.Popup.spacing,
                bottom: Constants.Popup.spacing,
                right: Constants.Popup.spacing
            )
            
            return view
        }()
        
        super.init(frame: .zero)
        
        self.orientation = .vertical
        self.alignment = .width
        self.spacing = Constants.Popup.spacing
        
        self.addArrangedSubview(self.header)
        self.addArrangedSubview(self.body)
        
        self.load()
        
        if self.body.subviews.isEmpty {
            self.body.addArrangedSubview(NSView())
        }
        
        self.heightAnchor.constraint(equalToConstant: self.height).isActive = true
        self.header.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
        self.body.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
        self.body.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open func load() {
        self.body.addArrangedSubview(NSView())
    }
}

public class PortalHeader: NSStackView {
    private let name: String
    
    public init(_ name: String) {
        self.name = name
        
        super.init(frame: NSRect.zero)
        self.heightAnchor.constraint(equalToConstant: 20).isActive = true
        
        let title = NSTextField()
        title.isEditable = false
        title.isSelectable = false
        title.isBezeled = false
        title.wantsLayer = true
        title.textColor = .textColor
        title.backgroundColor = .clear
        title.canDrawSubviewsIntoLayer = true
        title.alignment = .natural
        title.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        title.stringValue = localizedString(name)
        
        let settings = NSButton()
        settings.heightAnchor.constraint(equalToConstant: 18).isActive = true
        settings.bezelStyle = .regularSquare
        settings.translatesAutoresizingMaskIntoConstraints = false
        settings.imageScaling = .scaleProportionallyDown
        settings.image = iconFromSymbol(name: "gearshape.fill", scale: .medium)
        // portals only appear in the combined popup, which is glass on macOS 26+
        if #available(macOS 26.0, *) {
            settings.contentTintColor = .labelColor
        } else {
            settings.contentTintColor = .lightGray
        }
        settings.isBordered = false
        settings.action = #selector(self.openSettings)
        settings.target = self
        settings.toolTip = localizedString("Open module settings")
        settings.focusRingType = .none
        
        self.addArrangedSubview(title)
        self.addArrangedSubview(NSView())
        self.addArrangedSubview(settings)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func openSettings() {
        self.window?.setIsVisible(false)
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": self.name])
    }
}

// A single compact row for the combined popup: icon, title, optional subtitle, value and a chevron.
// Clicking the row calls `onClick`, which the combined view uses to open the module's full popup.
public class CompactPortalRow: NSView {
    public static let height: CGFloat = 40
    
    public let name: String
    public var onClick: ((String) -> Void)? = nil
    
    private let defaultIcon: NSImage?
    private let iconBackground: NSView = NSView()
    private let iconView: NSImageView = NSImageView()
    private let titleField: NSTextField = CompactPortalRow.label(size: 13, weight: .regular, color: .labelColor)
    private let subtitleField: NSTextField = CompactPortalRow.label(size: 11, weight: .regular, color: .secondaryLabelColor)
    private let valueField: NSTextField = CompactPortalRow.label(size: 12, weight: .regular, color: .secondaryLabelColor)
    private let chevron: NSImageView = NSImageView()
    
    private var highlighted: Bool = false {
        didSet { self.updateLayer() }
    }
    private var active: Bool = false
    private var iconKey: String? = nil
    private var trackingArea: NSTrackingArea? = nil
    
    public init(name: String, icon: NSImage?) {
        self.name = name
        self.defaultIcon = icon
        
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: CompactPortalRow.height))
        self.wantsLayer = true
        self.layer?.cornerRadius = 8
        self.toolTip = localizedString("Open details")
        
        self.iconBackground.wantsLayer = true
        self.iconBackground.layer?.cornerRadius = 14
        self.iconView.image = icon
        self.iconView.imageScaling = .scaleProportionallyDown
        self.iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        
        self.titleField.stringValue = localizedString(name)
        self.subtitleField.isHidden = true
        self.valueField.alignment = .right
        self.valueField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        self.valueField.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.valueField.setContentHuggingPriority(.required, for: .horizontal)
        self.titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        self.chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        self.chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        self.chevron.contentTintColor = .tertiaryLabelColor
        
        let text = NSStackView(views: [self.titleField, self.subtitleField])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0
        
        self.iconBackground.addSubview(self.iconView)
        [self.iconBackground, self.iconView, text, self.valueField, self.chevron].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        [self.iconBackground, text, self.valueField, self.chevron].forEach { self.addSubview($0) }
        
        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: CompactPortalRow.height),
            
            self.iconBackground.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 6),
            self.iconBackground.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.iconBackground.widthAnchor.constraint(equalToConstant: 28),
            self.iconBackground.heightAnchor.constraint(equalToConstant: 28),
            self.iconView.centerXAnchor.constraint(equalTo: self.iconBackground.centerXAnchor),
            self.iconView.centerYAnchor.constraint(equalTo: self.iconBackground.centerYAnchor),
            self.iconView.widthAnchor.constraint(equalToConstant: 18),
            self.iconView.heightAnchor.constraint(equalToConstant: 18),
            
            text.leadingAnchor.constraint(equalTo: self.iconBackground.trailingAnchor, constant: 10),
            text.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: self.valueField.leadingAnchor, constant: -6),
            
            self.valueField.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.valueField.trailingAnchor.constraint(equalTo: self.chevron.leadingAnchor, constant: -6),
            
            self.chevron.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
            self.chevron.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.chevron.widthAnchor.constraint(equalToConstant: 8)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - values (safe to call from any thread)
    
    public func setValue(_ value: String, subtitle: String? = nil) {
        DispatchQueue.main.async {
            if self.valueField.stringValue != value {
                self.valueField.stringValue = value
            }
            let sub = subtitle ?? ""
            if self.subtitleField.stringValue != sub {
                self.subtitleField.stringValue = sub
            }
            self.subtitleField.isHidden = sub.isEmpty
        }
    }
    
    // Changes the icon. `active` fills the circle with the accent color, like a connected Wi-Fi.
    public func setIcon(symbol: String?, active: Bool = false) {
        self.setIcon(key: symbol.map { "symbol:\($0)" }, active: active) {
            symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        }
    }
    
    public func setIcon(glyph: Glyph, scale: CGFloat = 1, active: Bool = false) {
        self.setIcon(key: "glyph:\(glyph.rawValue)@\(scale)", active: active) { glyph.image(scale: scale) }
    }
    
    // `key` identifies the icon so it's only rebuilt when it actually changes; nil means the module icon
    private func setIcon(key: String?, active: Bool, make: @escaping () -> NSImage?) {
        DispatchQueue.main.async {
            if self.iconKey != key {
                self.iconKey = key
                self.iconView.image = (key == nil ? nil : make()) ?? self.defaultIcon
            }
            if self.active != active {
                self.active = active
                self.updateLayer()
            }
        }
    }
    
    // MARK: - drawing and mouse
    
    public override var wantsUpdateLayer: Bool { true }
    
    public override func updateLayer() {
        self.layer?.backgroundColor = self.highlighted ? NSColor.labelColor.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
        self.iconBackground.layer?.backgroundColor = self.active
            ? NSColor.controlAccentColor.cgColor
            : NSColor.labelColor.withAlphaComponent(0.1).cgColor
        self.iconView.contentTintColor = self.active ? .white : .labelColor
    }
    
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.highlighted = false
    }
    
    public override func updateTrackingAreas() {
        if let area = self.trackingArea {
            self.removeTrackingArea(area)
        }
        let area = NSTrackingArea(rect: self.bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        self.addTrackingArea(area)
        self.trackingArea = area
        super.updateTrackingAreas()
    }
    
    public override func mouseEntered(with event: NSEvent) {
        self.highlighted = true
    }
    
    public override func mouseExited(with event: NSEvent) {
        self.highlighted = false
    }
    
    public override func mouseDown(with event: NSEvent) {}
    
    public override func mouseUp(with event: NSEvent) {
        guard self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return }
        self.highlighted = false
        self.onClick?(self.name)
    }
    
    private static func label(size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.truncatesLastVisibleLine = true
        return field
    }
}

// Latest values for the combined "summary" menu bar icon.
// Modules write into it from their reader callbacks; the icon reads it on the main thread.
public final class CombinedSummary {
    public static let shared = CombinedSummary()
    
    public struct Battery {
        public var level: Double // 0...1
        public var charging: Bool
        public var pluggedIn: Bool
        public init(level: Double, charging: Bool, pluggedIn: Bool) {
            self.level = level; self.charging = charging; self.pluggedIn = pluggedIn
        }
    }
    public struct Memory {
        public var usage: Double // 0...1
        public var pressure: Int // 1 normal, 2 warning, 3 critical
        public init(usage: Double, pressure: Int) {
            self.usage = usage; self.pressure = pressure
        }
    }
    public struct Network {
        public var upload: Int64 // bytes per second
        public var download: Int64
        public var connected: Bool
        public var wifi: Bool
        public init(upload: Int64, download: Int64, connected: Bool, wifi: Bool) {
            self.upload = upload; self.download = download; self.connected = connected; self.wifi = wifi
        }
    }
    public struct Values {
        public var battery: Battery? = nil
        public var cpu: [Double] = [] // recent usage samples, oldest first, 0...1
        public var memory: Memory? = nil
        public var network: Network? = nil
    }
    
    public static let cpuHistoryLength = 10
    
    private let queue = DispatchQueue(label: "eu.exelban.Stats.CombinedSummary")
    private var _values = Values()
    private var notifyScheduled = false
    
    public var values: Values { self.queue.sync { self._values } }
    
    public func update(_ change: (inout Values) -> Void) {
        let notify: Bool = self.queue.sync {
            change(&self._values)
            if self.notifyScheduled { return false }
            self.notifyScheduled = true
            return true
        }
        guard notify else { return }
        // coalesce bursts of updates from several modules into one redraw
        DispatchQueue.main.async {
            self.queue.sync { self.notifyScheduled = false }
            NotificationCenter.default.post(name: .combinedSummaryChanged, object: nil)
        }
    }
    
    public func pushCPU(_ value: Double) {
        self.update { v in
            v.cpu.append(max(0, min(1, value)))
            if v.cpu.count > CombinedSummary.cpuHistoryLength {
                v.cpu.removeFirst(v.cpu.count - CombinedSummary.cpuHistoryLength)
            }
        }
    }
}

// Hand-drawn glyphs that have no public SF Symbol equivalent.
// `draw` paints into the current graphics context; `image` returns a template image
// that tints like an SF Symbol.
public enum Glyph: String {
    case bean      // coffee bean, turned 45° counterclockwise
    case ethernet  // macOS-style  < · · · >
    
    public var size: NSSize {
        switch self {
        case .bean: return NSSize(width: 12, height: 12)
        case .ethernet: return NSSize(width: 17, height: 9)
        }
    }
    
    public func draw(center c: NSPoint, scale: CGFloat = 1, color: NSColor) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: c.x, yBy: c.y)
        t.scale(by: scale)
        t.concat()
        color.setFill()
        color.setStroke()
        
        switch self {
        case .bean:
            // an oval split by an S-shaped seam, low on the left and high on the right
            let rotate = NSAffineTransform()
            rotate.rotate(byDegrees: 45)
            rotate.concat()
            let rx: CGFloat = 6, ry: CGFloat = 4.8
            NSBezierPath(ovalIn: NSRect(x: -rx, y: -ry, width: rx*2, height: ry*2)).fill()
            let seam = NSBezierPath()
            seam.move(to: NSPoint(x: -rx - 1, y: -0.6))
            seam.curve(to: NSPoint(x: rx + 1, y: 0.6), controlPoint1: NSPoint(x: -1.8, y: -2.6), controlPoint2: NSPoint(x: 1.8, y: 2.6))
            seam.lineWidth = 1.3
            seam.lineCapStyle = .round
            ctx.compositingOperation = .destinationOut
            seam.stroke()
        case .ethernet:
            let w: CGFloat = 17, h: CGFloat = 9
            let chevrons = NSBezierPath()
            chevrons.lineWidth = 1.6
            chevrons.lineCapStyle = .round
            chevrons.lineJoinStyle = .round
            chevrons.move(to: NSPoint(x: -w/2 + 3.5, y: h/2))
            chevrons.line(to: NSPoint(x: -w/2 + 0.8, y: 0))
            chevrons.line(to: NSPoint(x: -w/2 + 3.5, y: -h/2))
            chevrons.move(to: NSPoint(x: w/2 - 3.5, y: h/2))
            chevrons.line(to: NSPoint(x: w/2 - 0.8, y: 0))
            chevrons.line(to: NSPoint(x: w/2 - 3.5, y: -h/2))
            chevrons.stroke()
            let d: CGFloat = 2
            for cx in [-3.5, 0, 3.5] as [CGFloat] {
                NSBezierPath(ovalIn: NSRect(x: cx - d/2, y: -d/2, width: d, height: d)).fill()
            }
        }
        ctx.restoreGraphicsState()
    }
    
    public func image(scale: CGFloat = 1) -> NSImage {
        let size = NSSize(width: self.size.width * scale, height: self.size.height * scale)
        let image = NSImage(size: size, flipped: false) { rect in
            self.draw(center: NSPoint(x: rect.midX, y: rect.midY), scale: scale, color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }
}
