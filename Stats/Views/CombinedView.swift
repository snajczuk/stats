//
//  CombinedView.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 09/01/2023
//  Using Swift 5.0
//  Running on macOS 13.1
//
//  Copyright © 2023 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit
import IOKit.pwr_mgt

internal class CombinedView: NSObject, NSGestureRecognizerDelegate {
    private var menuBarItem: NSStatusItem? = nil
    private var view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: Constants.Widget.height))
    private var popup: PopupWindow? = nil
    private var popupView: Popup? = nil
    // menu bar item the popup was last opened under
    private weak var popupAnchor: NSWindow? = nil
    // the "Summary items" style shows one menu bar item per group instead of the single combined item
    private var summaryItems: [SummaryStatusItem] = []
    // the single-item summary styles (bars, rings, dial)
    private let summary: CombinedSummaryWidget = CombinedSummaryWidget()
    
    private var status: Bool {
        Store.shared.bool(key: "CombinedModules", defaultValue: false) && !Store.shared.bool(key: "pause", defaultValue: false)
    }
    private var iconSymbol: String {
        Store.shared.string(key: "CombinedModules_iconSymbol", defaultValue: "app")
    }
    private var spacing: CGFloat {
        CGFloat(Int(Store.shared.string(key: "CombinedModules_spacing", defaultValue: "")) ?? 0)
    }
    private var separator: Bool {
        Store.shared.bool(key: "CombinedModules_separator", defaultValue: false)
    }
    private var summaryMode: Bool {
        CombinedModulesWidget.current == .summary
    }
    
    private var activeModules: [Module] {
        modules.filter({ $0.enabled }).sorted(by: { $0.combinedPosition < $1.combinedPosition })
    }
    
    private var combinedModulesPopup: Bool {
        get { Store.shared.bool(key: "CombinedModules_popup", defaultValue: true) }
        set { Store.shared.set(key: "CombinedModules_popup", value: newValue) }
    }
    
    override init() {
        super.init()
        
        modules.forEach { (m: Module) in
            m.menuBar.callback = { [weak self] in
                if let s = self?.status, s {
                    DispatchQueue.main.async(execute: {
                        self?.recalculate()
                    })
                }
            }
            m.summaryCallback = { [weak self] module, value in
                guard let self else { return }
                self.summary.setValue(for: module, with: value)
                guard self.status, CombinedModulesWidget.current.isSummaryWidget else { return }
                self.updateSummary()
            }
        }
        
        let popupView = Popup()
        popupView.openModule = { [weak self] name in
            self?.openModuleFromList(name)
        }
        self.popupView = popupView
        self.popup = PopupWindow(title: "Combined modules", module: .combined, view: popupView) { _ in }
        
        if self.status {
            self.enable()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(listenForStateChange), name: .toggleOneView, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(listenForStateChange), name: .pause, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(listenForModuleRearrrange), name: .moduleRearrange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(listenForModuleToggle), name: .toggleModule, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .toggleOneView, object: nil)
        NotificationCenter.default.removeObserver(self, name: .pause, object: nil)
        NotificationCenter.default.removeObserver(self, name: .moduleRearrange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .toggleModule, object: nil)
    }
    
    public func enable() {
        if self.summaryMode {
            self.enableSummary()
            DispatchQueue.main.async(execute: {
                self.recalculate()
            })
            return
        }
        guard self.menuBarItem == nil else { return }
        
        self.menuBarItem = NSStatusBar.system.statusItem(withLength: 0)
        DispatchQueue.main.async(execute: {
            self.menuBarItem?.autosaveName = "CombinedModules"
        })
        self.menuBarItem?.button?.addSubview(self.view)
        self.menuBarItem?.button?.image = NSImage()
        self.menuBarItem?.button?.toolTip = localizedString("Combined modules")
        
        self.menuBarItem?.button?.target = self
        self.menuBarItem?.button?.action = #selector(self.handleClick)
        self.menuBarItem?.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        
        DispatchQueue.main.async(execute: {
            self.recalculate()
        })
    }
    
    public func disable() {
        KeepAwake.shared.summaryShowsIndicator = false
        self.popup?.setIsVisible(false)
        if let item = self.menuBarItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.menuBarItem = nil
        self.disableSummary()
    }
    
    // Status items are placed to the left of the ones created before them,
    // so create them right to left: network, CPU/RAM, battery, clock.
    private func enableSummary() {
        guard self.summaryItems.isEmpty else { return }
        self.summaryItems = SummaryIconView.Group.allCases.reversed().map { group in
            let item = SummaryStatusItem(group: group)
            item.onClick = { [weak self] window in
                self?.togglePopup(anchor: window, group: group)
            }
            return item
        }
    }
    
    private func disableSummary() {
        self.summaryItems.forEach({ $0.remove() })
        self.summaryItems = []
    }
    
    private func recalculate() {
        // the battery item draws the bean itself, so Keep Awake doesn't need its own item
        KeepAwake.shared.summaryShowsIndicator = self.status && !self.summaryItems.isEmpty
        guard self.status else { return }
        
        // switching between the summary style and the others swaps which menu bar items exist
        if self.summaryMode {
            if let item = self.menuBarItem {
                self.popup?.setIsVisible(false)
                NSStatusBar.system.removeStatusItem(item)
                self.menuBarItem = nil
            }
            self.enableSummary()
            KeepAwake.shared.summaryShowsIndicator = true
            let names = Set(modules.filter({ $0.enabled }).map({ $0.name }))
            self.summaryItems.forEach({ $0.setSegments(names) })
            return
        } else if !self.summaryItems.isEmpty {
            self.popup?.setIsVisible(false)
            self.disableSummary()
            KeepAwake.shared.summaryShowsIndicator = false
            self.enable()
            return
        }
        
        guard self.menuBarItem != nil else { return }
        self.view.subviews.forEach({ $0.removeFromSuperview() })
        self.menuBarItem?.button?.toolTip = localizedString("Combined modules")
        self.menuBarItem?.button?.setAccessibilityLabel(localizedString("Combined modules"))
        
        if CombinedModulesWidget.current.isSummaryWidget {
            self.updateSummary()
            return
        }
        
        if CombinedModulesWidget.current == .icon {
            self.view.addSubview(AppIcon(symbol: self.iconSymbol))
            self.view.setFrameSize(NSSize(width: AppIcon.size.width, height: self.view.frame.height))
            self.menuBarItem?.length = AppIcon.size.width
            return
        }
        
        let visibleModules = self.activeModules.filter({ !$0.menuBar.activeWidgets.isEmpty })
        var w: CGFloat = 0
        visibleModules.enumerated().forEach { (i, m) in
            if i != 0 {
                w += self.spacing
                if self.separator {
                    self.view.addSubview(SeparatorLineView(frame: NSRect(x: w, y: 3, width: 1, height: Constants.Widget.height-6)))
                    w += 3 + self.spacing
                }
            }
            self.view.addSubview(m.menuBar.view)
            m.menuBar.view.setFrameOrigin(NSPoint(x: w, y: 0))
            w += m.menuBar.view.frame.width
        }
        self.view.setFrameSize(NSSize(width: w, height: self.view.frame.height))
        self.menuBarItem?.length = w
    }
    
    private func updateSummary() {
        guard self.menuBarItem != nil else { return }
        let list = self.activeModules.filter({ $0.config.hasSummary })
        
        if list.isEmpty {
            self.view.subviews.forEach({ $0.removeFromSuperview() })
            self.view.addSubview(AppIcon())
            self.view.setFrameSize(NSSize(width: AppIcon.size.width, height: self.view.frame.height))
            self.menuBarItem?.length = AppIcon.size.width
            self.menuBarItem?.button?.toolTip = localizedString("Combined modules")
            self.menuBarItem?.button?.setAccessibilityLabel(localizedString("Combined modules"))
            return
        }
        
        if self.summary.superview == nil {
            self.view.subviews.forEach({ $0.removeFromSuperview() })
            self.view.addSubview(self.summary)
        }
        
        self.summary.update(list)
        self.view.setFrameSize(self.summary.frame.size)
        self.menuBarItem?.length = self.summary.frame.width
        
        self.menuBarItem?.button?.toolTip = self.summary.toolTip
        self.menuBarItem?.button?.setAccessibilityLabel(self.summary.toolTip)
    }
    
    // call when popup appear/disappear
    private func visibilityCallback(_ state: Bool) {}
    
    @objc private func handleClick() {
        if CombinedModulesWidget.current != .widgets || self.combinedModulesPopup {
            if let window = self.menuBarItem?.button?.window {
                self.togglePopup(anchor: window)
            }
        } else {
            self.openModulePopup()
        }
    }
    
    private func openModulePopup() {
        guard let window = self.menuBarItem?.button?.window else { return }
        let location = self.view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let visibleModules = self.activeModules.filter({ !$0.menuBar.activeWidgets.isEmpty })
        guard let module = visibleModules.last(where: { $0.menuBar.view.frame.minX <= location.x }) ?? visibleModules.first else { return }
        
        var userInfo: [String: Any] = [
            "module": module.name,
            "origin": window.frame.origin,
            "center": window.frame.width/2
        ]
        let widgetLocation = module.menuBar.view.convert(location, from: self.view)
        let widgets = module.menuBar.activeWidgets
        if let widget = widgets.last(where: { $0.item.frame.minX <= widgetLocation.x }) ?? widgets.first {
            userInfo["widget"] = widget.type
        }
        NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: userInfo)
    }
    
    // opens a module's own popup under the combined menu bar item (used by the compact list)
    private func openModuleFromList(_ name: String) {
        guard let window = self.popupAnchor ?? self.menuBarItem?.button?.window else { return }
        self.popup?.setIsVisible(false)
        NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: [
            "module": name,
            "origin": window.frame.origin,
            "center": window.frame.width/2
        ])
    }
    
    // shows the popup under the given menu bar item; clicking the same item again hides it,
    // clicking another one moves it there
    // group: limit the popup to one summary item's modules (nil shows them all)
    private func togglePopup(anchor window: NSWindow, group: SummaryIconView.Group? = nil) {
        guard let popup = self.popup else { return }
        
        let hidden = popup.occlusionState.rawValue == 8192
        if hidden || self.popupAnchor !== window {
            self.popupAnchor = window
            self.popupView?.group = group
            popup.contentView?.invalidateIntrinsicContentSize()
            
            let windowCenter = popup.contentView!.intrinsicContentSize.width / 2
            var x = window.frame.origin.x - windowCenter + window.frame.width/2
            let y = window.frame.origin.y - popup.contentView!.intrinsicContentSize.height - 3
            
            let buttonPoint = NSPoint(x: window.frame.midX, y: window.frame.midY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonPoint) }) ?? NSScreen.main {
                if x + popup.contentView!.intrinsicContentSize.width > screen.frame.maxX {
                    x = screen.frame.maxX - popup.contentView!.intrinsicContentSize.width - 3
                }
                if x < screen.frame.minX {
                    x = screen.frame.minX + 3
                }
            }
            
            popup.setFrameOrigin(NSPoint(x: x, y: y))
            popup.orderFrontRegardless()
            popup.makeKey()
        } else {
            popup.setIsVisible(false)
        }
    }
    
    @objc private func listenForStateChange(_ notification: Notification) {
        guard notification.userInfo?["module"] == nil else { return }
        
        if self.status {
            self.enable()
        } else {
            self.disable()
        }
    }
    
    @objc private func listenForModuleRearrrange() {
        self.recalculate()
    }
    
    // the summary icon shows one segment per enabled module; wait for the module to finish toggling
    @objc private func listenForModuleToggle() {
        DispatchQueue.main.async { self.recalculate() }
    }
}

private class CombinedSummaryWidget: NSView {
    private var values: [(ModuleType, Double?)] = []
    
    private var color: NSColor { self.isDarkMode ? .white : .black }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        switch CombinedModulesWidget.current {
        case .rings: self.drawRings()
        case .dial: self.drawDial()
        default: self.drawBars()
        }
    }
    
    private func color(for value: Double?, moduleType: ModuleType) -> NSColor {
        guard let value else { return self.color }
        return (moduleType == .battery ? value < 0.1 : value > 0.9) ? .systemRed : self.color
    }
    
    private func drawBars() {
        let height: CGFloat = min(16, self.bounds.height - 4)
        let width = CGFloat(self.values.count) * 6 - 2
        let origin = ((self.bounds.width - width) / 2).rounded()
        let y = ((self.bounds.height - height) / 2).rounded()
        
        for (i, (module, value)) in self.values.enumerated() {
            let color = self.color(for: value, moduleType: module)
            let rect = NSRect(x: origin + CGFloat(i) * 6, y: y, width: 4, height: height)
            let track = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            color.withAlphaComponent(0.25).setFill()
            track.fill()
            
            if let value, value > 0 {
                let fill = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: height * CGFloat(value))
                NSGraphicsContext.saveGraphicsState()
                track.addClip()
                color.setFill()
                NSBezierPath(rect: fill).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
    
    private func drawRings() {
        guard !self.values.isEmpty else { return }
        let diameter = min(20, self.bounds.height - 2)
        let spacing = min(3, diameter / (CGFloat(self.values.count) * 2))
        let lineWidth = spacing - 0.5
        let center = NSPoint(x: self.bounds.midX, y: self.bounds.midY)
        
        for (i, (module, value)) in self.values.enumerated() {
            let color = self.color(for: value, moduleType: module)
            let radius = (diameter - lineWidth) / 2 - CGFloat(i) * spacing
            let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            track.lineWidth = lineWidth
            color.withAlphaComponent(0.25).setStroke()
            track.stroke()
            
            if let value, value > 0 {
                color.setStroke()
                if value == 1 {
                    track.stroke()
                } else {
                    let fill = NSBezierPath()
                    fill.lineWidth = lineWidth
                    fill.lineCapStyle = .round
                    fill.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - CGFloat(value) * 360, clockwise: true)
                    fill.stroke()
                }
            }
        }
    }
    
    private func drawDial() {
        guard !self.values.isEmpty else { return }
        let lineWidth: CGFloat = 2.5
        let radius = (min(20, self.bounds.height - 2) - lineWidth) / 2
        let center = NSPoint(x: self.bounds.midX, y: self.bounds.midY)
        let segment = 360 / CGFloat(self.values.count)
        let gap: CGFloat = self.values.count > 1 ? 32 : 0
        
        for (i, (module, value)) in self.values.enumerated() {
            let color = self.color(for: value, moduleType: module)
            let start = 90 - CGFloat(i) * segment - gap / 2
            let length = segment - gap
            let track = NSBezierPath()
            track.lineWidth = lineWidth
            track.lineCapStyle = .round
            track.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - length, clockwise: true)
            color.withAlphaComponent(0.25).setStroke()
            track.stroke()
            
            if let value, value > 0 {
                let fill = NSBezierPath()
                fill.lineWidth = lineWidth
                fill.lineCapStyle = .round
                fill.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - length * CGFloat(value), clockwise: true)
                color.setStroke()
                fill.stroke()
            }
        }
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    
    fileprivate func setValue(for module: ModuleType, with value: Double?) {
        let value = value.flatMap({ $0.isFinite ? min(max($0, 0), 1) : nil })
        if let index = self.values.firstIndex(where: { $0.0 == module }) {
            self.values[index].1 = value
        } else {
            self.values.append((module, value))
        }
    }
    
    fileprivate func update(_ list: [Module]) {
        self.values = list.map { module in
            (module.moduleType, self.values.first(where: { $0.0 == module.moduleType })?.1)
        }
        let width: CGFloat = CombinedModulesWidget.current == .bars ? max(22, CGFloat(self.values.count) * 6 + 2) : 22
        self.setFrameSize(NSSize(width: width, height: Constants.Widget.height))
        self.toolTip = list.map { module in
            let value = self.values.first(where: { $0.0 == module.moduleType })?.1.map({ "\(Int($0 * 100))%" }) ?? localizedString("Unknown")
            return "\(localizedString(module.name)): \(value)"
        }.joined(separator: "\n")
        self.needsDisplay = true
    }
}

private class SeparatorLineView: NSView {
    override var wantsUpdateLayer: Bool { true }
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayer() {
        self.layer?.backgroundColor = (self.isDarkMode ? NSColor.white : NSColor.black).cgColor
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }
}

private class Popup: NSStackView, Popup_p {
    fileprivate var keyboardShortcut: [UInt16] = []
    fileprivate var sizeCallback: ((NSSize) -> Void)? = nil
    fileprivate var openModule: ((String) -> Void)? = nil
    // when set, only this summary group's modules are listed
    fileprivate var group: SummaryIconView.Group? = nil {
        didSet {
            if oldValue != self.group { self.reinit() }
        }
    }
    
    private func included(_ m: Module) -> Bool {
        guard let group = self.group else { return true }
        return group.modules.contains(m.name)
    }
    
    // summary items' dropdowns are always compact; that's where their inline details live
    private var compactList: Bool {
        self.group != nil || Store.shared.bool(key: "CombinedModules_compact", defaultValue: false)
    }
    
    init() {
        self.keyboardShortcut = Store.shared.array(key: "CombinedModules_popup_keyboardShortcut", defaultValue: []) as? [UInt16] ?? []
        
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        
        self.orientation = .vertical
        self.distribution = .fill
        self.alignment = .width
        self.spacing = Constants.Popup.spacing*3
        
        self.reinit()
        
        NotificationCenter.default.addObserver(self, selector: #selector(reinit), name: .toggleModule, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reinit), name: .combinedModulesPopup, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    fileprivate func settings() -> NSView? { return nil }
    // the inline details only redraw while visible, so catch them up on open
    fileprivate func appear() {
        self.detailBoxes.forEach({ $0.details.appear() })
    }
    fileprivate func disappear() {
        self.detailBoxes.forEach({ $0.details.disappear() })
    }
    
    private var detailBoxes: [DetailsBox] {
        self.arrangedSubviews.compactMap({ $0 as? DetailsBox })
    }
    fileprivate func setKeyboardShortcut(_ binding: [UInt16]) {
        self.keyboardShortcut = binding
        Store.shared.set(key: "CombinedModules_popup_keyboardShortcut", value: binding)
    }
    
    @objc private func reinit() {
        self.subviews.forEach({ $0.removeFromSuperview() })
        
        if self.compactList {
            self.reinitCompact()
            return
        }
        self.spacing = Constants.Popup.spacing*3

        let availableModules = modules.filter({ $0.enabled && $0.portal != nil && self.included($0) })
        var modulesHeight: CGFloat = 0
        availableModules.forEach { (m: Module) in
            if let p = m.portal {
                modulesHeight += p.height
                self.addArrangedSubview(p)
                p.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
            }
        }

        let footer = self.footer()
        self.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true

        // panels and footer, with stack spacing between each of them
        let h = modulesHeight + footer.frame.height + (CGFloat(availableModules.count)*self.spacing)
        self.setFrameSize(NSSize(width: self.frame.width, height: h))
        self.sizeCallback?(self.frame.size)
    }
    
    // one row per module, like the macOS Control Center list
    private func reinitCompact() {
        self.spacing = 0
        
        var h: CGFloat = 0
        let list = modules.filter({ $0.enabled && $0.compactSupported && self.included($0) })
        list.forEach { m in
            let row = m.compact
            // in a summary item's dropdown the details are already shown, so the row isn't a link
            row.interactive = self.group == nil
            row.onClick = { [weak self] name in
                self?.openModule?(name)
            }
            self.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
            h += CompactPortalRow.height
            
            // a summary item's dropdown also shows the module's key metrics under its row
            if self.group != nil, let details = m.compactDetails {
                let box = DetailsBox(details)
                details.sizeCallback = { [weak self] _ in
                    DispatchQueue.main.async { self?.relayout() }
                }
                self.addArrangedSubview(box)
                box.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
                h += box.height
            }
        }
        
        let footer = self.footer()
        self.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
        
        h += footer.frame.height
        self.setFrameSize(NSSize(width: self.frame.width, height: h))
        self.sizeCallback?(self.frame.size)
    }
    
    // a details section changed height (e.g. Wi-Fi rows appearing): resize without rebuilding
    private func relayout() {
        guard self.compactList, !self.detailBoxes.isEmpty else { return }
        var h: CGFloat = 0
        self.arrangedSubviews.forEach { v in
            if v is CompactPortalRow {
                h += CompactPortalRow.height
            } else if let box = v as? DetailsBox {
                box.sync()
                h += box.height
            } else {
                h += v.frame.height
            }
        }
        if h != self.frame.height {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }
    
    // a thin line inset from the edges, inside its own full-width container
    private func separatorLine() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(line)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }
    
    // keep awake controls, then text actions at the bottom, like a native menu
    private func footer() -> NSView {
        let separator = self.separatorLine()
        let settings = MenuTextRow(localizedString("Stats Settings…")) { [weak self] in
            self?.window?.setIsVisible(false)
            // from a summary item, open that item's module page
            let page = self?.group?.settingsModule ?? "Combined modules"
            NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": page])
        }
        let activity = MenuTextRow(localizedString("Open Activity Monitor…")) { [weak self] in
            self?.window?.setIsVisible(false)
            // Activity Monitor opens on the tab saved in its preferences, so pick the matching one
            // first. This only takes effect when Activity Monitor isn't already running.
            if let tab = self?.group?.activityMonitorTab {
                let app = "com.apple.ActivityMonitor" as CFString
                CFPreferencesSetAppValue("SelectedTab" as CFString, tab as CFNumber, app)
                CFPreferencesAppSynchronize(app)
            }
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
                NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        
        // Keep Awake lives with the battery, so the other summary items leave it out
        let keepAwake = self.group == nil || self.group == .power
        
        let view = NSStackView(views: [separator])
        view.orientation = .vertical
        view.alignment = .width
        view.spacing = 0
        view.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 0, right: 0)
        view.setCustomSpacing(6, after: separator)
        var h: CGFloat = 6 + 1 + 6 + MenuTextRow.height * 2
        if keepAwake {
            let awake = KeepAwakeRow()
            let screen = KeepScreenRow()
            let separator2 = self.separatorLine()
            [awake, screen, separator2].forEach({ view.addArrangedSubview($0) })
            view.setCustomSpacing(6, after: screen)
            view.setCustomSpacing(6, after: separator2)
            h += KeepAwakeRow.height + KeepScreenRow.height + 6 + 1 + 6
        }
        view.addArrangedSubview(settings)
        view.addArrangedSubview(activity)

        view.setFrameSize(NSSize(width: self.frame.width, height: h))
        view.heightAnchor.constraint(equalToConstant: h).isActive = true
        return view
    }
}

// Holds a module's inline details under its compact row, sized to the details' own height.
private class DetailsBox: NSView {
    static let bottomGap: CGFloat = 6
    
    let details: PopupWrapper
    private var heightConstraint: NSLayoutConstraint? = nil
    
    var height: CGFloat { self.details.frame.height + DetailsBox.bottomGap }
    
    init(_ details: PopupWrapper) {
        self.details = details
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        
        details.removeFromSuperview()
        details.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(details)
        NSLayoutConstraint.activate([
            details.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            details.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            details.topAnchor.constraint(equalTo: self.topAnchor)
        ])
        let c = self.heightAnchor.constraint(equalToConstant: self.height)
        c.isActive = true
        self.heightConstraint = c
        self.setFrameSize(NSSize(width: self.frame.width, height: self.height))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func sync() {
        self.heightConstraint?.constant = self.height
    }
}

// A plain text action in the combined popup, styled like a menu item with a hover highlight.
private class MenuTextRow: NSView {
    static let height: CGFloat = 26
    
    private let action: () -> Void
    private var highlighted: Bool = false {
        didSet { self.needsDisplay = true }
    }
    private var trackingArea: NSTrackingArea? = nil
    
    init(_ title: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: MenuTextRow.height))
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(label)
        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: MenuTextRow.height),
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        self.layer?.backgroundColor = self.highlighted ? NSColor.labelColor.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.highlighted = false
    }
    
    override func updateTrackingAreas() {
        if let area = self.trackingArea { self.removeTrackingArea(area) }
        let area = NSTrackingArea(rect: self.bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        self.addTrackingArea(area)
        self.trackingArea = area
        super.updateTrackingAreas()
    }
    
    override func mouseEntered(with event: NSEvent) { self.highlighted = true }
    override func mouseExited(with event: NSEvent) { self.highlighted = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return }
        self.highlighted = false
        self.action()
    }
}

// One menu bar item of the summary style. It draws one group of segments and
// hides itself (zero width) when that group has nothing to show.
private final class SummaryStatusItem: NSObject {
    var onClick: ((NSWindow) -> Void)? = nil
    
    private let item: NSStatusItem
    private let icon: SummaryIconView
    
    init(group: SummaryIconView.Group) {
        self.item = NSStatusBar.system.statusItem(withLength: 0)
        self.icon = SummaryIconView(groups: [group])
        super.init()
        
        DispatchQueue.main.async(execute: {
            self.item.autosaveName = "CombinedModules_\(group.rawValue)"
        })
        self.item.button?.image = NSImage()
        self.item.button?.addSubview(self.icon)
        self.item.button?.toolTip = localizedString(group.title)
        self.item.button?.target = self
        self.item.button?.action = #selector(self.handleClick)
        self.item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        
        self.icon.setFrameOrigin(.zero)
        self.icon.widthChanged = { [weak self] in self?.syncLength() }
    }
    
    func setSegments(_ names: Set<String>) {
        self.icon.setSegments(names)
        self.syncLength()
    }
    
    func remove() {
        NSStatusBar.system.removeStatusItem(self.item)
    }
    
    private func syncLength() {
        self.item.length = self.icon.frame.width
    }
    
    @objc private func handleClick() {
        guard let window = self.item.button?.window else { return }
        self.onClick?(window)
    }
}

// Summary icon: clock, battery bar, CPU history bars, RAM pressure squares,
// connection icon and upload/download activity dots. Each menu bar item shows one
// group of these. A segment is drawn only while its module is turned on.
internal class SummaryIconView: NSView {
    // which segments go in the same menu bar item, in left-to-right order
    enum Group: String, CaseIterable {
        case clock, power, compute, network
        
        var title: String {
            switch self {
            case .clock: return "Clock"
            case .power: return "Battery"
            case .compute: return "CPU and memory"
            case .network: return "Network"
            }
        }
        
        // settings page for "Stats Settings…"
        var settingsModule: String {
            switch self {
            case .clock: return "Clock"
            case .power: return "Battery"
            case .compute: return "CPU"
            case .network: return "Network"
            }
        }
        
        // Activity Monitor tab for "Open Activity Monitor…": 0 CPU, 2 Energy, 4 Network
        var activityMonitorTab: Int? {
            switch self {
            case .power: return 2
            case .compute: return 0
            case .network: return 4
            case .clock: return nil
            }
        }
        
        // module names whose stats this group shows
        var modules: Set<String> {
            switch self {
            case .clock: return ["Clock"]
            case .power: return ["Battery"]
            case .compute: return ["CPU", "RAM"]
            case .network: return ["Network"]
            }
        }
    }
    
    var widthChanged: (() -> Void)? = nil
    
    private let groups: Set<Group>
    private var segments: Set<String> = []
    private var timer: Timer? = nil
    private var clockText: String = ""
    private var symbolCache: [String: NSImage] = [:]
    private var shrinkSince: Date? = nil
    private let shrinkDelay: TimeInterval = 3
    
    private let gap: CGFloat = 8         // between segments
    private let iconGap: CGFloat = 3     // between a symbol and its graphic
    private let wifiPointSize: CGFloat = 15 // matches the size of the system Wi-Fi icon
    private let wifiLift: CGFloat = 1       // and its vertical position
    private let clockFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    private let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        // follow the 12/24-hour preference, but drop AM/PM like the iPhone status bar
        let format = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "H:mm"
        f.dateFormat = format.replacingOccurrences(of: "a", with: "").trimmingCharacters(in: .whitespaces)
        return f
    }()
    
    init(groups: Set<Group> = Set(Group.allCases)) {
        self.groups = groups
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Constants.Widget.height))
        self.clockText = self.clockFormatter.string(from: Date())
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.refresh), name: .combinedSummaryChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.refresh), name: .keepAwakeChanged, object: nil)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // let clicks fall through to the status bar button underneath
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    
    func setSegments(_ names: Set<String>) {
        self.segments = names
        self.contentKey = nil
        self.updateWidth()
    }
    
    private func shows(_ group: Group, _ module: String) -> Bool {
        self.groups.contains(group) && self.segments.contains(module)
    }
    
    @objc private func refresh() {
        self.updateWidth() // speeds change the width
    }
    
    private func tick() {
        let text = self.clockFormatter.string(from: Date())
        if text != self.clockText {
            self.clockText = text
        }
        self.updateWidth() // also applies a pending shrink once it has waited long enough
    }
    
    // Everything this icon draws, as text. Updates arrive several times a second from all
    // modules (and the clock ticks every second), but most don't change what a given icon
    // shows; comparing this skips the measuring and redrawing for those.
    private var contentKey: String? = nil
    private func currentContentKey() -> String {
        let values = CombinedSummary.shared.values
        var key = ""
        if self.shows(.clock, "Clock") {
            key += "c\(self.clockText)|"
        }
        if self.groups.contains(.power) {
            key += "k\(KeepAwake.shared.isActive)|"
        }
        if self.shows(.power, "Battery"), let b = values.battery {
            key += "b\(Int(b.level * 100)),\(b.pluggedIn),\(b.charging)|"
        }
        if self.shows(.compute, "CPU") {
            key += "u" + values.cpu.map({ String(Int($0 * 100)) }).joined(separator: ",") + "|"
        }
        if self.shows(.compute, "RAM") {
            key += "m\(values.memory?.pressure ?? 0)|"
        }
        if self.shows(.network, "Network"), let n = values.network {
            key += "n\(n.connected),\(n.wifi),\(n.wifiStrength),\(SummaryIconView.litDots(n.upload)),\(SummaryIconView.litDots(n.download))|"
        }
        return key
    }
    
    // how many of the 4 speed dots to light, like signal bars, each step about ten times
    // faster than the last
    private static func litDots(_ bytes: Int64) -> Int {
        switch bytes {
        case ..<1_000: return 0
        case ..<100_000: return 1
        case ..<1_000_000: return 2
        case ..<10_000_000: return 3
        default: return 4
        }
    }
    
    // Fit the content tightly. Grow right away; shrink only after the content has stayed
    // narrower for a few seconds, so fluctuating speeds don't make the menu bar jitter.
    private func updateWidth() {
        let key = self.currentContentKey()
        let changed = key != self.contentKey
        // nothing new to show and no shrink waiting to happen
        guard changed || self.shrinkSince != nil || self.frame.width == 0 else { return }
        self.contentKey = key
        
        let w = self.layout(draw: false)
        let current = self.frame.width
        var apply = w > current || current == 0
        if w < current {
            if let since = self.shrinkSince {
                apply = Date().timeIntervalSince(since) >= self.shrinkDelay
            } else {
                self.shrinkSince = Date()
            }
        } else {
            self.shrinkSince = nil
        }
        if apply && w != current {
            self.shrinkSince = nil
            self.setFrameSize(NSSize(width: w, height: Constants.Widget.height))
            self.widthChanged?()
        }
        if changed {
            self.needsDisplay = true
        }
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.symbolCache.removeAll()
        self.needsDisplay = true
    }
    
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        self.symbolCache.removeAll() // cached at the screen's pixel density
        self.needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        _ = self.layout(draw: true)
    }
    
    // MARK: - layout and drawing (one pass; `draw: false` only measures)
    
    private var isDark: Bool {
        self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    private var green: NSColor { self.isDark ? NSColor(red: 0.42, green: 0.83, blue: 0.36, alpha: 1) : NSColor(red: 0.12, green: 0.55, blue: 0.24, alpha: 1) }
    private var blue: NSColor { self.isDark ? NSColor(red: 0.36, green: 0.65, blue: 1.0, alpha: 1) : NSColor(red: 0.12, green: 0.42, blue: 0.82, alpha: 1) }
    private var yellow: NSColor { self.isDark ? NSColor(red: 1.0, green: 0.84, blue: 0.04, alpha: 1) : NSColor(red: 0.72, green: 0.56, blue: 0.0, alpha: 1) }
    private var red: NSColor { self.isDark ? NSColor(red: 1.0, green: 0.36, blue: 0.33, alpha: 1) : NSColor(red: 0.80, green: 0.15, blue: 0.13, alpha: 1) }
    private var track: NSColor { self.isDark ? NSColor.white.withAlphaComponent(0.3) : NSColor.black.withAlphaComponent(0.22) }
    private var ink: NSColor { self.isDark ? .white : .black }
    
    private func layout(draw: Bool) -> CGFloat {
        let values = CombinedSummary.shared.values
        let height = Constants.Widget.height
        let midY = height / 2
        let content = height - 4 // usable height, leaving 2pt above and below
        var x: CGFloat = 0
        var first = true
        
        func startSegment() {
            if !first { x += self.gap }
            first = false
        }
        func text(_ string: String, font: NSFont, at x: CGFloat, y: CGFloat? = nil) -> CGFloat {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: self.ink]
            let size = (string as NSString).size(withAttributes: attrs)
            if draw {
                (string as NSString).draw(at: NSPoint(x: x, y: y ?? (midY - size.height/2)), withAttributes: attrs)
            }
            return ceil(size.width)
        }
        
        // clock
        if self.shows(.clock, "Clock") {
            startSegment()
            x += text(self.clockText, font: self.clockFont, at: x)
        }
        
        // keep awake: coffee bean, sitting right next to the battery
        var beanDrawn = false
        if self.groups.contains(.power) && KeepAwake.shared.isActive {
            startSegment()
            x += self.glyph(.bean, x: x, draw: draw)
            beanDrawn = true
        }
        
        // battery: pill bar, with a bolt cut into it when plugged in
        if self.shows(.power, "Battery") {
            if beanDrawn {
                x += 4 // pair the bean with the battery instead of a full segment gap
            } else {
                startSegment()
            }
            let battery = values.battery
            let plugged = battery?.pluggedIn ?? false
            let level = CGFloat(battery?.level ?? 0)
            // green unless the battery is nearly empty
            let color = level <= 0.10 ? self.red : self.green
            let w: CGFloat = 28, h: CGFloat = 9
            if draw {
                let rect = NSRect(x: x, y: midY - h/2, width: w, height: h)
                self.track.setFill()
                NSBezierPath(roundedRect: rect, xRadius: h/2, yRadius: h/2).fill()
                if level > 0 {
                    color.setFill()
                    let fill = NSRect(x: x, y: rect.minY, width: max(h, w * level), height: h)
                    NSBezierPath(roundedRect: fill, xRadius: h/2, yRadius: h/2).fill()
                }
                if plugged {
                    // bolt while charging; plug when on power but not charging (full, or on hold)
                    if battery?.charging ?? false {
                        self.drawBadge("bolt.fill", scale: 1.4, in: rect)
                    } else {
                        // turned upright (prongs up); slightly smaller since it's long
                        self.drawBadge("powerplug.fill", scale: 1.0, rotation: 90, in: rect)
                    }
                }
            }
            x += w
        }
        
        // CPU: history bars, newest on the right, colored by load
        if self.shows(.compute, "CPU") {
            startSegment()
            let count = CombinedSummary.cpuHistoryLength, w: CGFloat = 2, spacing: CGFloat = 1.5
            let maxH: CGFloat = content - 2, minH: CGFloat = 2
            let history = values.cpu
            for i in 0..<count {
                // pad on the left until enough samples arrive
                let idx = i - (count - history.count)
                let v = idx >= 0 ? history[idx] : 0
                if draw {
                    let h = minH + (maxH - minH) * CGFloat(v)
                    var color = self.track
                    if idx >= 0 {
                        color = v >= 0.8 ? self.red : (v >= 0.5 ? self.yellow : self.blue)
                    }
                    color.setFill()
                    NSBezierPath(roundedRect: NSRect(x: x, y: midY - maxH/2, width: w, height: h), xRadius: w/2, yRadius: w/2).fill()
                }
                x += w + (i < count-1 ? spacing : 0)
            }
        }
        
        // RAM: three squares for pressure (normal, warning, critical)
        if self.shows(.compute, "RAM") {
            startSegment()
            let filled = values.memory?.pressure ?? 0
            let size: CGFloat = 7, spacing: CGFloat = 2
            let fill = filled >= 3 ? self.red : filled == 2 ? self.yellow : self.green
            for i in 0..<3 {
                if draw {
                    (i < filled ? fill : self.track).setFill()
                    NSBezierPath(roundedRect: NSRect(x: x, y: midY - size/2, width: size, height: size), xRadius: 2, yRadius: 2).fill()
                }
                x += size + (i < 2 ? spacing : 0)
            }
        }
        
        // network: connection icon + upload/download speeds stacked
        if self.shows(.network, "Network") {
            startSegment()
            let net = values.network
            if let net, !net.connected {
                x += self.symbol("wifi.slash", pointSize: self.wifiPointSize, lift: self.wifiLift, x: x, draw: draw)
            } else if let net, !net.wifi {
                x += self.glyph(.ethernet, x: x, draw: draw)
            } else {
                x += self.symbol("wifi", variableValue: net?.wifiStrength ?? 1, pointSize: self.wifiPointSize, lift: self.wifiLift, x: x, draw: draw)
            }
            x += self.iconGap + 1
            
            // two rows (upload on top, download below): a small arrow, then 4 dots that
            // light up like signal bars
            let aw: CGFloat = 5, ah: CGFloat = 4, d: CGFloat = 3.5, dotGap: CGFloat = 1.5
            let rowOffset: CGFloat = 3.5 // distance of each row's center from the middle
            if draw {
                for (bytes, isUp) in [(net?.upload ?? 0, true), (net?.download ?? 0, false)] {
                    let cy = isUp ? midY + rowOffset : midY - rowOffset
                    
                    self.ink.setFill()
                    let arrow = NSBezierPath()
                    let tip: CGFloat = isUp ? ah/2 : -ah/2
                    arrow.move(to: NSPoint(x: x, y: cy - tip))
                    arrow.line(to: NSPoint(x: x + aw, y: cy - tip))
                    arrow.line(to: NSPoint(x: x + aw/2, y: cy + tip))
                    arrow.close()
                    arrow.fill()
                    
                    let lit = SummaryIconView.litDots(bytes)
                    var dx = x + aw + 2
                    for i in 0..<4 {
                        (i < lit ? self.ink : self.track).setFill()
                        NSBezierPath(ovalIn: NSRect(x: dx, y: cy - d/2, width: d, height: d)).fill()
                        dx += d + dotGap
                    }
                }
            }
            x += aw + 2 + 4*d + 3*dotGap
        }
        
        return ceil(x)
    }
    
    // Bolt or plug centered on the battery bar. A slightly larger copy is first erased from the bar
    // so the symbol has a gap around it and stays readable on both the fill and the track.
    private func drawBadge(_ symbol: String, scale: CGFloat, rotation: CGFloat = 0, in rect: NSRect) {
        guard let base = (NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                          ?? NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .heavy)) else { return }
        // enlarged so it reads at this small size and bleeds past the bar
        let size = NSSize(width: base.size.width * scale, height: base.size.height * scale)
        // drawn around the bar's center, so rotation turns it in place (positive = counterclockwise)
        let boltRect = NSRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height)
        NSGraphicsContext.current?.saveGraphicsState()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }
        let t = NSAffineTransform()
        t.translateX(by: rect.midX, yBy: rect.midY)
        t.rotate(byDegrees: rotation)
        t.concat()
        
        for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0), (0.0, 0.0)] {
            base.draw(in: boltRect.offsetBy(dx: dx, dy: dy), from: .zero, operation: .destinationOut, fraction: 1)
        }
        // colored through the symbol configuration so it stays vector-sharp when rotated
        let tinted = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [self.ink])) ?? base
        tinted.draw(in: boltRect)
    }
    
    // hand-drawn glyph (coffee bean, Ethernet) in the menu bar text color, returns its width
    private func glyph(_ glyph: Glyph, x: CGFloat, draw: Bool) -> CGFloat {
        if draw {
            glyph.draw(center: NSPoint(x: x + glyph.size.width/2, y: Constants.Widget.height/2), color: self.ink)
        }
        return glyph.size.width
    }
    
    // Renders the symbol once into pixels in the given color. (An image built from a
    // drawing callback would re-run that callback on every draw.)
    private func tintedBitmap(_ base: NSImage, color: NSColor, scale: CGFloat) -> NSImage? {
        let size = base.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(size.width * scale)),
            pixelsHigh: Int(ceil(size.height * scale)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        // the size in points must be set before drawing, or it draws at 1x into the corner
        rep.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(origin: .zero, size: size)
        base.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()
        
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
    
    // draws an SF Symbol tinted with the menu bar text color, returns its width
    // variableValue lights part of a symbol that supports it (the Wi-Fi bars), on macOS 13+
    // lift: points to raise it above center
    private func symbol(_ name: String, variableValue: Double? = nil, pointSize: CGFloat = 13, lift: CGFloat = 0, x: CGFloat, draw: Bool) -> CGFloat {
        let scale = self.window?.backingScaleFactor ?? 2
        let key = "\(name)-\(variableValue ?? -1)-\(pointSize)-\(self.isDark)-\(scale)"
        var image = self.symbolCache[key]
        if image == nil {
            var source = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            if let variableValue, #available(macOS 13.0, *) {
                source = NSImage(systemSymbolName: name, variableValue: variableValue, accessibilityDescription: nil)
            }
            if let base = source?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)) {
                image = self.tintedBitmap(base, color: self.ink, scale: scale)
                self.symbolCache[key] = image
            }
        }
        guard let image else { return 0 }
        if draw {
            let y = (Constants.Widget.height - image.size.height) / 2 + lift
            image.draw(in: NSRect(x: x, y: y, width: image.size.width, height: image.size.height))
        }
        return ceil(image.size.width)
    }
}

// MARK: - Keep awake

extension Notification.Name {
    static let keepAwakeChanged = Notification.Name("keepAwakeChanged")
}

// Prevents idle sleep until turned off, like `caffeinate`/Amphetamine. While active, the summary
// style's battery item shows a coffee bean; with any other menu bar style it gets its own bean item instead. The on/off state isn't saved, so a relaunch starts with it off;
// the "keep screen on" choice is saved.
internal final class KeepAwake: NSObject, NSMenuDelegate {
    static let shared = KeepAwake()
    
    private(set) var isActive: Bool = false
    // set by the combined view: when the summary icon is in the menu bar, it shows the
    // bean itself, so no separate menu bar item is needed
    var summaryShowsIndicator: Bool = false {
        didSet {
            if oldValue != self.summaryShowsIndicator { self.updateStatusItem() }
        }
    }
    private var assertion: IOPMAssertionID = 0
    private var statusItem: NSStatusItem? = nil
    
    var keepScreenOn: Bool {
        get { Store.shared.bool(key: "KeepAwake_screen", defaultValue: false) }
        set {
            Store.shared.set(key: "KeepAwake_screen", value: newValue)
            if self.isActive { self.createAssertion() }
            self.notify()
        }
    }
    
    func setActive(_ state: Bool) {
        guard state != self.isActive else { return }
        self.isActive = state
        if state {
            self.createAssertion()
        } else {
            self.releaseAssertion()
        }
        self.updateStatusItem()
        self.notify()
    }
    
    // "display" also keeps the system awake; "system" lets the screen sleep but not the Mac
    private func createAssertion() {
        self.releaseAssertion()
        let type = self.keepScreenOn ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Stats keep awake" as CFString, &self.assertion)
        if result != kIOReturnSuccess {
            self.assertion = 0
        }
    }
    
    private func releaseAssertion() {
        guard self.assertion != 0 else { return }
        IOPMAssertionRelease(self.assertion)
        self.assertion = 0
    }
    
    private func notify() {
        NotificationCenter.default.post(name: .keepAwakeChanged, object: nil)
    }
    
    // MARK: menu bar cup
    
    private func updateStatusItem() {
        let wanted = self.isActive && !self.summaryShowsIndicator
        if wanted, self.statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "KeepAwake"
            item.button?.image = Glyph.bean.image(scale: 1.25)
            item.button?.toolTip = localizedString("Keep Awake is on")
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.statusItem = item
        } else if !wanted, let item = self.statusItem {
            NSStatusBar.system.removeStatusItem(item)
            self.statusItem = nil
        }
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: localizedString("Keep Awake is on"), action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let screen = NSMenuItem(title: localizedString("Keep screen on"), action: #selector(self.toggleScreen), keyEquivalent: "")
        screen.target = self
        screen.state = self.keepScreenOn ? .on : .off
        menu.addItem(screen)
        menu.addItem(.separator())
        let off = NSMenuItem(title: localizedString("Turn Off"), action: #selector(self.turnOff), keyEquivalent: "")
        off.target = self
        menu.addItem(off)
    }
    
    @objc private func toggleScreen() {
        self.keepScreenOn.toggle()
    }
    
    @objc private func turnOff() {
        self.setActive(false)
    }
}

// Dropdown row: coffee bean icon, "Keep Awake", status line and a switch. Clicking anywhere toggles it.
private class KeepAwakeRow: NSView {
    static let height: CGFloat = 40
    
    private let iconBackground = NSView()
    private let iconView = NSImageView()
    private let subtitle = NSTextField(labelWithString: "")
    private let toggle = NSSwitch()
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: KeepAwakeRow.height))
        
        self.wantsLayer = true
        self.iconBackground.wantsLayer = true
        self.iconBackground.layer?.cornerRadius = 14
        self.iconView.image = Glyph.bean.image(scale: 1.15)
        
        let title = NSTextField(labelWithString: localizedString("Keep Awake"))
        title.font = NSFont.systemFont(ofSize: 13)
        title.textColor = .labelColor
        self.subtitle.font = NSFont.systemFont(ofSize: 11)
        self.subtitle.textColor = .secondaryLabelColor
        
        self.toggle.controlSize = .small
        self.toggle.target = self
        self.toggle.action = #selector(self.switchChanged)
        
        let text = NSStackView(views: [title, self.subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0
        
        self.iconBackground.addSubview(self.iconView)
        [self.iconBackground, self.iconView, text, self.toggle].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        [self.iconBackground, text, self.toggle].forEach { self.addSubview($0) }
        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: KeepAwakeRow.height),
            self.iconBackground.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 6),
            self.iconBackground.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.iconBackground.widthAnchor.constraint(equalToConstant: 28),
            self.iconBackground.heightAnchor.constraint(equalToConstant: 28),
            self.iconView.centerXAnchor.constraint(equalTo: self.iconBackground.centerXAnchor),
            self.iconView.centerYAnchor.constraint(equalTo: self.iconBackground.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: self.iconBackground.trailingAnchor, constant: 10),
            text.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.toggle.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
            self.toggle.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
        
        self.sync()
        NotificationCenter.default.addObserver(self, selector: #selector(self.sync), name: .keepAwakeChanged, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func sync() {
        let on = KeepAwake.shared.isActive
        self.toggle.state = on ? .on : .off
        if on {
            self.subtitle.stringValue = localizedString(KeepAwake.shared.keepScreenOn ? "On, screen stays on" : "On, screen can sleep")
        } else {
            self.subtitle.stringValue = localizedString("Off")
        }
        self.needsDisplay = true
    }
    
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        let on = KeepAwake.shared.isActive
        self.iconBackground.layer?.backgroundColor = on ? NSColor.controlAccentColor.cgColor : NSColor.labelColor.withAlphaComponent(0.1).cgColor
        self.iconView.contentTintColor = on ? .white : .labelColor
    }
    
    @objc private func switchChanged() {
        KeepAwake.shared.setActive(self.toggle.state == .on)
    }
    
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return }
        KeepAwake.shared.setActive(!KeepAwake.shared.isActive)
    }
}

// Dropdown row under Keep Awake: whether the screen also stays on.
private class KeepScreenRow: NSView {
    static let height: CGFloat = 26
    
    private let toggle = NSSwitch()
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: KeepScreenRow.height))
        
        let label = NSTextField(labelWithString: localizedString("Keep screen on"))
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        
        self.toggle.controlSize = .mini
        self.toggle.target = self
        self.toggle.action = #selector(self.switchChanged)
        
        [label, self.toggle].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview($0)
        }
        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: KeepScreenRow.height),
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 44), // lines up with "Keep Awake"
            label.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.toggle.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
            self.toggle.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
        
        self.sync()
        NotificationCenter.default.addObserver(self, selector: #selector(self.sync), name: .keepAwakeChanged, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func sync() {
        self.toggle.state = KeepAwake.shared.keepScreenOn ? .on : .off
    }
    
    @objc private func switchChanged() {
        KeepAwake.shared.keepScreenOn = self.toggle.state == .on
    }
}
