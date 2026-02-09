//
//  SamGlassesApp.swift
//  SamGlasses
//
//  Created by OpenClaw on 2026-02-08.
//

import SwiftUI

@main
struct SamGlassesApp: App {
    // Initialize core services
    @StateObject private var openClawClient = OpenClawClient()
    @StateObject private var audioManager = AudioManager()
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var ttsManager = TTSManager()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(openClawClient)
                .environmentObject(audioManager)
                .environmentObject(speechManager)
                .environmentObject(ttsManager)
                .onAppear {
                    // Initialize services on app launch
                    setupServices()
                }
        }
    }
    
    /// Setup and configure services on app launch
    private func setupServices() {
        // Wire up service dependencies first
        speechManager.openClawClient = openClawClient
        ttsManager.audioManager = audioManager
        ttsManager.openClawClient = openClawClient
        
        // Load saved settings
        openClawClient.loadSettings()
        
        // Initialize services (deferred from init to avoid crashes)
        audioManager.setupAudioSession()
        speechManager.setup()
        speechManager.requestSpeechRecognitionPermission()
    }
}