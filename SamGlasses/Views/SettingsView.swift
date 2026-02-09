//
//  SettingsView.swift
//  SamGlasses
//
//  Settings and configuration view
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var openClawClient: OpenClawClient
    @EnvironmentObject private var audioManager: AudioManager
    @EnvironmentObject private var speechManager: SpeechManager
    @EnvironmentObject private var ttsManager: TTSManager
    
    @State private var authToken = ""
    @State private var gatewayURL = "https://daves-mac-studio.taile75ef.ts.net"
    @State private var selectedAudioDevice: AudioDevice?
    @State private var useOnDeviceSpeech = true
    @State private var preferredLanguage = "en-US"
    @State private var selectedVoice = "nova"
    @State private var speechRate: Float = 1.0
    @State private var wakeWordEnabled = false // Future feature
    @State private var showingTokenHelp = false
    
    var body: some View {
        NavigationView {
            Form {
                // OpenClaw Configuration
                Section("OpenClaw Gateway") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gateway URL")
                        TextField("https://your-gateway.example.com", text: $gatewayURL)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: gatewayURL) { newValue in
                                openClawClient.updateBaseURL(newValue)
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Auth Token")
                            Spacer()
                            Button("Help") {
                                showingTokenHelp = true
                            }
                            .font(.caption)
                        }
                        
                        SecureField("Enter your OpenClaw auth token", text: $authToken)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: authToken) { newValue in
                                if !newValue.isEmpty {
                                    openClawClient.updateAuthToken(newValue)
                                }
                            }
                    }
                    
                    HStack {
                        Text("Connection")
                        Spacer()
                        ConnectionStatusBadge(
                            isConnected: openClawClient.isConnected,
                            status: openClawClient.connectionStatus
                        )
                    }
                }
                
                // Audio Configuration
                Section("Audio Settings") {
                    if !audioManager.availableAudioDevices.isEmpty {
                        Picker("Audio Device", selection: $selectedAudioDevice) {
                            ForEach(audioManager.availableAudioDevices) { device in
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text(deviceTypeDescription(device.type))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .tag(device as AudioDevice?)
                            }
                        }
                        .onChange(of: selectedAudioDevice) { newValue in
                            if let device = newValue {
                                audioManager.selectAudioDevice(device)
                            }
                        }
                    } else {
                        Text("No audio devices found")
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("Bluetooth Status")
                        Spacer()
                        Text(audioManager.isBluetoothConnected ? "Connected" : "Disconnected")
                            .foregroundColor(audioManager.isBluetoothConnected ? .green : .red)
                    }
                }
                
                // Speech Recognition
                Section("Speech Recognition") {
                    Toggle("Use On-Device Recognition", isOn: $useOnDeviceSpeech)
                        .onChange(of: useOnDeviceSpeech) { newValue in
                            speechManager.setOnDeviceRecognition(newValue)
                        }
                    
                    Picker("Language", selection: $preferredLanguage) {
                        Text("English (US)").tag("en-US")
                        Text("English (UK)").tag("en-GB")
                        Text("Spanish").tag("es-ES")
                        Text("French").tag("fr-FR")
                        Text("German").tag("de-DE")
                        Text("Italian").tag("it-IT")
                        Text("Portuguese").tag("pt-BR")
                        Text("Japanese").tag("ja-JP")
                    }
                    .onChange(of: preferredLanguage) { newValue in
                        speechManager.setLanguage(newValue)
                    }
                    
                    HStack {
                        Text("Permission Status")
                        Spacer()
                        Text(speechPermissionStatus)
                            .foregroundColor(speechPermissionColor)
                    }
                    
                    if speechManager.speechRecognitionPermission != .authorized {
                        Button("Request Permission") {
                            speechManager.requestSpeechRecognitionPermission()
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                // Text-to-Speech
                Section("Text-to-Speech") {
                    Picker("Voice", selection: $selectedVoice) {
                        ForEach(ttsManager.availableVoices) { voice in
                            VStack(alignment: .leading) {
                                Text(voice.name)
                                Text("\(voice.language) • \(voice.gender.description)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .tag(voice.id)
                        }
                    }
                    .onChange(of: selectedVoice) { newValue in
                        ttsManager.setVoice(newValue)
                    }
                    
                    VStack {
                        HStack {
                            Text("Speech Rate")
                            Spacer()
                            Text(String(format: "%.1f", speechRate))
                                .foregroundColor(.gray)
                        }
                        
                        Slider(value: $speechRate, in: 0.5...2.0, step: 0.1)
                            .onChange(of: speechRate) { newValue in
                                ttsManager.setSpeechRate(newValue)
                            }
                    }
                    
                    Button("Test Voice") {
                        Task {
                            try? await ttsManager.speakText("Hello! This is a test of the selected voice.")
                        }
                    }
                    .disabled(ttsManager.isSpeaking)
                }
                
                // Future Features
                Section("Future Features") {
                    HStack {
                        Toggle("Wake Word Detection", isOn: $wakeWordEnabled)
                            .disabled(true)
                        
                        Text("Coming Soon")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("Camera Access")
                        Spacer()
                        Text("Requires Meta DAT")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                // About
                Section("About") {
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                    
                    Link("GitHub Repository", destination: URL(string: "https://github.com/dvanblaricom/SamGlasses")!)
                    
                    Link("OpenClaw Documentation", destination: URL(string: "https://docs.openclaw.ai")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSettings()
            }
            .alert("Auth Token Help", isPresented: $showingTokenHelp) {
                Button("OK") { }
            } message: {
                Text("Get your OpenClaw auth token from the OpenClaw dashboard or by running 'openclaw auth token' in your terminal.")
            }
        }
    }
    
    // MARK: - Helper Methods
    private func loadSettings() {
        authToken = KeychainHelper.shared.getAuthToken() ?? ""
        gatewayURL = openClawClient.baseURL
        selectedAudioDevice = audioManager.currentAudioDevice
        useOnDeviceSpeech = speechManager.useOnDeviceRecognition
        preferredLanguage = speechManager.preferredLanguage
        selectedVoice = ttsManager.selectedVoice
        speechRate = ttsManager.speechRate
    }
    
    private var speechPermissionStatus: String {
        switch speechManager.speechRecognitionPermission {
        case .notDetermined:
            return "Not Requested"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .authorized:
            return "Authorized"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var speechPermissionColor: Color {
        switch speechManager.speechRecognitionPermission {
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }
    
    private func deviceTypeDescription(_ type: AudioDeviceType) -> String {
        switch type {
        case .bluetoothHFP:
            return "Bluetooth HFP"
        case .builtInSpeaker:
            return "Built-in Speaker"
        case .builtInMicrophone:
            return "Built-in Microphone"
        case .other:
            return "Other"
        }
    }
}

// MARK: - Supporting Views
struct ConnectionStatusBadge: View {
    let isConnected: Bool
    let status: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(status)
                .font(.caption)
                .foregroundColor(isConnected ? .green : .red)
        }
    }
}

// MARK: - Extensions
extension VoiceGender {
    var description: String {
        switch self {
        case .male:
            return "Male"
        case .female:
            return "Female"
        case .neutral:
            return "Neutral"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(OpenClawClient())
        .environmentObject(AudioManager())
        .environmentObject(SpeechManager())
        .environmentObject(TTSManager())
}
