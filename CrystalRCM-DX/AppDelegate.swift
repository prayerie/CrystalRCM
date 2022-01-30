//
//  AppDelegate.swift
//  CrystalRCM-DX
//
//  Created by Robert Dale on 28/01/2022.
//

import Cocoa
import USBDeviceSwift

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    let tegraMonitor = USBDeviceMonitor([
        USBMonitorData(vendorId: VID.RCM.rawValue, productId: PID.RCM.rawValue)
        ])

    let nxMonitor = USBDeviceMonitor([
        USBMonitorData(vendorId: VID.NX.rawValue, productId: PID.NX.rawValue)
        ])
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let tegraDaemon = Thread(target: tegraMonitor, selector:#selector(tegraMonitor.start), object: nil)
        tegraDaemon.start()
        
        let nxDaemon = Thread(target: nxMonitor, selector:#selector(nxMonitor.start), object: nil)
        nxDaemon.start()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }


}

