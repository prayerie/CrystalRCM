import Cocoa
import USBDeviceSwift

extension Notification.Name {
    static let ProgressUpdate = Notification.Name("ProgressUpdate")
}



class ViewController: NSViewController {
    
    @IBOutlet var consoleOutputBox: NSTextView!
    @IBOutlet weak var statusImage: NSImageView!
    @IBOutlet var progressBar: NSProgressIndicator!
    @IBOutlet var cbPayloadPaths: NSComboBox!
    @IBOutlet var btPush: NSButton!
    @IBOutlet var lbUpdate: NSTextField!
    @IBOutlet var chbAutopush: NSButton!
    
    var connectedDevice:TegraDevice?
    var devices:[TegraDevice] = []
    var shutupWarn = false
    var forceAllowPush = false
    var canPush = false
    var doAutopush = false
    
    private var inferredPayloadType: NXPayload = .generic
    private let recentPathsKey = "RecentPayloadPaths"
    private let autopushKey = "AutoPushOn"
    private let maxRecentPaths = 5
    
    private let ver = "1.0.0"
    private let crystalrcmGh = "https://api.github.com/repos/prayerie/CrystalRCM/releases/latest"

    // let the user force enable the push button
    override func flagsChanged(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            forceAllowPush = true
            self.btPush.isEnabled = true
            return
        }
        if !canPush {
            disablePushBtn()
        }
        forceAllowPush = false
    }
    
    private func disablePushBtn() {
        if !forceAllowPush {
            btPush.isEnabled = false
        }
    }
    
    private func tryEnablePushBtn() {
        if canPush {
            btPush.isEnabled = true
        }
    }
    
    func addConsoleLine(line: String) {
        let msg: NSAttributedString = NSAttributedString(string: line + "\n")
        DispatchQueue.main.async {
            self.consoleOutputBox.textStorage?.append(msg)
        }
    }
    
    private func checkForUpdates() {
        guard let url = URL(string: crystalrcmGh) else { return }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else {
                return
            }
            
            let latestVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            
            if self.isNewerVersion(latestVersion, than: self.ver) {
                DispatchQueue.main.async {
                    self.showUpdateAvailable(version: latestVersion, url: htmlURL)
                }
            }
        }
        
        task.resume()
    }
    
    private func isNewerVersion(_ latest: String, than current: String) -> Bool {
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(latestComponents.count, currentComponents.count) {
            let latestPart = i < latestComponents.count ? latestComponents[i] : 0
            let currentPart = i < currentComponents.count ? currentComponents[i] : 0
            
            if latestPart > currentPart {
                return true
            } else if latestPart < currentPart {
                return false
            }
        }
        
        return false
    }

    private func showUpdateAvailable(version: String, url: String) {
        lbUpdate.isHidden = false
        
        let paragraphStyle: NSMutableParagraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = NSTextAlignment.right
        let attributedString = NSMutableAttributedString(string: "Update available! v\(version)", attributes: [NSAttributedString.Key.paragraphStyle : paragraphStyle])
        let range = NSRange(location: 0, length: attributedString.length)
        
        lbUpdate.alignment = .right
        attributedString.addAttribute(.link, value: url, range: range)
        attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
        attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        lbUpdate.attributedStringValue = attributedString
        lbUpdate.allowsEditingTextAttributes = true
        lbUpdate.isSelectable = true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self, selector: #selector(self.usbConnected), name: .USBDeviceConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.usbDisconnected), name: .USBDeviceDisconnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.onProgressUpdate), name: .ProgressUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.onPayloadTypeInferred), name: .PayloadTypeDetected, object: nil)
//        NotificationCenter.default.addObserver(self, selector: #selector(self.onMenubarPayloadPress), name: .MenubarPush, object: nil)
//        NotificationCenter.default.addObserver(self, selector: #selector(self.onMenubarOpen), name: .MenubarOpen, object: nil)
        
        progressBar.doubleValue = 0.0
        progressBar.isHidden = true
        
        if #available(OSX 10.14, *) {
            consoleOutputBox.usesAdaptiveColorMappingForDarkAppearance = true
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
                    self.flagsChanged(with: $0)
                    return $0
                }
        disablePushBtn() // don't want any pushes before a payload is chosen
        
        cbPayloadPaths.removeAllItems() // remove annoying 'Item 1' 'Item 2' etc
        
        if let paths = UserDefaults.standard.array(forKey: recentPathsKey) as? [String] {
            cbPayloadPaths.removeAllItems()
            cbPayloadPaths.addItems(withObjectValues: paths)
            if !paths.isEmpty {
                cbPayloadPaths.stringValue = paths[0]
            }
        }

        let apOn = UserDefaults.standard.integer(forKey: autopushKey) as Int
        chbAutopush.state = NSControl.StateValue(rawValue: apOn)
        doAutopush = apOn == 1
        
        btPush.toolTip = "Hold SHIFT to force allow push"
        cbPayloadPaths.toolTip = "Path to payload binary"
        lbUpdate.isHidden = true
        checkForUpdates()
        
        if doAutopush && canPush {
            go()
        }
    }
    
    override func viewWillDisappear() {
        exit(0)
    }

    
    @IBAction func onAutopushToggle(_ sender: NSButton) {
        setAutopushOn(chbAutopush.state.rawValue)
        doAutopush = chbAutopush.state.rawValue == 1
        if doAutopush && canPush {
            go()
        }
    }
    
    @objc func onProgressUpdate(notification: NSNotification) {
        let p = notification.userInfo?["by"] as? Double ?? 0.0
        DispatchQueue.main.async {
            self.progressBar.isHidden = false
            self.progressBar.doubleValue = p
        }
        
        
    }
    
    private func go() {
        guard let device = devices.first(where: {
            $0.deviceInfo.vendorId == VID.RCM.rawValue &&
            $0.deviceInfo.productId == PID.RCM.rawValue
        }) else {
            addConsoleLine(line: "[error] No RCM device connected.")
            return
        }
        
        let payloadPath = cbPayloadPaths.stringValue
        
        if payloadPath.isEmpty {
            addConsoleLine(line: "[error] No payload.")
            return
        }
        
        let url = URL(fileURLWithPath: payloadPath)
        
        if !FileManager.default.fileExists(atPath: payloadPath) {
            addConsoleLine(line: "[error] The file \"\(payloadPath)\" doesn't exist.")
            return
        }
        
        if url.pathExtension.lowercased() != "bin" {
            addConsoleLine(line: "[error] Selected file does not have the extension \".bin\".")
            return
        }
        
        progressBar.increment(by: 5.0)
        addConsoleLine(line: "Loading payload: \(payloadPath)")

        do {
            let payloadData = try Data(contentsOf: URL(string: "file://" + payloadPath)!)
            self.progressBar.doubleValue = 5.0
            guard let intermezzoPath = Bundle.main.path(forResource: "intermezzo", ofType: "bin") else {
                addConsoleLine(line: "[error] intermezzo.bin is missing. Please redownload CrystalRCM.")
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try device.pushPayload(payloadData: payloadData, intermezzoPath: intermezzoPath)
                    
                    DispatchQueue.main.async {
                        self.addConsoleLine(line: "Payload launched successfully!")
                        
                        let successImage: NSImage?
                        switch self.inferredPayloadType {
                        case .fusee:
                            successImage = C_ATMOSPHERE
                        case .hekate:
                            successImage = C_HEKATE
                        case .rei:
                            successImage = C_REI
                        case .briccmii:
                            self.addConsoleLine(line: "Briccmii was detected. Your device will now only boot to RCM.") // pointless warning probably, maybe someone will do it by accident
                            successImage = C_BRICCMII
                        case .lockpick:
                            successImage = C_LOCKPICK
                        case .generic:
                            successImage = C_GENERIC
                        }
                        
                        self.statusImage.image = successImage
                    }
                } catch let error as TegraDeviceError {
                    DispatchQueue.main.async { // todo separate function to reset prog bar oops
                        self.progressBar.doubleValue = 0.0
                        self.progressBar.isHidden = true
                    }
                    if case .BadId = error {
                        
                        self.showWarning(title: "Bad device ID.", body: "Device ID returned all zeroes. Please reboot RCM.")
                    } else if case .ProbablyAlreadyInRcm = error {
                        if !self.doAutopush {
                            self.showWarning(title: "Bad device state.", body: "You have probably already launched a payload, or a previous launch got interrupted.\nPlease reboot RCM.")
                        } else {
                            self.addConsoleLine(line: "[warning] Auto-push is on, but push failed because the console is in an invalid state.")
                        }
                    }
                    if case .IoReadPipeError(let desc) = error {
                        self.showWarning(title: "Error during `ReadPipeTO`.", body: "Couldn't read device ID; the connection is probably bad. Please try again with a different cable/USB port.")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.progressBar.doubleValue = 0.0
                        self.addConsoleLine(line: "[fatal] \(error)")
                    }
                }
            }
        } catch let error {
            addConsoleLine(line: "[error] Couldn't read payload file: \"\(error)\"")
        }
    }
    
    @IBAction func onPushPress(_ sender: Any) {
        go()
    }
    
    @objc func onPayloadTypeInferred(notification: NSNotification) {
        if let typeRawValue = notification.object as? Int,
           let type = NXPayload(rawValue: typeRawValue) {
            inferredPayloadType = type
        }
    }
    
    @objc func usbConnected(notification: NSNotification) {
        guard let nobj = notification.object as? NSDictionary else {
            return
        }

        guard let deviceInfo:USBDevice = nobj["device"] as? USBDevice else {
            return
        }
        
        if (deviceInfo.vendorId == VID.RCM.rawValue) && (deviceInfo.productId == PID.RCM.rawValue) {
            let device = TegraDevice(deviceInfo)
            DispatchQueue.main.async {
                self.devices.append(device)
                self.addConsoleLine(line: "RCM device connected.")
                self.statusImage.image = READY
                if !self.cbPayloadPaths.stringValue.isEmpty {
                    self.canPush = true // for hold shift logic...when stop holding shift check if bt can beenabled etc
                    self.tryEnablePushBtn()
                    if self.doAutopush {
                        self.go()
                    }
                } else {
                    self.canPush = false
                    self.disablePushBtn()
                }
            }
        }
        if (deviceInfo.vendorId == VID.NX.rawValue) && (deviceInfo.productId == PID.NX.rawValue) {
            let device = TegraDevice(deviceInfo)
            DispatchQueue.main.async {
                self.devices.append(device)
                self.addConsoleLine(line: "Non-RCM Switch connected.")
                if !self.shutupWarn {
                    self.showWarning(title: "Non-RCM switch detected.", body: "You have just connected a Nintendo Switch device which is not in RCM.")
                    self.shutupWarn = true
                }
            }
        }
    }
    
    @objc func usbDisconnected(notification: NSNotification) {
        guard let nobj = notification.object as? NSDictionary else {
            return
        }
        
        guard let id:UInt64 = nobj["id"] as? UInt64 else {
            return
        }
        
        DispatchQueue.main.async {
            if let index = self.devices.firstIndex(where: { $0.deviceInfo.id == id }) {
                self.devices.remove(at: index)
                self.addConsoleLine(line: "Disconnected")
                self.progressBar.isHidden = true
                self.statusImage.image = WAITING
                self.connectedDevice = nil
                self.disablePushBtn()
                self.canPush = false
            }
        }
    }

    @objc func onMenubarOpen(notification: NSNotification) {
        selectBlob()
    }
    
    @IBAction func onMenubarPayloadPress(_ sender: Any) {
        onPushPress(sender)
    }
    
    @IBAction func onPayloadPress(_ sender: Any) {
        selectBlob()
    }
    
    func selectBlob() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["bin"]
        let clicked = panel.runModal()
        
        if clicked == NSApplication.ModalResponse.OK, let url = panel.url {
            let payloadPath: String
            if #available(macOS 13.0, *) {
                payloadPath = url.path()
            } else {
                payloadPath = url.path
            }
            
            addRecentPath(payloadPath)
            cbPayloadPaths.stringValue = payloadPath
            addConsoleLine(line: "Payload set to \(url.lastPathComponent)")
            
            // probably not great, but don't enable button unless there actually is a device connected
            if let device = devices.first(where: {
                $0.deviceInfo.vendorId == VID.RCM.rawValue &&
                $0.deviceInfo.productId == PID.RCM.rawValue
            }) {
                tryEnablePushBtn()
            } else {
                disablePushBtn()
            }
        }
    }
    
    private func setAutopushOn(_ state: Int) {
        UserDefaults.standard.set(state, forKey: autopushKey)
        UserDefaults.standard.synchronize()
    }
    
    private func addRecentPath(_ path: String) {
        var paths = UserDefaults.standard.array(forKey: recentPathsKey) as? [String] ?? []
        
        paths.removeAll { $0 == path }
        
        paths.insert(path, at: 0)
        
        if paths.count > maxRecentPaths {
            paths = Array(paths.prefix(maxRecentPaths))
        }
        
        UserDefaults.standard.set(paths, forKey: recentPathsKey)
        UserDefaults.standard.synchronize()
        
        DispatchQueue.main.async {
            self.cbPayloadPaths.removeAllItems()
            self.cbPayloadPaths.addItems(withObjectValues: paths)
            self.cbPayloadPaths.stringValue = path
        }
    }
    
    
    func showWarning(title: String, body: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = body
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .warning
            alert.icon = NSImage(named: NSImage.cautionName)
            alert.runModal()
        }
    }

    
    override var representedObject: Any? {
        didSet {
        }
    }
}
