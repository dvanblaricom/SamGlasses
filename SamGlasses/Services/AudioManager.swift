//
//  AudioManager.swift
//  SamGlasses
//
//  Handles Bluetooth HFP audio routing for Meta Ray-Ban glasses
//

import Foundation
import AVFoundation
import Combine

/// Manages audio routing, recording, and playback for Bluetooth glasses
@MainActor
class AudioManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isBluetoothConnected = false
    @Published var availableAudioDevices: [AudioDevice] = []
    @Published var currentAudioDevice: AudioDevice?
    @Published var isRecording = false
    @Published var isPlaying = false
    
    // MARK: - Audio Components
    private var audioEngine = AVAudioEngine()
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private let audioSession = AVAudioSession.sharedInstance()
    
    // MARK: - Recording
    private var recordingURL: URL?
    
    override init() {
        super.init()
        // Defer audio setup until explicitly called — initializing
        // AVAudioSession too early crashes on real devices
    }
    
    // MARK: - Audio Session Setup
    func setupAudioSession() {
        do {
            // Configure audio session for Bluetooth HFP
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetoothA2DP, .allowAirPlay, .allowBluetooth]
            )
            
            try audioSession.setActive(true)
            
            // Start monitoring audio route changes
            startMonitoringAudioRoutes()
            
            // Update device list
            updateAvailableDevices()
            
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Device Management
    private func startMonitoringAudioRoutes() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        // Also monitor for interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    @objc private func audioRouteChanged() {
        Task { @MainActor in
            updateAvailableDevices()
            checkBluetoothConnection()
        }
    }
    
    private func updateAvailableDevices() {
        var devices: [AudioDevice] = []
        
        // Built-in devices
        devices.append(AudioDevice(
            id: "built-in-speaker",
            name: "iPhone Speaker",
            type: .builtInSpeaker
        ))
        
        devices.append(AudioDevice(
            id: "built-in-mic",
            name: "iPhone Microphone",
            type: .builtInMicrophone
        ))
        
        // Check current audio route for Bluetooth devices
        let currentRoute = audioSession.currentRoute
        let btTypes: [AVAudioSession.Port] = [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE]
        
        for output in currentRoute.outputs {
            if btTypes.contains(output.portType) {
                devices.append(AudioDevice(
                    id: output.uid,
                    name: output.portName,
                    type: .bluetoothHFP
                ))
            }
        }
        
        for input in currentRoute.inputs {
            if btTypes.contains(input.portType) {
                devices.append(AudioDevice(
                    id: input.uid,
                    name: input.portName,
                    type: .bluetoothHFP
                ))
            }
        }
        
        availableAudioDevices = devices
        
        // Set current device (prefer Bluetooth HFP)
        currentAudioDevice = devices.first { $0.type == .bluetoothHFP } ?? devices.first
    }
    
    private func checkBluetoothConnection() {
        let route = audioSession.currentRoute
        let btTypes: [AVAudioSession.Port] = [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE]
        isBluetoothConnected = route.outputs.contains { btTypes.contains($0.portType) } ||
                               route.inputs.contains { btTypes.contains($0.portType) }
    }
    
    func selectAudioDevice(_ device: AudioDevice) {
        // iOS automatically routes to available Bluetooth devices
        // We can prefer certain ports but can't force specific routing
        currentAudioDevice = device
    }
    
    // MARK: - Audio Recording
    func startRecording() async throws -> URL {
        guard !isRecording else { return recordingURL! }
        
        // Request microphone permission
        let permission = await requestMicrophonePermission()
        guard permission else {
            throw AudioError.microphonePermissionDenied
        }
        
        // Create recording URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsPath.appendingPathComponent("recording-\(Date().timeIntervalSince1970).wav")
        
        // Configure recording settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.delegate = self
            
            // Ensure we're using the microphone (prefer Bluetooth)
            try audioSession.setCategory(.record, mode: .voiceChat, options: .allowBluetooth)
            try audioSession.setActive(true)
            
            audioRecorder?.record()
            isRecording = true
            
            return recordingURL!
            
        } catch {
            throw AudioError.recordingFailed(error.localizedDescription)
        }
    }
    
    func stopRecording() async -> URL? {
        guard isRecording, let recorder = audioRecorder else { return nil }
        
        recorder.stop()
        isRecording = false
        
        // Reset audio session for playback
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
        
        return recordingURL
    }
    
    // MARK: - Audio Playback
    func playAudio(data: Data) async throws {
        guard !isPlaying else { return }
        
        do {
            // Configure for playback (prefer Bluetooth speakers)
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
            
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            
            isPlaying = true
            audioPlayer?.play()
            
        } catch {
            isPlaying = false
            throw AudioError.playbackFailed(error.localizedDescription)
        }
    }
    
    func playAudioFile(url: URL) async throws {
        guard !isPlaying else { return }
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
            
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            
            isPlaying = true
            audioPlayer?.play()
            
        } catch {
            isPlaying = false
            throw AudioError.playbackFailed(error.localizedDescription)
        }
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
    }
    
    // MARK: - Permissions
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - AVAudioRecorderDelegate
extension AudioManager: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.isRecording = false
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.isRecording = false
        }
        print("Recording error: \(error?.localizedDescription ?? "Unknown")")
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.isPlaying = false
        }
        print("Playback error: \(error?.localizedDescription ?? "Unknown")")
    }
}

// MARK: - Supporting Types
struct AudioDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let type: AudioDeviceType
}

enum AudioDeviceType {
    case bluetoothHFP
    case builtInSpeaker
    case builtInMicrophone
    case other
}

enum AudioError: LocalizedError {
    case microphonePermissionDenied
    case recordingFailed(String)
    case playbackFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission denied"
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .playbackFailed(let reason):
            return "Playback failed: \(reason)"
        }
    }
}