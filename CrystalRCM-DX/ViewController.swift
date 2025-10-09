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
    
    var connectedDevice:TegraDevice?
    var devices:[TegraDevice] = []
    var shutupWarn = false
    
    private var inferredPayloadType: NXPayload = .generic
    private let recentPathsKey = "RecentPayloadPaths"
    private let maxRecentPaths = 5
    
    private let ver = "0.1.3"
    private let crystalrcmGh = "https://api.github.com/repos/prayerie/CrystalRCM/releases/latest"

    
    func addConsoleLine(line: String) {
        let msg: NSAttributedString = NSAttributedString(string: line + "\n")
        consoleOutputBox.textStorage?.append(msg)
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
        

        btPush.isEnabled = false // don't want any pushes before a payload is chosen
        
        cbPayloadPaths.removeAllItems() // remove annoying 'Item 1' 'Item 2' etc
        
        if let paths = UserDefaults.standard.array(forKey: recentPathsKey) as? [String] {
            cbPayloadPaths.removeAllItems()
            cbPayloadPaths.addItems(withObjectValues: paths)
            if !paths.isEmpty {
                cbPayloadPaths.stringValue = paths[0]
            }
        }
        
        
        
        lbUpdate.isHidden = true
        checkForUpdates()
    }
    
    override func viewWillDisappear() {
        exit(0)
    }


    
    @objc func onProgressUpdate(notification: NSNotification) {
        let p = notification.userInfo?["by"] as? Double ?? 0.0
        DispatchQueue.main.async {
            self.progressBar.isHidden = false
            self.progressBar.doubleValue = p
        }
        
        
    }
    
    @IBAction func onPushPress(_ sender: Any) {
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
                    if case .BadId = error {
                        DispatchQueue.main.async {
                            self.progressBar.doubleValue = 0.0
                            self.warnUserBadId()
                        }
                    }
                    DispatchQueue.main.async {
                        self.progressBar.doubleValue = 0.0
                        self.addConsoleLine(line: "[error] \(error)")
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
                    self.btPush.isEnabled = true
                }
            }
        }
        if (deviceInfo.vendorId == VID.NX.rawValue) && (deviceInfo.productId == PID.NX.rawValue) {
            let device = TegraDevice(deviceInfo)
            DispatchQueue.main.async {
                self.devices.append(device)
                self.addConsoleLine(line: "Non-RCM Switch connected.")
                if !self.shutupWarn {
                    self.warnUser()
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
                self.statusImage.image = WAITING
                self.connectedDevice = nil
                self.btPush.isEnabled = false
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
                btPush.isEnabled = true
            } else {
                btPush.isEnabled = false
            }
        }
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
        
        cbPayloadPaths.removeAllItems()
        cbPayloadPaths.addItems(withObjectValues: paths)
        cbPayloadPaths.stringValue = path
    }
    
    func warnUser() {
        let alert = NSAlert()
        alert.messageText = "Non-RCM switch detected."
        alert.informativeText = "You have just connected a Nintendo Switch device which is not in RCM."
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .warning
        alert.icon = NSImage(named: NSImage.cautionName)
        alert.runModal()
    }
    
    func warnUserBadId() {
        let alert = NSAlert()
        alert.messageText = "Bad device ID."
        alert.informativeText = "Device ID returned all zeroes. Please reboot RCM."
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .warning
        alert.icon = NSImage(named: NSImage.cautionName)
        alert.runModal()
    }
    
    override var representedObject: Any? {
        didSet {
        }
    }
}
