//
//  TegraDevice.swift
//  CrystalRCM-DX
//
//  Created by Robert Dale on 30/01/2022.
//

//
//  STM32Device.swift
//  STM32DeviceExample
//
//  Created by Artem Hruzd on 6/12/17.
//  Copyright © 2017 Artem Hruzd. All rights reserved.
//

import Cocoa
import USBDeviceSwift


enum TEGRAREQUEST:UInt8 {
    case STANDARD_REQUEST_DEVICE_TO_HOST_TO_ENDPOINT = 0x82
    case STANDARD_REQUEST_DEVICE_TO_HOST   = 0x80
    case GET_DESCRIPTOR    = 0x6
    case GET_CONFIGURATION = 0x8
    case GET_STATUS        = 0x0
}

enum VID:UInt16 {
    case RCM = 0x0955
    case NX = 0x057E
}

enum PID:UInt16 {
    case RCM = 0x7321
    case NX = 0x2000
}

enum TegraDeviceError: Error {
    case DeviceInterfaceNotFound
    case InvalidData(desc:String)
    case RequestError(desc:String)
}

class TegraDevice {
    var deviceInfo:USBDevice
    
    required init(_ deviceInfo:USBDevice) {
        self.deviceInfo = deviceInfo
    }
    
    func getStatus() throws -> [UInt8] {
        //Getting device interface from our pointer
        guard let deviceInterface = self.deviceInfo.deviceInterfacePtrPtr?.pointee?.pointee else {
            throw TegraDeviceError.DeviceInterfaceNotFound
        }
        
        var kr:Int32 = 0
        let length:Int = 6
        var requestPtr:[UInt8] = [UInt8](repeating: 0, count: length)
        // Creating request
        var request = IOUSBDevRequest(bmRequestType: TEGRAREQUEST.STANDARD_REQUEST_DEVICE_TO_HOST_TO_ENDPOINT.rawValue,
                                      bRequest: TEGRAREQUEST.GET_STATUS.rawValue,
                                      wValue: 0,
                                      wIndex: 0,
                                      wLength: UInt16(length),
                                      pData: &requestPtr,
                                      wLenDone: 255)
        
        kr = deviceInterface.DeviceRequest(self.deviceInfo.deviceInterfacePtrPtr, &request)
        
        if (kr != kIOReturnSuccess) {
            throw TegraDeviceError.RequestError(desc: "Get device status request error: \(kr)")
        }
        
        return requestPtr
    }
}

