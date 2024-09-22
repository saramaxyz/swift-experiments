import Foundation
import CoreBluetooth
import Combine
import AVFoundation

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var discoveredPeripherals: [(peripheral: CBPeripheral, rssi: NSNumber)] = []
    private var centralManager: CBCentralManager!
    
    let SERVICE_UUID = CBUUID(string: "19B10000-E8F2-537E-4F6C-D104768A1214")
    let CHARACTERISTIC_UUID = CBUUID(string: "19B10001-E8F2-537E-4F6C-D104768A1214")
    
    private var audioCharacteristic: CBCharacteristic?
    private var audioData: Data = Data()
    
    private var audioEngine: AVAudioEngine!
    private var audioPlayerNode: AVAudioPlayerNode!
    @Published var connectedPeripherals: Set<CBPeripheral> = []

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        setupAudio()
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            print("Bluetooth is not available.")
        }
    }
    
    func isConnected(to peripheral: CBPeripheral) -> Bool {
        return connectedPeripherals.contains(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, name == "Friend" else { return }
        
        if !discoveredPeripherals.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            discoveredPeripherals.append((peripheral, RSSI))
            discoveredPeripherals.sort { $0.rssi.intValue > $1.rssi.intValue }
        }
    }
    
    func connect(to peripheral: CBPeripheral) {
        centralManager.connect(peripheral, options: nil)
        connectedPeripherals.insert(peripheral)
    }
    
    func disconnect(from peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
        connectedPeripherals.remove(peripheral)
    }
    
//    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
//        print("Connected to \(peripheral.name ?? "unknown")")
//        peripheral.delegate = self
//        peripheral.discoverServices(nil) // Discover all services
//    }
//    
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
//        if let error = error {
//            print("Error discovering services: \(error.localizedDescription)")
//            return
//        }
//        
//        guard let services = peripheral.services else { return }
//        
//        for service in services {
//            print("Service UUID: \(service.uuid)")
//                // Optionally, discover characteristics for each service
//            peripheral.discoverCharacteristics(nil, for: service)
//        }
//    }
//    
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
//        if let error = error {
//            print("Error discovering characteristics for service \(service.uuid): \(error.localizedDescription)")
//            return
//        }
//        
//        guard let characteristics = service.characteristics else { return }
//        
//        for characteristic in characteristics {
//            print("Characteristic UUID: \(characteristic.uuid)")
//        }
//    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "unknown")")
        peripheral.delegate = self
        peripheral.discoverServices(nil) // Discover all services
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == SERVICE_UUID {
                peripheral.discoverCharacteristics(nil, for: service) // Discover characteristics for the audio service
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics for service \(service.uuid): \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == CHARACTERISTIC_UUID {
                audioCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic) // Start notifications
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, error == nil else { return }
        handleAudioData(data: data)
    }
    
    func handleAudioData(data: Data) {
            // Check if the data length is sufficient to avoid out-of-bounds
        guard data.count > 3 else { return }
        let dataSlice = data.subdata(in: 3..<data.count)
        print("Received Data: \(dataSlice.toHexString())")
        audioData.append(dataSlice)
        processAudio()
    }
    
    func processAudio() {
        guard audioData.count > 0 else {
            print("Warning: Received empty audio data array.")
            return
        }
        
        let filteredAudioData = filterAudioData(audioData)
        playAudio(filteredAudioData)
        audioData.removeAll()
    }
    
    func filterAudioData(_ audioData: Data) -> [Int16] {
        var trimmedData = audioData
        let remainder = trimmedData.count % MemoryLayout<Int16>.size
        if remainder != 0 {
            trimmedData.removeLast(remainder) // Remove excess bytes to align with Int16
        }
        
        let audioSamples = trimmedData.withUnsafeBytes {
            Array(UnsafeBufferPointer<Int16>(
                start: $0.baseAddress!.assumingMemoryBound(to: Int16.self),
                count: trimmedData.count / MemoryLayout<Int16>.size
            ))
        }
        
        return audioSamples
    }
    
    private func setupAudio() {
        audioEngine = AVAudioEngine()
        audioPlayerNode = AVAudioPlayerNode()
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
        
        audioEngine.attach(audioPlayerNode)
        audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: format)
        
        do {
            try audioEngine.start()
            print("Audio engine started.")
        } catch {
            print("Error starting audio engine: \(error.localizedDescription)")
        }
    }
    
    func printBufferAsHexString(_ buffer: AVAudioPCMBuffer) {
            // Check if the buffer contains float channel data (usually the case after conversion)
        if let channelData = buffer.floatChannelData {
                // Retrieve the frame length (number of samples)
            let frameLength = Int(buffer.frameLength)
            
                // Access the first channel's data (mono audio)
            let firstChannelData = channelData[0]
            
                // Convert float samples to their hex representation
            var hexString = ""
            for i in 0..<frameLength {
                let floatValue = firstChannelData[i]
                hexString += String(format: "%02hhx", floatValue) + " "
            }
            
                // Print the final hex string
            print("Buffer as hex string: \(hexString)")
        } else {
            print("No float channel data found in buffer.")
        }
    }

    func playAudio(_ audioSamples: [Int16]) {
            // Convert Int16 to UInt8 or directly to float for playback as needed
        let floatSamples = audioSamples.map { Float($0) / Float(Int16.max) } // Normalize to [-1.0, 1.0]
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(floatSamples.count)
        ) else {
            print("Failed to create AVAudioPCMBuffer.")
            return
        }
        
        buffer.frameLength = buffer.frameCapacity
        
        let channelData = buffer.floatChannelData![0]
        for i in 0..<floatSamples.count {
            channelData[i] = floatSamples[i]
        }
        
        audioPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops) {
            print("Audio buffer played \(self.printBufferAsHexString(buffer)).")
        }
        
        if !audioPlayerNode.isPlaying {
            audioPlayerNode.play()
            print("Audio player node started playing.")
        }
    }
}


extension Data {
    func toHexString() -> String {
        return self.map { String(format: "%02hhx", $0) }.joined()
    }
}
