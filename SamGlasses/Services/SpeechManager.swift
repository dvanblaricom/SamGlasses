//
//  SpeechManager.swift
//  SamGlasses
//
//  Handles speech recognition using Apple Speech framework and OpenClaw Whisper
//

import Foundation
import Speech
import Combine

/// Manages speech recognition with fallback between on-device and cloud services
@MainActor
class SpeechManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isSpeechRecognitionAvailable = false
    @Published var speechRecognitionPermission: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var partialText = ""
    
    // MARK: - Configuration
    @Published var useOnDeviceRecognition = true // Prefer on-device when available
    @Published var preferredLanguage = "en-US"
    
    // MARK: - Dependencies
    weak var openClawClient: OpenClawClient?
    
    // MARK: - Speech Recognition
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    override init() {
        super.init()
        setupSpeechRecognizer()
    }
    
    // MARK: - Setup
    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: preferredLanguage))
        speechRecognizer?.delegate = self
        
        isSpeechRecognitionAvailable = speechRecognizer?.isAvailable ?? false
        speechRecognitionPermission = SFSpeechRecognizer.authorizationStatus()
    }
    
    func requestSpeechRecognitionPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.speechRecognitionPermission = status
                self?.isSpeechRecognitionAvailable = status == .authorized && (self?.speechRecognizer?.isAvailable ?? false)
            }
        }
    }
    
    // MARK: - On-Device Speech Recognition
    func startListening() async throws {
        guard !isListening else { return }
        
        // Check permissions
        guard speechRecognitionPermission == .authorized else {
            throw SpeechError.permissionDenied
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        
        // Cancel any ongoing recognition
        stopListening()
        
        // Setup audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.setupFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Use on-device recognition when available
        if #available(iOS 13.0, *), useOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        // Setup audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                if let result = result {
                    self?.partialText = result.bestTranscription.formattedString
                    
                    if result.isFinal {
                        self?.recognizedText = result.bestTranscription.formattedString
                        self?.stopListening()
                    }
                }
                
                if let error = error {
                    print("Speech recognition error: \(error)")
                    self?.stopListening()
                }
            }
        }
        
        isListening = true
        recognizedText = ""
        partialText = ""
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isListening = false
    }
    
    // MARK: - Audio File Recognition
    
    /// Recognize speech from audio file using on-device recognition
    func recognizeSpeechFromFile(url: URL) async throws -> String {
        guard speechRecognitionPermission == .authorized else {
            throw SpeechError.permissionDenied
        }
        
        guard let speechRecognizer = speechRecognizer else {
            throw SpeechError.recognizerUnavailable
        }
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        
        // Use on-device when available
        if #available(iOS 13.0, *), useOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            speechRecognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
    
    /// Transcribe audio using OpenClaw Whisper service
    func transcribeWithWhisper(audioData: Data) async throws -> String {
        guard let openClawClient = openClawClient else {
            throw SpeechError.clientNotAvailable
        }
        
        return try await openClawClient.transcribeAudio(audioData: audioData)
    }
    
    /// Transcribe audio with automatic fallback between on-device and cloud
    func transcribeAudio(audioData: Data) async throws -> String {
        // Try on-device first if available and preferred
        if useOnDeviceRecognition && isSpeechRecognitionAvailable {
            do {
                // Save audio to temp file for on-device recognition
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("temp_audio.wav")
                try audioData.write(to: tempURL)
                
                let result = try await recognizeSpeechFromFile(url: tempURL)
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
                
                return result
            } catch {
                print("On-device recognition failed, falling back to Whisper: \(error)")
                // Fall through to Whisper
            }
        }
        
        // Fallback to OpenClaw Whisper
        return try await transcribeWithWhisper(audioData: audioData)
    }
    
    // MARK: - Configuration
    func setLanguage(_ languageCode: String) {
        preferredLanguage = languageCode
        setupSpeechRecognizer()
    }
    
    func setOnDeviceRecognition(_ enabled: Bool) {
        useOnDeviceRecognition = enabled
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension SpeechManager: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            self.isSpeechRecognitionAvailable = available
        }
    }
}

// MARK: - Errors
enum SpeechError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case setupFailed
    case clientNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition permission denied"
        case .recognizerUnavailable:
            return "Speech recognizer unavailable"
        case .setupFailed:
            return "Failed to setup speech recognition"
        case .clientNotAvailable:
            return "OpenClaw client not available"
        }
    }
}