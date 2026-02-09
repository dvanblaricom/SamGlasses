//
//  TTSManager.swift
//  SamGlasses
//
//  Handles text-to-speech using OpenClaw Edge TTS service
//

import Foundation
import AVFoundation
import Combine

/// Manages text-to-speech conversion and playback through glasses speakers
@MainActor
class TTSManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isGenerating = false
    @Published var isSpeaking = false
    @Published var availableVoices: [TTSVoice] = []
    @Published var selectedVoice = "nova" // Default voice
    
    // MARK: - Configuration
    @Published var speechRate: Float = 1.0
    @Published var speechPitch: Float = 1.0
    @Published var speechVolume: Float = 1.0
    
    // MARK: - Dependencies
    weak var openClawClient: OpenClawClient?
    weak var audioManager: AudioManager?
    
    // MARK: - Internal Components
    private var speechSynthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    
    init() {
        setupSpeechSynthesizer()
        setupAvailableVoices()
    }
    
    // MARK: - Setup
    private func setupSpeechSynthesizer() {
        speechSynthesizer.delegate = self
    }
    
    private func setupAvailableVoices() {
        // Common Edge TTS voices - would be better to fetch from API
        availableVoices = [
            TTSVoice(id: "nova", name: "Nova", language: "en-US", gender: .female),
            TTSVoice(id: "alloy", name: "Alloy", language: "en-US", gender: .neutral),
            TTSVoice(id: "echo", name: "Echo", language: "en-US", gender: .male),
            TTSVoice(id: "fable", name: "Fable", language: "en-GB", gender: .male),
            TTSVoice(id: "onyx", name: "Onyx", language: "en-US", gender: .male),
            TTSVoice(id: "shimmer", name: "Shimmer", language: "en-US", gender: .female)
        ]
    }
    
    // MARK: - TTS Generation and Playback
    
    /// Generate speech audio from text using OpenClaw Edge TTS
    func speakText(_ text: String, useCloudTTS: Bool = true) async throws {
        guard !text.isEmpty else { return }
        
        if useCloudTTS {
            await speakWithCloudTTS(text)
        } else {
            await speakWithSystemTTS(text)
        }
    }
    
    /// Use OpenClaw Edge TTS (preferred method)
    private func speakWithCloudTTS(_ text: String) async {
        guard let openClawClient = openClawClient else {
            print("OpenClaw client not available, falling back to system TTS")
            await speakWithSystemTTS(text)
            return
        }
        
        isGenerating = true
        
        do {
            // Generate TTS audio
            let audioData = try await openClawClient.requestTTS(text: text)
            
            isGenerating = false
            isSpeaking = true
            
            // Play through audio manager (to route to glasses speakers)
            if let audioManager = audioManager {
                try await audioManager.playAudio(data: audioData)
            } else {
                // Fallback to AVAudioPlayer directly
                let audioPlayer = try AVAudioPlayer(data: audioData)
                audioPlayer.play()
                
                // Wait for playback to complete (simplified)
                while audioPlayer.isPlaying {
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }
            
            isSpeaking = false
            
        } catch {
            isGenerating = false
            isSpeaking = false
            
            print("Cloud TTS failed: \(error), falling back to system TTS")
            await speakWithSystemTTS(text)
        }
    }
    
    /// Fallback to system TTS
    private func speakWithSystemTTS(_ text: String) async {
        stopSpeaking() // Stop any current speech
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = speechRate * AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = speechPitch
        utterance.volume = speechVolume
        
        // Try to find a voice that matches selected voice characteristics
        if let voice = findSystemVoice() {
            utterance.voice = voice
        }
        
        currentUtterance = utterance
        isSpeaking = true
        
        speechSynthesizer.speak(utterance)
    }
    
    /// Find appropriate system voice based on selected TTS voice
    private func findSystemVoice() -> AVSpeechSynthesisVoice? {
        let selectedTTSVoice = availableVoices.first { $0.id == selectedVoice }
        let language = selectedTTSVoice?.language ?? "en-US"
        
        // Try to find a voice matching the language and gender preference
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // First, try exact language match
        let languageMatches = voices.filter { $0.language == language }
        if !languageMatches.isEmpty {
            return languageMatches.first
        }
        
        // Fallback to language code match (e.g., "en" from "en-US")
        let languageCode = String(language.prefix(2))
        let languageCodeMatches = voices.filter { $0.language.hasPrefix(languageCode) }
        if !languageCodeMatches.isEmpty {
            return languageCodeMatches.first
        }
        
        // Final fallback
        return AVSpeechSynthesisVoice(language: "en-US")
    }
    
    // MARK: - Playback Control
    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        audioManager?.stopPlayback()
        
        currentUtterance = nil
        isSpeaking = false
    }
    
    func pauseSpeaking() {
        speechSynthesizer.pauseSpeaking(at: .immediate)
    }
    
    func resumeSpeaking() {
        speechSynthesizer.continueSpeaking()
    }
    
    // MARK: - Configuration
    func setVoice(_ voiceId: String) {
        selectedVoice = voiceId
    }
    
    func setSpeechRate(_ rate: Float) {
        speechRate = max(0.1, min(2.0, rate)) // Clamp between 0.1 and 2.0
    }
    
    func setSpeechPitch(_ pitch: Float) {
        speechPitch = max(0.5, min(2.0, pitch)) // Clamp between 0.5 and 2.0
    }
    
    func setSpeechVolume(_ volume: Float) {
        speechVolume = max(0.0, min(1.0, volume)) // Clamp between 0.0 and 1.0
    }
    
    // MARK: - Voice Management
    func refreshAvailableVoices() async {
        // In a full implementation, this could fetch available voices from OpenClaw API
        // For now, we use the predefined list
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TTSManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        // Already set isSpeaking = true when we started
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if currentUtterance == utterance {
                isSpeaking = false
                currentUtterance = nil
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            currentUtterance = nil
        }
    }
}

// MARK: - Supporting Types
struct TTSVoice: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let gender: VoiceGender
}

enum VoiceGender {
    case male
    case female
    case neutral
}

// MARK: - Errors
enum TTSError: LocalizedError {
    case clientNotAvailable
    case audioGenerationFailed
    case playbackFailed
    
    var errorDescription: String? {
        switch self {
        case .clientNotAvailable:
            return "OpenClaw client not available"
        case .audioGenerationFailed:
            return "Failed to generate audio"
        case .playbackFailed:
            return "Failed to play audio"
        }
    }
}