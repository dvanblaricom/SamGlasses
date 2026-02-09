//
//  MainView.swift
//  SamGlasses
//
//  Main interface for Sam Glasses companion app
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject private var openClawClient: OpenClawClient
    @EnvironmentObject private var audioManager: AudioManager
    @EnvironmentObject private var speechManager: SpeechManager
    @EnvironmentObject private var ttsManager: TTSManager
    
    @State private var showingSettings = false
    @State private var isRecording = false
    @State private var recordingURL: URL?
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Connection Status Section
                connectionStatusView
                
                Spacer()
                
                // Main Action Buttons
                actionButtonsView
                
                Spacer()
                
                // Conversation History
                conversationHistoryView
            }
            .padding()
            .navigationTitle("Sam Glasses")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
    
    // MARK: - Connection Status
    private var connectionStatusView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Connection Status")
                    .font(.headline)
                Spacer()
            }
            
            HStack(spacing: 16) {
                StatusIndicator(
                    title: "OpenClaw",
                    isConnected: openClawClient.isConnected,
                    status: openClawClient.connectionStatus
                )
                
                StatusIndicator(
                    title: "Bluetooth",
                    isConnected: audioManager.isBluetoothConnected,
                    status: audioManager.isBluetoothConnected ? "Connected" : "Disconnected"
                )
                
                StatusIndicator(
                    title: "Speech",
                    isConnected: speechManager.isSpeechRecognitionAvailable,
                    status: speechManager.isSpeechRecognitionAvailable ? "Ready" : "Unavailable"
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    private var actionButtonsView: some View {
        VStack(spacing: 24) {
            // Talk Button (Main)
            Button {
                Task {
                    await handleTalkButton()
                }
            } label: {
                VStack {
                    Image(systemName: isRecording ? "stop.circle" : "mic.circle")
                        .font(.system(size: 60))
                        .foregroundColor(isRecording ? .red : .blue)
                    
                    Text(isRecording ? "Stop Recording" : "Tap to Talk")
                        .font(.title2)
                        .fontWeight(.medium)
                }
                .frame(width: 200, height: 120)
                .background(
                    Circle()
                        .fill(isRecording ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                        .scaleEffect(1.2)
                )
            }
            .disabled(openClawClient.isProcessing || ttsManager.isSpeaking)
            
            // Camera Button (Placeholder)
            HStack(spacing: 20) {
                Button {
                    // Placeholder for camera capture
                    handleCameraCapture()
                } label: {
                    VStack {
                        Image(systemName: "camera.circle")
                            .font(.system(size: 40))
                        Text("Capture")
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                }
                .disabled(true) // Disabled until DAT access available
                
                // Quick Actions
                Button {
                    Task {
                        await handleQuickMessage("What am I looking at?")
                    }
                } label: {
                    VStack {
                        Image(systemName: "eye.circle")
                            .font(.system(size: 40))
                        Text("Identify")
                            .font(.caption)
                    }
                    .foregroundColor(.purple)
                }
                .disabled(!openClawClient.isConnected)
                
                Button {
                    Task {
                        await handleQuickMessage("What should I do next?")
                    }
                } label: {
                    VStack {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 40))
                        Text("Ask")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                }
                .disabled(!openClawClient.isConnected)
            }
        }
    }
    
    // MARK: - Conversation History
    private var conversationHistoryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Conversation")
                    .font(.headline)
                
                Spacer()
                
                if !openClawClient.conversations.isEmpty {
                    Button("Clear") {
                        openClawClient.clearConversation()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(openClawClient.conversations.suffix(5)) { message in
                        MessageBubble(message: message)
                    }
                }
            }
            .frame(maxHeight: 200)
            
            if openClawClient.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    private func handleTalkButton() async {
        if isRecording {
            // Stop recording and process
            await stopRecordingAndProcess()
        } else {
            // Start recording
            await startRecording()
        }
    }
    
    private func startRecording() async {
        do {
            recordingURL = try await audioManager.startRecording()
            isRecording = true
        } catch {
            showError("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    private func stopRecordingAndProcess() async {
        isRecording = false
        
        guard let audioURL = await audioManager.stopRecording() else {
            showError("No recording to process")
            return
        }
        
        do {
            // Load audio data
            let audioData = try Data(contentsOf: audioURL)
            
            // Transcribe audio
            let transcription = try await speechManager.transcribeAudio(audioData: audioData)
            
            // Send to OpenClaw and get response
            let response = try await openClawClient.sendMessage(transcription)
            
            // Speak the response
            try await ttsManager.speakText(response)
            
        } catch {
            showError("Processing failed: \(error.localizedDescription)")
        }
    }
    
    private func handleQuickMessage(_ message: String) async {
        do {
            let response = try await openClawClient.sendMessage(message)
            try await ttsManager.speakText(response)
        } catch {
            showError("Failed to send message: \(error.localizedDescription)")
        }
    }
    
    private func handleCameraCapture() {
        // Placeholder for camera capture functionality
        showError("Camera access not yet implemented. Requires DAT (Device Access Token) from Meta.")
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Supporting Views
struct StatusIndicator: View {
    let title: String
    let isConnected: Bool
    let status: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            Text(status)
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MessageBubble: View {
    let message: ConversationMessage
    
    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer()
            }
            
            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.isFromUser ? Color.blue : Color(.systemGray5))
                    )
                    .foregroundColor(message.isFromUser ? .white : .primary)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            if !message.isFromUser {
                Spacer()
            }
        }
    }
}

#Preview {
    MainView()
        .environmentObject(OpenClawClient())
        .environmentObject(AudioManager())
        .environmentObject(SpeechManager())
        .environmentObject(TTSManager())
}