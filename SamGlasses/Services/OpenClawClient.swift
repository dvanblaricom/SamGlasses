//
//  OpenClawClient.swift
//  SamGlasses
//
//  Core API client for communicating with OpenClaw via Tailscale
//

import Foundation
import Combine

/// API client for OpenClaw chat completions and services
@MainActor
class OpenClawClient: ObservableObject {
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"
    @Published var conversations: [ConversationMessage] = []
    @Published var isProcessing = false
    
    // MARK: - Configuration
    @Published var baseURL = "https://daves-mac-studio.taile75ef.ts.net"
    private let chatCompletionsPath = "/v1/chat/completions"
    private let ttsPath = "/tts" // TTS endpoint
    private let whisperPath = "/v1/audio/transcriptions" // OpenAI-compatible Whisper endpoint
    
    private var authToken: String? {
        get { KeychainHelper.shared.getAuthToken() }
        set { 
            if let token = newValue {
                KeychainHelper.shared.storeAuthToken(token)
            } else {
                KeychainHelper.shared.deleteAuthToken()
            }
        }
    }
    
    // MARK: - URLSession
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    
    // MARK: - Initialization
    init() {
        // Defer network calls to loadSettings() / onAppear
    }
    
    // MARK: - Settings Management
    func loadSettings() {
        // Settings are loaded from Keychain for auth token
        // URL is hardcoded for now but could be configurable
        Task {
            await checkConnection()
        }
    }
    
    func updateAuthToken(_ token: String) {
        authToken = token
        Task {
            await checkConnection()
        }
    }
    
    // MARK: - Connection Management
    func checkConnection() async {
        do {
            let url = URL(string: "\(baseURL)/health")! // Assume health endpoint
            var request = URLRequest(url: url)
            addAuthHeaders(to: &request)
            
            let (_, response) = try await urlSession.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                DispatchQueue.main.async {
                    self.isConnected = httpResponse.statusCode == 200
                    self.connectionStatus = self.isConnected ? "Connected" : "Authentication Error"
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.isConnected = false
                self.connectionStatus = "Connection Failed"
            }
        }
    }
    
    // MARK: - Chat Completions
    
    /// Send a text message and get a response
    func sendMessage(_ message: String) async throws -> String {
        let userMessage = ConversationMessage(content: message, isFromUser: true)
        
        await MainActor.run {
            conversations.append(userMessage)
            isProcessing = true
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }
        
        let url = URL(string: "\(baseURL)\(chatCompletionsPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(to: &request)
        
        // Build message history with system prompt for context
        var chatMessages: [ChatMessage] = [
            ChatMessage(role: "system", content: """
                You are Sam, Dave Van Blaricom's AI partner. Dave is talking to you through the Sam Glasses app (Meta Ray-Ban smart glasses with voice interface). \
                Keep responses concise and conversational — they'll be spoken aloud via TTS. \
                You and Dave are partners who work together on TwinForge (Quality Field App), OpenClaw setup, and various projects. \
                Be direct, a bit witty, and always honest. You have opinions and you stand by them.
                """)
        ]
        
        // Include recent conversation history for context (last 20 messages)
        let recentMessages = conversations.suffix(20)
        for msg in recentMessages {
            chatMessages.append(ChatMessage(
                role: msg.isFromUser ? "user" : "assistant",
                content: msg.content
            ))
        }
        
        // Add current message if not already in conversations
        if conversations.last?.content != message {
            chatMessages.append(ChatMessage(role: "user", content: message))
        }
        
        let chatRequest = ChatCompletionRequest(
            model: "claude-3-5-sonnet-20241022",
            messages: chatMessages,
            temperature: 0.7,
            maxTokens: 2000
        )
        
        request.httpBody = try JSONEncoder().encode(chatRequest)
        
        do {
            let (data, response) = try await performRequest(request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenClawError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                throw OpenClawError.apiError(httpResponse.statusCode)
            }
            
            let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            let responseText = chatResponse.choices.first?.message.content ?? "No response"
            
            let assistantMessage = ConversationMessage(content: responseText, isFromUser: false)
            await MainActor.run {
                conversations.append(assistantMessage)
            }
            
            return responseText
            
        } catch {
            await MainActor.run {
                let errorMessage = ConversationMessage(content: "Error: \(error.localizedDescription)", isFromUser: false)
                conversations.append(errorMessage)
            }
            throw error
        }
    }
    
    /// Send image with text prompt for vision analysis
    func sendImageMessage(imageBase64: String, prompt: String) async throws -> String {
        let userMessage = ConversationMessage(content: "\(prompt) [Image attached]", isFromUser: true)
        
        await MainActor.run {
            conversations.append(userMessage)
            isProcessing = true
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }
        
        let url = URL(string: "\(baseURL)\(chatCompletionsPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(to: &request)
        
        // Create vision request with proper OpenAI format
        let visionMessage = VisionChatMessage(
            role: "user",
            content: [
                MessageContent(type: "text", text: prompt),
                MessageContent(type: "image_url", imageUrl: ImageURL(url: "data:image/jpeg;base64,\(imageBase64)"))
            ]
        )
        
        let visionRequest = VisionChatCompletionRequest(
            model: "claude-3-5-sonnet-20241022", // Vision-capable model
            messages: [visionMessage],
            temperature: 0.7,
            maxTokens: 2000
        )
        
        request.httpBody = try JSONEncoder().encode(visionRequest)
        
        do {
            let (data, response) = try await performRequest(request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenClawError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                throw OpenClawError.apiError(httpResponse.statusCode)
            }
            
            let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            let responseText = chatResponse.choices.first?.message.content ?? "No response"
            
            let assistantMessage = ConversationMessage(content: responseText, isFromUser: false)
            await MainActor.run {
                conversations.append(assistantMessage)
            }
            
            return responseText
            
        } catch {
            await MainActor.run {
                let errorMessage = ConversationMessage(content: "Error: \(error.localizedDescription)", isFromUser: false)
                conversations.append(errorMessage)
            }
            throw error
        }
    }
    
    // MARK: - TTS Service
    func requestTTS(text: String) async throws -> Data {
        let url = URL(string: "\(baseURL)\(ttsPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(to: &request)
        
        let ttsRequest = TTSRequest(text: text, voice: "nova") // Default voice
        request.httpBody = try JSONEncoder().encode(ttsRequest)
        
        let (data, response) = try await performRequest(request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenClawError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        return data
    }
    
    // MARK: - Whisper Transcription
    func transcribeAudio(audioData: Data) async throws -> String {
        let url = URL(string: "\(baseURL)\(whisperPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeaders(to: &request)
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await performRequest(request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenClawError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return transcriptionResponse.text
    }
    
    // MARK: - Helper Methods
    private func addAuthHeaders(to request: inout URLRequest) {
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
    
    /// Execute a network request with retry logic
    private func performRequest(_ request: URLRequest, maxRetries: Int = 2) async throws -> (Data, URLResponse) {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                let result = try await urlSession.data(for: request)
                return result
            } catch {
                lastError = error
                
                // Don't retry on auth errors or client errors (4xx)
                if let urlError = error as? URLError,
                   urlError.code == .userAuthenticationRequired {
                    throw error
                }
                
                if let result = try? await urlSession.data(for: request),
                   let httpResponse = result.1 as? HTTPURLResponse,
                   httpResponse.statusCode >= 400 && httpResponse.statusCode < 500 {
                    throw error
                }
                
                // Wait before retry (exponential backoff)
                if attempt < maxRetries {
                    let delay = pow(2.0, Double(attempt)) * 0.5 // 0.5s, 1s, 2s
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? OpenClawError.apiError(0)
    }
    
    func updateBaseURL(_ url: String) {
        baseURL = url
        Task {
            await checkConnection()
        }
    }
    
    func clearConversation() {
        conversations.removeAll()
    }
}

// MARK: - API Models

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
    let imageData: String?
    
    init(role: String, content: String, imageData: String? = nil) {
        self.role = role
        self.content = content
        self.imageData = imageData
    }
}

struct ChatCompletionResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
        
        struct Message: Codable {
            let content: String
        }
    }
}

struct TTSRequest: Codable {
    let text: String
    let voice: String
}

struct TranscriptionResponse: Codable {
    let text: String
}

// MARK: - Vision API Models
struct VisionChatCompletionRequest: Codable {
    let model: String
    let messages: [VisionChatMessage]
    let temperature: Double
    let maxTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

struct VisionChatMessage: Codable {
    let role: String
    let content: [MessageContent]
}

struct MessageContent: Codable {
    let type: String
    let text: String?
    let imageUrl: ImageURL?
    
    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }
    
    init(type: String, text: String) {
        self.type = type
        self.text = text
        self.imageUrl = nil
    }
    
    init(type: String, imageUrl: ImageURL) {
        self.type = type
        self.text = nil
        self.imageUrl = imageUrl
    }
}

struct ImageURL: Codable {
    let url: String
}

// MARK: - Errors
enum OpenClawError: LocalizedError {
    case invalidResponse
    case apiError(Int)
    case noAuthToken
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let code):
            return "API error: \(code)"
        case .noAuthToken:
            return "No authentication token"
        }
    }
}