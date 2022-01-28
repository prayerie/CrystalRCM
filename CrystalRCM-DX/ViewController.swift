//
//  ViewController.swift
//  CrystalRCM-DX
//
//  Created by Robert Dale on 28/01/2022.
//

import Cocoa

class ViewController: NSViewController {
    
    @IBOutlet var consoleOutputBox: NSTextView!
    
    
    
    func addConsoleLine(line: String) {
        let msg: NSAttributedString = NSAttributedString(string: line)
        consoleOutputBox.textStorage?.append(msg)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    @IBAction func onPushPress(_ sender: Any) {
        
        
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
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


}

