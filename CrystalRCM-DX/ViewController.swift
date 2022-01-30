//
//  ViewController.swift
//  CrystalRCM-DX
//
//  Created by Robert Dale on 28/01/2022.
//

import Cocoa
import USBDeviceSwift

class ViewController: NSViewController {
    
    @IBOutlet var consoleOutputBox: NSTextView!
    @IBOutlet weak var statusImage: NSImageView!
    
    var connectedDevice:TegraDevice?
    var devices:[TegraDevice] = []
    
    func addConsoleLine(line: String) {
        let msg: NSAttributedString = NSAttributedString(string: line + "\n")
        consoleOutputBox.textStorage?.append(msg)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self, selector: #selector(self.usbConnected), name: .USBDeviceConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.usbDisconnected), name: .USBDeviceDisconnected, object: nil)

    }

    @IBAction func onPushPress(_ sender: Any) {
        
        
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
                self.addConsoleLine(line: "Connected - RCM")
                self.statusImage.image = READY
            }
        }
        if (deviceInfo.vendorId == VID.NX.rawValue) && (deviceInfo.productId == PID.NX.rawValue) {
            let device = TegraDevice(deviceInfo)
            DispatchQueue.main.async {
                self.devices.append(device)
                self.addConsoleLine(line: "Connected - non RCM")
                self.warnUser()
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
            if let index = self.devices.index(where: { $0.deviceInfo.id == id }) {
                self.devices.remove(at: index)
                self.addConsoleLine(line: "Disonnected")
                self.statusImage.image = WAITING
                self.connectedDevice = nil
            }
        }
    }

    @IBAction func onPayloadPress(_ sender: Any) {
        let panel                     = NSOpenPanel()
        panel.canChooseDirectories    = false
        panel.canChooseFiles          = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes        = ["bin"]
        let clicked                   = panel.runModal()

        if clicked == NSApplication.ModalResponse.OK {
            addConsoleLine(line: "\(panel.urls)")
        }
    }
    
    func warnUser() {
        let alert = NSAlert()
        alert.messageText = "what"
        alert.informativeText = "Piss My Pants .com"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.icon = NSImage(named: NSImage.cautionName)
        alert.runModal()
    }
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


}

