//
//  AppSettings.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 15/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

class ApplicationSettings: NSStackView {
    private var updateIntervalValue: String {
        Store.shared.string(key: "update-interval", defaultValue: AppUpdateInterval.silent.rawValue)
    }
    
    private var temperatureUnitsValue: String {
        get { Store.shared.string(key: "temperature_units", defaultValue: "system") }
        set { Store.shared.set(key: "temperature_units", value: newValue) }
    }
    
    private var combinedModulesState: Bool {
        get { Store.shared.bool(key: "CombinedModules", defaultValue: false) }
        set { Store.shared.set(key: "CombinedModules", value: newValue) }
    }
    private var combinedModulesSpacing: String {
        get { Store.shared.string(key: "CombinedModules_spacing", defaultValue: "none") }
        set { Store.shared.set(key: "CombinedModules_spacing", value: newValue) }
    }
    private var combinedModulesSeparator: Bool {
        get { Store.shared.bool(key: "CombinedModules_separator", defaultValue: false) }
        set { Store.shared.set(key: "CombinedModules_separator", value: newValue) }
    }
    private var combinedModulesPopup: Bool {
        get { Store.shared.bool(key: "CombinedModules_popup", defaultValue: true) }
        set { Store.shared.set(key: "CombinedModules_popup", value: newValue) }
    }
    private var combinedModulesIconSymbol: String {
        get { Store.shared.string(key: "CombinedModules_iconSymbol", defaultValue: "app") }
        set { Store.shared.set(key: "CombinedModules_iconSymbol", value: newValue) }
    }
    private var combinedModulesCompact: Bool {
        get { Store.shared.bool(key: "CombinedModules_compact", defaultValue: false) }
        set { Store.shared.set(key: "CombinedModules_compact", value: newValue) }
    }
    
    private var systemWidgetsUpdatesState: Bool {
        get {
            let userDefaults = UserDefaults(suiteName: "\(Bundle.main.object(forInfoDictionaryKey: "TeamId") as! String).eu.exelban.Stats.widgets")
            return userDefaults?.bool(forKey: "systemWidgetsUpdates_state") ?? false
        }
        set {
            let userDefaults = UserDefaults(suiteName: "\(Bundle.main.object(forInfoDictionaryKey: "TeamId") as! String).eu.exelban.Stats.widgets")
            userDefaults?.set(newValue, forKey: "systemWidgetsUpdates_state")
        }
    }
    
    private var keepMenuBarPosition: Bool {
        get { Store.shared.bool(key: "keep_menubar_positions", defaultValue: false) }
        set { Store.shared.set(key: "keep_menubar_positions", value: newValue) }
    }
    
    private var updateSelector: NSPopUpButton?
    private var startAtLoginBtn: NSSwitch?
    private var remoteControlBtn: NSSwitch?
    private var remoteUpdatesBtn: NSSwitch?
    
    private var combinedModulesView: PreferencesSection?
    private var fanHelperView: PreferencesSection?
    private var remoteView: PreferencesSection?
    
    private var updateWindow: UpdateWindow?
    private let moduleSelector: ModuleSelectorView = ModuleSelectorView()
    private var combinedIconSelect: NSPopUpButton? = nil
    private var keepScreenSwitch: NSSwitch? = nil
    fileprivate var forkModulesSection: PreferencesSection? = nil

    private static let combinedModulesClickActions: [KeyValue_t] = [
        KeyValue_t(key: "list", value: "Combined list"),
        KeyValue_t(key: "module", value: "Module details")
    ]
    
    private var CPUeButton: NSButton?
    private var CPUpButton: NSButton?
    private var CPUsButton: NSButton?
    private var GPUButton: NSButton?
    
    private var CPUeTest: CPUStressTest = CPUStressTest(type: .efficiency)
    private var CPUpTest: CPUStressTest = CPUStressTest(type: .performance)
    private var CPUsTest: CPUStressTest = CPUStressTest(type: .super)
    private var GPUTest: GPUStressTest? = GPUStressTest()
    
    private var planField: NSTextField?
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Settings.width, height: Constants.Settings.height))
        self.translatesAutoresizingMaskIntoConstraints = false
        
        let scrollView = ScrollableStackView(orientation: .vertical)
        scrollView.stackView.edgeInsets = NSEdgeInsets(
            top: 0,
            left: Constants.Settings.margin,
            bottom: Constants.Settings.margin,
            right: Constants.Settings.margin
        )
        scrollView.stackView.spacing = Constants.Settings.margin
        
        scrollView.stackView.addArrangedSubview(self.informationView())
        
        self.updateSelector = selectView(
            action: #selector(self.toggleUpdateInterval),
            items: AppUpdateIntervals,
            selected: self.updateIntervalValue
        )
        self.startAtLoginBtn = switchView(
            action: #selector(self.toggleLaunchAtLogin),
            state: LaunchAtLogin.isEnabled
        )
        
        scrollView.stackView.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Check for updates"), component: self.updateSelector!),
            PreferencesRow(localizedString("Temperature"), component: selectView(
                action: #selector(self.toggleTemperatureUnits),
                items: TemperatureUnits,
                selected: self.temperatureUnitsValue
            )),
            PreferencesRow(localizedString("Show icon in dock"), component: switchView(
                action: #selector(self.toggleDock),
                state: Store.shared.bool(key: "dockIcon", defaultValue: false)
            )),
            PreferencesRow(localizedString("Start at login"), component: self.startAtLoginBtn!),
            PreferencesRow(localizedString("Keep the menubar items position"), component: switchView(
                action: #selector(self.toggleMenuBarPosition),
                state: self.keepMenuBarPosition
            )),
            PreferencesRow("macOS widgets", component: switchView(
                action: #selector(self.toggleSystemWidgetsUpdatesState),
                state: self.systemWidgetsUpdatesState
            ))
        ]))
        
        let iconSelect = selectView(
            action: #selector(self.toggleCombinedModulesIconSymbol),
            items: CombinedModulesIcons,
            selected: self.combinedModulesIconSymbol
        )
        self.combinedIconSelect = iconSelect
        // rows by index; updateCombinedModulesSettings() shows only the ones that apply
        self.combinedModulesView = PreferencesSection(
            title: localizedString("Combined modules"),
            subtitle: localizedString("Show modules together in the menu bar instead of one item each"),
            [
                PreferencesRow(localizedString("Enabled"), component: switchView( // 0
                    action: #selector(self.toggleCombinedModules),
                    state: self.combinedModulesState
                )),
                PreferencesRow(localizedString("Menu bar"), component: selectView( // 1
                    action: #selector(self.toggleCombinedModulesStyle),
                    items: CombinedModulesWidget.all,
                    selected: CombinedModulesWidget.current.rawValue
                )),
                PreferencesRow(localizedString("Icon"), component: iconSelect), // 2
                PreferencesRow(component: self.moduleSelector), // 3
                PreferencesRow(localizedString("Spacing"), component: selectView( // 4
                    action: #selector(self.toggleCombinedModulesSpacing),
                    items: CombinedModulesSpacings,
                    selected: self.combinedModulesSpacing
                )),
                PreferencesRow(localizedString("Separator"), component: switchView( // 5
                    action: #selector(self.toggleCombinedModulesSeparator),
                    state: self.combinedModulesSeparator
                )),
                PreferencesRow(localizedString("Clicking opens"), component: selectView( // 6
                    action: #selector(self.toggleCombinedModulesClick),
                    items: ApplicationSettings.combinedModulesClickActions,
                    selected: self.combinedModulesPopup ? "list" : "module"
                )),
                PreferencesRow(localizedString("Compact list"), component: switchView( // 7
                    action: #selector(self.toggleCombinedModulesCompact),
                    state: self.combinedModulesCompact
                ))
            ]
        )
        scrollView.stackView.addArrangedSubview(self.combinedModulesView!)
        self.updateCombinedModulesSettings()
        
        self.remoteControlBtn = switchView(
            action: #selector(self.toggleRemoteControlState),
            state: SystemStats.shared.control
        )
        self.remoteUpdatesBtn = switchView(
            action: #selector(self.toggleRemoteUpdateState),
            state: SystemStats.shared.update
        )
        self.planField = textView(SystemStats.shared.plan?.rawValue.capitalized ?? "Free")
        self.remoteView = PreferencesSection(title: "System Stats", [
            PreferencesRow(localizedString("Authorization"), component: buttonView(#selector(self.loginToRemote), text: localizedString("Sign in"))),
            PreferencesRow(localizedString("Identificator"), component: textView(SystemStats.shared.id.uuidString)),
            PreferencesRow(localizedString("Plan"), component: self.planField!),
            PreferencesRow(localizedString("Monitoring"), component: switchView(
                action: #selector(self.toggleRemoteMonitoringState),
                state: SystemStats.shared.monitoring
            )),
            PreferencesRow(id: "monitoring_modules", component: buttonView(
                #selector(self.selectRemoteMonitoringModules), text: localizedString("Modules")
            )),
            PreferencesRow(localizedString("Control"), component: self.remoteControlBtn!),
            PreferencesRow(localizedString("Update"), component: self.remoteUpdatesBtn!),
            PreferencesRow(component: buttonView(#selector(self.logoutFromRemote), text: localizedString("Sign out"))),
            PreferencesRow(component: buttonView(#selector(self.deregisterFromRemote), text: localizedString("Deregister")))
        ])
        scrollView.stackView.addArrangedSubview(self.remoteView!)
        for row in 1...8 {
            self.remoteView?.setRowVisibility(row, newState: false)
        }
        
        scrollView.stackView.addArrangedSubview(PreferencesSection(title: localizedString("Settings"), [
            PreferencesRow(
                localizedString("Export settings"),
                component: buttonView(#selector(self.exportSettings), text: localizedString("Save"))
            ),
            PreferencesRow(
                localizedString("Import settings"),
                component: buttonView(#selector(self.importSettings), text: localizedString("Choose file"))
            ),
            PreferencesRow(
                localizedString("Reset settings"),
                component: buttonView(#selector(self.resetSettings), text: localizedString("Reset"))
            )
        ]))
        
        self.fanHelperView = PreferencesSection([
            PreferencesRow(
                localizedString("Uninstall fan helper"),
                component: buttonView(#selector(self.uninstallHelper), text: localizedString("Uninstall"))
            )
        ])
        scrollView.stackView.addArrangedSubview(self.fanHelperView!)
        
        self.addArrangedSubview(scrollView)
        
        let CPUeButton = buttonView(#selector(self.toggleCPUeStressTest), text: localizedString("Run"))
        let CPUpButton = buttonView(#selector(self.toggleCPUpStressTest), text: localizedString("Run"))
        let CPUsButton = buttonView(#selector(self.toggleCPUsStressTest), text: localizedString("Run"))
        let GPUButton = buttonView(#selector(self.toggleGPUStressTest), text: localizedString("Run"))
        
        self.CPUeButton = CPUeButton
        self.CPUpButton = CPUpButton
        self.CPUsButton = CPUsButton
        self.GPUButton = GPUButton
        
        let cpu = SystemKit.shared.device.info.cpu
        var tests: [PreferencesRow] = []
        if (cpu?.eCores ?? 0) > 0 {
            tests.append(PreferencesRow(localizedString("Efficiency cores"), component: CPUeButton))
        }
        if (cpu?.pCores ?? 1) > 0 {
            tests.append(PreferencesRow(localizedString("Performance cores"), component: CPUpButton))
        }
        if (cpu?.sCores ?? 0) > 0 {
            tests.append(PreferencesRow(localizedString("Super cores"), component: CPUsButton))
        }
        if self.GPUTest != nil {
            tests.append(PreferencesRow(localizedString("GPU"), component: GPUButton))
        }
        
        #if arch(arm64)
        scrollView.stackView.addArrangedSubview(PreferencesSection(title: localizedString("Stress tests"), tests))
        #endif
        
        self.applyForkLayout(scrollView.stackView)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.toggleUninstallHelperButton), name: .fanHelperState, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleRemoteState), name: .remoteState, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .fanHelperState, object: nil)
        NotificationCenter.default.removeObserver(self, name: .remoteState, object: nil)
    }
    
    internal func viewWillAppear() {
        self.startAtLoginBtn?.state = LaunchAtLogin.isEnabled ? .on : .off
        self.remoteControlBtn?.state = SystemStats.shared.control ? .on : .off
        
        self.planField?.stringValue = SystemStats.shared.plan?.rawValue.capitalized ?? "Free"
        self.setRemoteSettings(SystemStats.shared.isAuthorized)
        
        var idx = self.updateSelector?.indexOfSelectedItem ?? 0
        if let items = self.updateSelector?.menu?.items {
            for (i, item) in items.enumerated() {
                if let obj = item.representedObject as? String, obj == self.updateIntervalValue {
                    idx = i
                }
            }
        }
        self.updateSelector?.selectItem(at: idx)
    }
    
    private func informationView() -> NSView {
        let view = NSStackView()
        view.heightAnchor.constraint(equalToConstant: 220).isActive = true
        view.orientation = .vertical
        view.distribution = .fill
        view.alignment = .centerY
        view.spacing = 0
        
        let container: NSGridView = NSGridView()
        container.heightAnchor.constraint(equalToConstant: 180).isActive = true
        container.rowSpacing = 0
        container.yPlacement = .center
        container.xPlacement = .center
        
        let iconView: NSImageView = NSImageView(image: NSImage(named: NSImage.Name("Stats"))!)
        
        let statsName: NSTextField = TextView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: 22))
        statsName.alignment = .center
        statsName.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        statsName.stringValue = "Stats"
        statsName.isSelectable = true
        
        let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        
        let statsVersion: NSTextField = TextView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: 16))
        statsVersion.alignment = .center
        statsVersion.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        statsVersion.stringValue = "\(localizedString("Version")) \(versionNumber)"
        statsVersion.isSelectable = true
        statsVersion.toolTip = "\(localizedString("Build number")) \(buildNumber)"
        
        let updateButton: NSButton = NSButton()
        updateButton.title = localizedString("Check for update")
        updateButton.bezelStyle = .rounded
        updateButton.target = self
        updateButton.action = #selector(self.updateAction)
        
        container.addRow(with: [iconView])
        container.addRow(with: [statsName])
        container.addRow(with: [statsVersion])
        container.addRow(with: [updateButton])
        
        container.row(at: 1).height = 22
        container.row(at: 2).height = 20
        container.row(at: 3).height = 30
        
        view.addArrangedSubview(container)
        
        return view
    }
    
    // MARK: - actions
    
    @objc private func updateAction() {
        // fork: upstream releases would replace this build
        guard !ApplicationSettings.isFork else { return }
        updater.check(force: true, completion: { result, error in
            if error != nil {
                debug("error updater.check(): \(error!.localizedDescription)")
                return
            }
            
            guard let version: version_s = result else {
                debug("download error(): no version found")
                return
            }
            
            DispatchQueue.main.async(execute: {
                if self.updateWindow == nil {
                    let w = UpdateWindow()
                    w.onClose = { [weak self = self] in self?.updateWindow = nil }
                    self.updateWindow = w
                }
                self.updateWindow?.open(version, settingButton: true)
                return
            })
        })
    }
    
    @objc private func toggleUpdateInterval(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        Store.shared.set(key: "update-interval", value: key)
    }
    
    @objc private func toggleTemperatureUnits(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.temperatureUnitsValue = key
    }
    
    @objc private func toggleDock(_ sender: NSButton) {
        let state = sender.state
        Store.shared.set(key: "dockIcon", value: state == NSControl.StateValue.on)
        NSApp.updateWindows()
        if state == .off {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        LaunchAtLogin.isEnabled = sender.state == NSControl.StateValue.on
        if !Store.shared.exist(key: "runAtLoginInitialized") {
            Store.shared.set(key: "runAtLoginInitialized", value: true)
        }
    }
    
    @objc private func toggleCombinedModules(_ sender: NSButton) {
        self.combinedModulesState = sender.state == NSControl.StateValue.on
        self.updateCombinedModulesSettings()
        NotificationCenter.default.post(name: .toggleOneView, object: nil, userInfo: nil)
    }
    
    // Shows only the rows that do something for the chosen style:
    // - Widgets: module order, spacing, separator, what a click opens, and the compact
    //   list when a click opens the combined list
    // - Summary items: nothing extra; their dropdowns always use the compact layout
    // - Icon: which icon, and the compact list (a click always opens the combined list)
    // - Bars, rings, dial: the compact list (a click always opens the combined list)
    private func updateCombinedModulesSettings() {
        let on = self.combinedModulesState
        let style = CombinedModulesWidget.current
        let visible: [Int: Bool] = [
            1: on,
            2: on && style == .icon,
            3: on && style == .widgets,
            4: on && style == .widgets,
            5: on && style == .widgets,
            6: on && style == .widgets,
            7: on && (style == .icon || style.isSummaryWidget || (style == .widgets && self.combinedModulesPopup))
        ]
        visible.forEach { self.combinedModulesView?.setRowVisibility($0.key, newState: $0.value) }
    }
    
    @objc private func toggleCombinedModulesStyle(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let style = CombinedModulesWidget(rawValue: key),
              style != CombinedModulesWidget.current else { return }
        CombinedModulesWidget.current = style
        if style == .icon {
            // "ticks" was how the summary style used to be saved; it isn't a real icon
            if self.combinedModulesIconSymbol == "ticks" {
                self.combinedModulesIconSymbol = "app"
            }
            self.selectCombinedIcon(self.combinedModulesIconSymbol)
        }
        self.updateCombinedModulesSettings()
        NotificationCenter.default.post(name: .moduleRearrange, object: nil, userInfo: nil)
        NotificationCenter.default.post(name: .combinedModulesPopup, object: nil, userInfo: nil)
    }
    
    // marks the given icon as chosen in the Icon picker
    private func selectCombinedIcon(_ key: String) {
        guard let select = self.combinedIconSelect else { return }
        select.itemArray.forEach { $0.state = ($0.representedObject as? String) == key ? .on : .off }
        if let item = select.itemArray.first(where: { ($0.representedObject as? String) == key }) {
            select.select(item)
        }
    }
    
    @objc private func toggleCombinedModulesClick(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.combinedModulesPopup = key == "list"
        self.updateCombinedModulesSettings()
        NotificationCenter.default.post(name: .combinedModulesPopup, object: nil, userInfo: nil)
    }
    
    @objc private func toggleKeepScreenOn(_ sender: NSButton) {
        KeepAwake.shared.keepScreenOn = sender.state == .on
    }
    
    @objc private func toggleSummaryWifiStrength(_ sender: NSButton) {
        Store.shared.set(key: "CombinedModules_wifiStrength", value: sender.state == .on)
        NotificationCenter.default.post(name: .combinedSummaryLayoutChanged, object: nil)
    }
    
    @objc private func toggleSummaryNetworkDots(_ sender: NSButton) {
        Store.shared.set(key: "CombinedModules_networkDots", value: sender.state == .on)
        NotificationCenter.default.post(name: .combinedSummaryLayoutChanged, object: nil)
    }
    
    @objc private func toggleSummaryDetails(_ sender: NSButton) {
        Store.shared.set(key: "CombinedModules_details", value: sender.state == .on)
        NotificationCenter.default.post(name: .combinedModulesPopup, object: nil)
    }
    
    @objc private func syncKeepScreen() {
        self.keepScreenSwitch?.state = KeepAwake.shared.keepScreenOn ? .on : .off
    }
    
    @objc private func toggleCombinedModulesSpacing(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.combinedModulesSpacing = key
        NotificationCenter.default.post(name: .moduleRearrange, object: nil, userInfo: nil)
    }
    
    @objc private func toggleCombinedModulesSeparator(_ sender: NSButton) {
        self.combinedModulesSeparator = sender.state == NSControl.StateValue.on
        NotificationCenter.default.post(name: .moduleRearrange, object: nil, userInfo: nil)
    }
    
    @objc private func toggleCombinedModulesIconSymbol(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.combinedModulesIconSymbol = key
        NotificationCenter.default.post(name: .moduleRearrange, object: nil, userInfo: nil)
    }
    
    @objc private func toggleCombinedModulesCompact(_ sender: NSButton) {
        self.combinedModulesCompact = sender.state == NSControl.StateValue.on
        NotificationCenter.default.post(name: .combinedModulesPopup, object: nil, userInfo: nil)
    }
    
    @objc private func toggleMenuBarPosition(_ sender: NSButton) {
        self.keepMenuBarPosition = sender.state == NSControl.StateValue.on
    }
    
    @objc private func importSettings() {
        let panel = NSOpenPanel()
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.modalPanelWindow)))
        panel.begin { (result) in
            guard result.rawValue == NSApplication.ModalResponse.OK.rawValue else { return }
            if let url = panel.url {
                Store.shared.import(from: url)
            }
        }
    }
    
    @objc private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Stats.plist"
        panel.showsTagField = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.modalPanelWindow)))
        panel.begin { (result) in
            guard result.rawValue == NSApplication.ModalResponse.OK.rawValue else { return }
            if let url = panel.url {
                Store.shared.export(to: url)
            }
        }
    }
    
    @objc private func resetSettings() {
        let alert = NSAlert()
        alert.messageText = localizedString("Reset settings")
        alert.informativeText = localizedString("Reset settings text")
        alert.alertStyle = .warning
        alert.addButton(withTitle: localizedString("Yes"))
        alert.addButton(withTitle: localizedString("No"))
        
        if alert.runModal() == .alertFirstButtonReturn {
            Store.shared.reset()
            restartApp(self)
        }
    }
    
    @objc private func toggleUninstallHelperButton(_ notification: Notification) {
        guard let state = notification.userInfo?["state"] as? Bool, let v = self.fanHelperView else {
            return
        }
        v.isHidden = !state || ApplicationSettings.isFork
    }
    
    @objc private func uninstallHelper() {
        SMCHelper.shared.uninstall()
    }
    
    @objc private func toggleCPUeStressTest() {
        if self.CPUeTest.isRunning {
            self.CPUeTest.stop()
            self.CPUeButton?.title = localizedString("Run")
        } else {
            self.CPUeTest.start()
            self.CPUeButton?.title = localizedString("Stop")
        }
    }
    
    @objc private func toggleCPUpStressTest() {
        if self.CPUpTest.isRunning {
            self.CPUpTest.stop()
            self.CPUpButton?.title = localizedString("Run")
        } else {
            self.CPUpTest.start()
            self.CPUpButton?.title = localizedString("Stop")
        }
    }
    
    @objc private func toggleCPUsStressTest() {
        if self.CPUsTest.isRunning {
            self.CPUsTest.stop()
            self.CPUsButton?.title = localizedString("Run")
        } else {
            self.CPUsTest.start()
            self.CPUsButton?.title = localizedString("Stop")
        }
    }
    
    @objc private func toggleGPUStressTest() {
        guard let test = self.GPUTest else { return }
        
        if test.isRunning {
            test.stop()
            self.GPUButton?.title = localizedString("Run")
        } else {
            test.start()
            self.GPUButton?.title = localizedString("Stop")
        }
    }
    
    @objc private func toggleRemoteMonitoringState(_ sender: NSButton) {
        SystemStats.shared.monitoring = sender.state == NSControl.StateValue.on
        self.remoteView?.setRowVisibility("monitoring_modules", newState: SystemStats.shared.monitoring)
    }
    @objc private func selectRemoteMonitoringModules(_ sender: NSButton) {
        let supported = [ModuleType.CPU, .GPU, .RAM, .disk, .sensors, .network, .battery].map { $0.stringValue }
        let list = modules.filter { $0.available && $0.enabled && supported.contains($0.name) }
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        list.forEach { module in
            let item = NSMenuItem(title: localizedString(module.name), action: #selector(self.toggleRemoteMonitoringModule), keyEquivalent: "")
            item.target = self
            item.representedObject = module.name
            item.state = SystemStats.shared.isMonitoringEnabled(for: module.name) ? .on : .off
            menu.addItem(item)
        }
        if list.isEmpty {
            let item = NSMenuItem(title: localizedString("None"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }
    @objc private func toggleRemoteMonitoringModule(_ sender: NSMenuItem) {
        guard let module = sender.representedObject as? String else { return }
        let enabled = sender.state != .on
        SystemStats.shared.setMonitoring(enabled, for: module)
        sender.state = enabled ? .on : .off
    }
    @objc private func toggleRemoteControlState(_ sender: NSButton) {
        if sender.state == .on {
            let alert = NSAlert()
            alert.messageText = localizedString("Warning")
            alert.informativeText = localizedString("It is not recommended to enable remote control unless you know what you are doing.")
            alert.alertStyle = .warning
            alert.addButton(withTitle: localizedString("Enable"))
            alert.addButton(withTitle: localizedString("Cancel"))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                SystemStats.shared.control = true
            } else {
                sender.state = .off
            }
        } else {
            SystemStats.shared.control = false
        }
    }
    @objc private func toggleRemoteUpdateState(_ sender: NSButton) {
        SystemStats.shared.update = sender.state == NSControl.StateValue.on
    }
    
    @objc private func handleRemoteState(_ notification: Notification) {
        guard let auth = notification.userInfo?["auth"] as? Bool else { return }
        self.setRemoteSettings(auth)
    }
    
    @objc private func loginToRemote() {
        SystemStats.shared.login()
    }
    
    @objc private func logoutFromRemote() {
        SystemStats.shared.logout()
    }
    
    @objc private func deregisterFromRemote() {
        let alert = NSAlert()
        alert.messageText = localizedString("Deregister")
        alert.informativeText = localizedString("Deregister text")
        alert.alertStyle = .warning
        alert.addButton(withTitle: localizedString("Yes"))
        alert.addButton(withTitle: localizedString("No"))
        
        if alert.runModal() == .alertFirstButtonReturn {
            SystemStats.shared.deregister()
        }
    }
    
    private func setRemoteSettings(_ auth: Bool) {
        DispatchQueue.main.async {
            for row in 1...8 {
                self.remoteView?.setRowVisibility(row, newState: auth)
            }
            self.remoteView?.setRowVisibility(0, newState: !auth)
            self.remoteView?.setRowVisibility("monitoring_modules", newState: auth && SystemStats.shared.monitoring)
        }
    }
    
    @objc private func toggleSystemWidgetsUpdatesState(_ sender: NSButton) {
        self.systemWidgetsUpdatesState = sender.state == NSControl.StateValue.on
    }
}

private class ModuleSelectorView: NSStackView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Constants.Widget.height + (Constants.Settings.margin*2)))
        
        self.translatesAutoresizingMaskIntoConstraints = false
        self.edgeInsets = NSEdgeInsets(
            top: Constants.Settings.margin,
            left: Constants.Settings.margin,
            bottom: Constants.Settings.margin,
            right: Constants.Settings.margin
        )
        self.spacing = Constants.Settings.margin
        
        let background: NSVisualEffectView = {
            let view = NSVisualEffectView(frame: NSRect.zero)
            view.blendingMode = .withinWindow
            view.material = .contentBackground
            view.state = .active
            view.wantsLayer = true
            view.layer?.cornerRadius = 5
            return view
        }()
        
        var w = self.spacing
        modules.filter({ $0.available }).sorted(by: { $0.combinedPosition < $1.combinedPosition }).forEach { (m: Module) in
            let v = ModulePreview(id: m.name, icon: m.config.icon)
            self.addArrangedSubview(v)
            w += v.frame.width + self.spacing
        }
        
        if w < 20 {
            w = 20
        }
        
        self.addSubview(background, positioned: .below, relativeTo: .none)
        
        self.setFrameSize(NSSize(width: w, height: self.frame.height))
        background.setFrameSize(NSSize(width: w, height: self.frame.height))
        
        self.widthAnchor.constraint(equalToConstant: w).isActive = true
        self.heightAnchor.constraint(equalToConstant: self.frame.height).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let targetIdx = self.views.firstIndex(where: { $0.hitTest(location) != nil }),
              let window = self.window, self.views[targetIdx].identifier != nil else {
            super.mouseDragged(with: event)
            return
        }
        
        let view = self.views[targetIdx]
        let copy = ViewCopy(view)
        copy.zPosition = 2
        copy.transform = CATransform3DMakeScale(0.9, 0.9, 1)
        
        // hide the original view, show the copy
        view.subviews.forEach({ $0.isHidden = true })
        self.layer?.addSublayer(copy)
        
        // hide the copy view, show the original
        defer {
            copy.removeFromSuperlayer()
            view.subviews.forEach({ $0.isHidden = false })
        }
        
        var newIdx = -1
        let originCenter = view.frame.midX
        let originX = view.frame.origin.x
        let p0 = convert(event.locationInWindow, from: nil).x
        
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: 1e6, mode: .eventTracking) { event, stop in
            guard let event = event else {
                stop.pointee = true
                return
            }
            
            if event.type == .leftMouseDragged {
                let p1 = self.convert(event.locationInWindow, from: nil).x
                let diff = p1 - p0
                
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                copy.frame.origin.x = originX + diff
                CATransaction.commit()
                
                let reordered = self.views.map{
                    (view: $0, x: $0 !== view ? $0.frame.midX : originCenter + diff)
                }.sorted{ $0.x < $1.x }.map { $0.view }
                
                guard let nextIndex = reordered.firstIndex(of: view),
                      let prevIndex = self.views.firstIndex(of: view) else {
                    stop.pointee = true
                    return
                }
                
                if nextIndex != prevIndex {
                    newIdx = nextIndex
                    view.removeFromSuperviewWithoutNeedingDisplay()
                    self.insertArrangedSubview(view, at: newIdx)
                    self.layoutSubtreeIfNeeded()
                    
                    for (i, v) in self.views(in: .leading).compactMap({$0 as? ModulePreview}).enumerated() {
                        if let m = modules.first(where: { $0.name == v.identifier?.rawValue }) {
                            m.combinedPosition = i
                        }
                    }
                }
            } else {
                if newIdx != -1, let view = self.views[newIdx] as? ModulePreview, let id = view.identifier?.rawValue {
                    NotificationCenter.default.post(name: .moduleRearrange, object: nil, userInfo: ["id": id])
                }
                view.mouseUp(with: event)
                stop.pointee = true
            }
        }
    }
}

private class ModulePreview: NSStackView {
    private let imageView: NSImageView
    
    fileprivate init(id: String, icon: NSImage?) {
        self.imageView = NSImageView(frame: NSRect(origin: .zero, size: NSSize(width: Constants.Widget.height, height: Constants.Widget.height)))
        
        let size: CGSize = CGSize(width: Constants.Widget.height + (Constants.Widget.spacing * 2), height: Constants.Widget.height)
        super.init(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        
        self.wantsLayer = true
        self.layer?.cornerRadius = 2
        self.layer?.borderColor = NSColor(red: 221/255, green: 221/255, blue: 221/255, alpha: 1).cgColor
        self.layer?.borderWidth = 1
        self.layer?.backgroundColor = NSColor.white.cgColor
        
        self.identifier = NSUserInterfaceItemIdentifier(rawValue: id)
        self.setAccessibilityElement(true)
        self.toolTip = id
        
        self.orientation = .vertical
        self.distribution = .fill
        self.alignment = .centerY
        self.spacing = 0
        
        self.imageView.image = icon
        self.imageView.contentTintColor = self.isDarkMode ? .textBackgroundColor : .textColor
        
        self.addArrangedSubview(self.imageView)
        
        self.addTrackingArea(NSTrackingArea(
            rect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            options: [NSTrackingArea.Options.activeAlways, NSTrackingArea.Options.mouseEnteredAndExited, NSTrackingArea.Options.activeInActiveApp],
            owner: self,
            userInfo: nil
        ))
        
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: size.width),
            self.heightAnchor.constraint(equalToConstant: size.height)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayer() {
        self.imageView.contentTintColor = self.isDarkMode ? .textBackgroundColor : .textColor
    }
    
    override func mouseEntered(with: NSEvent) {
        NSCursor.pointingHand.set()
    }
    
    override func mouseExited(with: NSEvent) {
        NSCursor.arrow.set()
    }
}

// MARK: - Fork: only the settings this fork uses

// Hides what this fork doesn't use instead of deleting it, so upstream changes to that
// code keep merging cleanly.
extension ApplicationSettings {
    static let isFork = true // hides and disables what this fork doesn't use
    private static let forkModules = ["Battery", "CPU", "RAM", "Network"]
    
    fileprivate func applyForkLayout(_ stack: NSStackView) {
        let sections = stack.arrangedSubviews.compactMap({ $0 as? PreferencesSection })
        
        // general: only start at login. Hidden: update checks (the fork never updates from
        // upstream), temperature units (nothing shown uses them), the dock icon, keeping menu
        // bar positions (the summary items keep theirs anyway) and macOS desktop widgets
        if let general = sections.first {
            [0, 1, 2, 4, 5].forEach { general.setRowVisibility($0, newState: false) }
        }
        // the "Check for update" button under the app's name and version
        self.hideButton(in: stack, action: #selector(self.updateAction))
        // the summary items style is the only one this fork uses, so its picker goes too
        self.combinedModulesView?.isHidden = true
        self.remoteView?.isHidden = true // System Stats cloud monitoring
        self.fanHelperView?.isHidden = true
        // export, import, reset
        sections.first(where: { self.containsButton(in: $0, action: #selector(self.exportSettings)) })?.isHidden = true
        #if arch(arm64)
        sections.last?.isHidden = true // stress tests
        #endif
        
        let section = PreferencesSection(
            title: localizedString("Modules"),
            subtitle: localizedString("What Stats reads and shows in the menu bar"),
            self.forkModuleRows()
        )
        stack.addArrangedSubview(section)
        self.forkModulesSection = section
        self.syncForkModules()
        NotificationCenter.default.addObserver(self, selector: #selector(self.syncForkModules), name: .toggleModule, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.syncKeepScreen), name: .keepAwakeChanged, object: nil)
    }
    
    // Each module's switch, followed by its own options (indented):
    // Battery › Keep Awake keeps the screen on; Network › signal strength, activity dots.
    // Then one option for all dropdowns.
    private func forkModuleRows() -> [PreferencesRow] {
        func option(_ title: String, _ module: String, _ toggle: NSSwitch) -> PreferencesRow {
            let row = PreferencesRow(localizedString(title), component: toggle)
            row.edgeInsets.left += 20
            row.identifier = NSUserInterfaceItemIdentifier("option:\(module)")
            return row
        }
        
        // one refresh rate for all modules, shown as the CPU's (they're always set together)
        let interval = Store.shared.int(key: "CPU_updateInterval", defaultValue: 1)
        var rows: [PreferencesRow] = [
            PreferencesRow(localizedString("Update interval"), component: selectView(
                action: #selector(self.toggleForkUpdateInterval(_:)),
                items: ReaderUpdateIntervals,
                selected: "\(interval)"
            ))
        ]
        for name in ApplicationSettings.forkModules {
            guard let module = modules.first(where: { $0.config.name == name }), module.available else { continue }
            let toggle = switchView(action: #selector(self.toggleForkModule(_:)), state: module.enabled)
            toggle.identifier = NSUserInterfaceItemIdentifier(name)
            rows.append(PreferencesRow(localizedString(name), component: toggle))
            
            switch name {
            case "Battery":
                let keepScreen = switchView(action: #selector(self.toggleKeepScreenOn), state: KeepAwake.shared.keepScreenOn)
                self.keepScreenSwitch = keepScreen
                rows.append(option("Keep Awake keeps the screen on", name, keepScreen))
            case "Network":
                rows.append(option("Wi-Fi icon shows signal strength", name, switchView(
                    action: #selector(self.toggleSummaryWifiStrength),
                    state: Store.shared.bool(key: "CombinedModules_wifiStrength", defaultValue: true)
                )))
                rows.append(option("Network activity dots", name, switchView(
                    action: #selector(self.toggleSummaryNetworkDots),
                    state: Store.shared.bool(key: "CombinedModules_networkDots", defaultValue: true)
                )))
            default: break
            }
        }
        rows.append(PreferencesRow(localizedString("Details in dropdowns"), component: switchView(
            action: #selector(self.toggleSummaryDetails),
            state: Store.shared.bool(key: "CombinedModules_details", defaultValue: true)
        )))
        return rows
    }
    
    // hides a button, and its whole row when it sits in a grid
    private func hideButton(in view: NSView, action: Selector) {
        if let button = view as? NSButton, button.action == action {
            var parent = button.superview
            while let p = parent, !(p is NSGridView) { parent = p.superview }
            if let grid = parent as? NSGridView, let row = grid.cell(for: button)?.row {
                row.isHidden = true
            }
            button.isHidden = true
            return
        }
        view.subviews.forEach { self.hideButton(in: $0, action: action) }
    }
    
    private func containsButton(in view: NSView, action: Selector) -> Bool {
        if let button = view as? NSButton, button.action == action { return true }
        return view.subviews.contains(where: { self.containsButton(in: $0, action: action) })
    }
    
    @objc fileprivate func toggleForkUpdateInterval(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let seconds = Int(key) else { return }
        modules.forEach { $0.setUpdateInterval(seconds) }
    }
    
    @objc fileprivate func toggleForkModule(_ sender: NSSwitch) {
        guard let name = sender.identifier?.rawValue else { return }
        NotificationCenter.default.post(name: .toggleModule, object: nil, userInfo: ["module": name, "state": sender.state == .on])
    }
    
    // a module can also be turned on or off elsewhere
    @objc fileprivate func syncForkModules() {
        DispatchQueue.main.async {
            guard let section = self.forkModulesSection else { return }
            section.subviews.forEach { self.syncSwitches(in: $0) }
            if let network = modules.first(where: { $0.config.name == "Network" }) {
                section.findRows(id: "option:Network").forEach {
                    section.setRowVisibility($0, newState: network.enabled)
                }
            }
        }
    }
    
    private func syncSwitches(in view: NSView) {
        if let toggle = view as? NSSwitch, let name = toggle.identifier?.rawValue,
           let module = modules.first(where: { $0.config.name == name }) {
            toggle.state = module.enabled ? .on : .off
        }
        view.subviews.forEach { self.syncSwitches(in: $0) }
    }
}
