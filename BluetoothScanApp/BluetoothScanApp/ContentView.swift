//
//  ContentView.swift
//  BluetoothScanApp
//
//  Created by praful on 9/22/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some View {
        NavigationView {
            List {
                ForEach(bluetoothManager.discoveredPeripherals, id: \.peripheral.identifier) { (peripheral, rssi) in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(peripheral.name ?? "Unknown")
                                .font(.headline)
                            Text("RSSI: \(rssi)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        if bluetoothManager.isConnected(to: peripheral) {
                            Button(action: { bluetoothManager.disconnect(from: peripheral)}){
                                Text("Disconnect")
                                    .foregroundColor(.red)
                                    .padding(6)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(5)
                            }
                        } else {
                            Button(action: {
                                bluetoothManager.connect(to: peripheral)
                            }) {
                                Text("Connect")
                                    .foregroundColor(.blue)
                                    .padding(6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(5)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Bluetooth Devices")
        }
        .onAppear {
            bluetoothManager.discoveredPeripherals.removeAll() // Clear old data on appear
        }
    }
}
