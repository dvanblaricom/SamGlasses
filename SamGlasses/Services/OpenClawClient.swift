//
//  OpenClawClient.swift
//  SamGlasses
//
//  Gateway WebSocket client — connects to OpenClaw as a proper session
//  so Sam has full access to memory, tools, SOUL.md, and everything else.
//

import Foundation
import Combine
import CryptoKit

/// API client that connects to OpenClaw Gateway via WebSocket protocol
@MainActor
class OpenClawClient: ObservableObject {
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"
    @Published var conversations: [ConversationMessage] = []
    @Published var isProcessing = false
    
    // MARK: - Configuration
    @Published var baseURL = "wss://daves-mac-studio.taile75ef.ts.net"
    
    // Fallback HTTP base for TTS/Whisper (still needed until those go through WS)
    private var httpBaseURL: String {
        baseURL
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
    }
    
    private let ttsPath = "/tts"
    private let whisperPath = "/v1/audio/transcriptions"
    
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
    
    // MARK: - WebSocket State
    private var webSocket: URLSessionWebSocketTask?
    private var deviceId: String = ""
    private var deviceToken: String? {
        get { KeychainHelper.shared.getDeviceToken() }
        set {
            if let token = newValue {
                KeychainHelper.shared.storeDeviceToken(token)
            } else {
                KeychainHelper.shared.deleteDeviceToken()
            }
        }
    }
    private var requestId = 0
    private var pendingRequests: [String: CheckedContinuation<GatewayResponse, Error>] = [:]
    private var currentRunId: String?
    private var streamingBuffer = ""
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var isIntentionalDisconnect = false
    private var challengeNonce: String?
    
    // MARK: - URLSession
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()
    
    // MARK: - Initialization
    init() {
        deviceId = getOrCreateDeviceId()
    }
    
    // MARK: - Device Identity
    private func getOrCreateDeviceId() -> String {
        let key = "com.samglasses.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = "samglasses_\(UUID().uuidString.prefix(8).lowercased())"
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
    
    // MARK: - Connection Management
    func connect() {
        guard webSocket == nil else { return }
        isIntentionalDisconnect = false
        
        guard let url = URL(string: baseURL) else {
            connectionStatus = "Invalid URL"
            return
        }
        
        connectionStatus = "Connecting..."
        
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        
        // Start listening for messages (including challenge)
        listenForMessages()
    }
    
    func disconnect() {
        isIntentionalDisconnect = true
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isConnected = false
        connectionStatus = "Disconnected"
        
        // Fail all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: OpenClawError.disconnected)
        }
        pendingRequests.removeAll()
    }
    
    func loadSettings() {
        connect()
    }
    
    func checkConnection() async {
        if !isConnected {
            connect()
        }
    }
    
    // MARK: - WebSocket Handshake
    
    private func sendHandshake() {
        let id = nextRequestId()
        
        // Build auth — prefer device token, fall back to gateway token
        var auth: [String: Any] = [:]
        if let dt = deviceToken {
            auth["deviceToken"] = dt
        } else if let token = authToken {
            auth["token"] = token
        }
        
        // Build device identity
        var device: [String: Any] = ["id": deviceId]
        
        // If we have a challenge nonce, sign it
        if let nonce = challengeNonce {
            device["nonce"] = nonce
            // For simplicity, we send the nonce back; full crypto signing
            // would use a keypair. The gateway auto-approves local + tailscale.
        }
        
        let connectParams: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id": "sam-glasses",
                "version": "1.0.0",
                "platform": "ios",
                "mode": "operator"
            ],
            "role": "operator",
            "scopes": ["operator.read", "operator.write"],
            "caps": [],
            "commands": [],
            "permissions": [:] as [String: Any],
            "auth": auth,
            "locale": Locale.current.identifier,
            "userAgent": "SamGlasses/1.0.0 iOS",
            "device": device
        ]
        
        let frame: [String: Any] = [
            "type": "req",
            "id": id,
            "method": "connect",
            "params": connectParams
        ]
        
        sendJSON(frame)
    }
    
    // MARK: - Chat Methods
    
    /// Send a text message through the Gateway session (the real Sam)
    func sendMessage(_ message: String) async throws -> String {
        let userMessage = ConversationMessage(content: message, isFromUser: true)
        conversations.append(userMessage)
        isProcessing = true
        streamingBuffer = ""
        
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }
        
        guard isConnected else {
            throw OpenClawError.disconnected
        }
        
        let id = nextRequestId()
        let idempotencyKey = UUID().uuidString
        
        let params: [String: Any] = [
            "message": message,
            "idempotencyKey": idempotencyKey
        ]
        
        let frame: [String: Any] = [
            "type": "req",
            "id": id,
            "method": "chat.send",
            "params": params
        ]
        
        // Send the request — chat.send acks immediately, response streams via events
        let ack = try await sendRequest(id: id, frame: frame)
        
        if let runId = ack.payload?["runId"] as? String {
            currentRunId = runId
        }
        
        // Wait for the full response via chat events
        let response = try await waitForChatResponse()
        
        let assistantMessage = ConversationMessage(content: response, isFromUser: false)
        conversations.append(assistantMessage)
        
        return response
    }
    
    /// Send image with text prompt through the Gateway session
    func sendImageMessage(imageBase64: String, prompt: String) async throws -> String {
        let userMessage = ConversationMessage(content: "\(prompt) [Image attached]", isFromUser: true)
        conversations.append(userMessage)
        isProcessing = true
        streamingBuffer = ""
        
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }
        
        guard isConnected else {
            throw OpenClawError.disconnected
        }
        
        let id = nextRequestId()
        let idempotencyKey = UUID().uuidString
        
        // Send as a message with image attachment
        // The gateway handles vision model routing
        let params: [String: Any] = [
            "message": prompt,
            "attachments": [
                [
                    "type": "image",
                    "data": "data:image/jpeg;base64,\(imageBase64)"
                ]
            ],
            "idempotencyKey": idempotencyKey
        ]
        
        let frame: [String: Any] = [
            "type": "req",
            "id": id,
            "method": "chat.send",
            "params": params
        ]
        
        let ack = try await sendRequest(id: id, frame: frame)
        
        if let runId = ack.payload?["runId"] as? String {
            currentRunId = runId
        }
        
        let response = try await waitForChatResponse()
        
        let assistantMessage = ConversationMessage(content: response, isFromUser: false)
        conversations.append(assistantMessage)
        
        return response
    }
    
    /// Load chat history from the Gateway session
    func loadHistory() async {
        guard isConnected else { return }
        
        let id = nextRequestId()
        let frame: [String: Any] = [
            "type": "req",
            "id": id,
            "method": "chat.history",
            "params": ["limit": 20]
        ]
        
        do {
            let response = try await sendRequest(id: id, frame: frame)
            if let messages = response.payload?["messages"] as? [[String: Any]] {
                var loaded: [ConversationMessage] = []
                for msg in messages {
                    let role = msg["role"] as? String ?? ""
                    let content = msg["content"] as? String ?? ""
                    if !content.isEmpty && (role == "user" || role == "assistant") {
                        loaded.append(ConversationMessage(
                            content: content,
                            isFromUser: role == "user"
                        ))
                    }
                }
                conversations = loaded
            }
        } catch {
            print("Failed to load history: \(error)")
        }
    }
    
    // MARK: - TTS Service (still HTTP for now)
    func requestTTS(text: String) async throws -> Data {
        let url = URL(string: "\(httpBaseURL)\(ttsPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(to: &request)
        
        let ttsRequest = TTSRequest(text: text, voice: "nova")
        request.httpBody = try JSONEncoder().encode(ttsRequest)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenClawError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        return data
    }
    
    // MARK: - Whisper Transcription (still HTTP for now)
    func transcribeAudio(audioData: Data) async throws -> String {
        let url = URL(string: "\(httpBaseURL)\(whisperPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeaders(to: &request)
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenClawError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return transcriptionResponse.text
    }
    
    // MARK: - WebSocket Message Handling
    
    private func listenForMessages() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    // Keep listening
                    self.listenForMessages()
                    
                case .failure(let error):
                    print("WebSocket receive error: \(error)")
                    self.handleDisconnect()
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        let type = json["type"] as? String ?? ""
        
        switch type {
        case "event":
            handleEvent(json)
        case "res":
            handleResponse(json)
        default:
            break
        }
    }
    
    private func handleEvent(_ json: [String: Any]) {
        let event = json["event"] as? String ?? ""
        let payload = json["payload"] as? [String: Any] ?? [:]
        
        switch event {
        case "connect.challenge":
            // Store nonce and send handshake
            challengeNonce = payload["nonce"] as? String
            sendHandshake()
            
        case "chat":
            // Streaming chat response
            handleChatEvent(payload)
            
        case "chat.done":
            // Response complete
            chatResponseContinuation?.resume(returning: streamingBuffer)
            chatResponseContinuation = nil
            
        default:
            break
        }
    }
    
    private func handleResponse(_ json: [String: Any]) {
        guard let id = json["id"] as? String else { return }
        
        let ok = json["ok"] as? Bool ?? false
        let payload = json["payload"] as? [String: Any]
        let error = json["error"] as? [String: Any]
        
        // Check if this is the connect response
        if let payloadType = payload?["type"] as? String, payloadType == "hello-ok" {
            handleConnectSuccess(payload!)
            // Still resolve the pending request
        }
        
        if let continuation = pendingRequests.removeValue(forKey: id) {
            if ok {
                continuation.resume(returning: GatewayResponse(ok: true, payload: payload))
            } else {
                let msg = error?["message"] as? String ?? "Unknown error"
                continuation.resume(throwing: OpenClawError.gatewayError(msg))
            }
        }
    }
    
    private func handleConnectSuccess(_ payload: [String: Any]) {
        isConnected = true
        connectionStatus = "Connected"
        reconnectAttempts = 0
        
        // Store device token if issued
        if let auth = payload["auth"] as? [String: Any],
           let dt = auth["deviceToken"] as? String {
            deviceToken = dt
        }
        
        // Load history on connect
        Task {
            await loadHistory()
        }
    }
    
    // MARK: - Chat Event Streaming
    
    private var chatResponseContinuation: CheckedContinuation<String, Error>?
    
    private func handleChatEvent(_ payload: [String: Any]) {
        // Handle different chat event subtypes
        if let delta = payload["delta"] as? String {
            streamingBuffer += delta
        } else if let content = payload["content"] as? String {
            streamingBuffer = content
        } else if let message = payload["message"] as? [String: Any],
                  let content = message["content"] as? String {
            streamingBuffer = content
        }
        
        // Check if this is a final/done event
        let status = payload["status"] as? String
        if status == "done" || status == "complete" || status == "finished" {
            chatResponseContinuation?.resume(returning: streamingBuffer)
            chatResponseContinuation = nil
        }
    }
    
    private func waitForChatResponse() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            chatResponseContinuation = continuation
            
            // Timeout after 90 seconds
            Task {
                try await Task.sleep(nanoseconds: 90_000_000_000)
                if let cont = chatResponseContinuation {
                    chatResponseContinuation = nil
                    if !streamingBuffer.isEmpty {
                        cont.resume(returning: streamingBuffer)
                    } else {
                        cont.resume(throwing: OpenClawError.timeout)
                    }
                }
            }
        }
    }
    
    // MARK: - Reconnection
    
    private func handleDisconnect() {
        webSocket = nil
        isConnected = false
        
        guard !isIntentionalDisconnect else {
            connectionStatus = "Disconnected"
            return
        }
        
        connectionStatus = "Reconnecting..."
        
        guard reconnectAttempts < maxReconnectAttempts else {
            connectionStatus = "Connection Failed"
            return
        }
        
        reconnectAttempts += 1
        let delay = pow(2.0, Double(reconnectAttempts)) * 0.5
        
        Task {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            connect()
        }
    }
    
    // MARK: - Helper Methods
    
    private func nextRequestId() -> String {
        requestId += 1
        return "sg_\(requestId)"
    }
    
    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        webSocket?.send(.string(text)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }
    
    private func sendRequest(id: String, frame: [String: Any]) async throws -> GatewayResponse {
        try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            sendJSON(frame)
            
            // Timeout after 30 seconds for ack
            Task {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                if let cont = pendingRequests.removeValue(forKey: id) {
                    cont.resume(throwing: OpenClawError.timeout)
                }
            }
        }
    }
    
    private func addAuthHeaders(to request: inout URLRequest) {
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
    
    func updateAuthToken(_ token: String) {
        authToken = token
        // Reconnect with new token
        disconnect()
        connect()
    }
    
    func updateBaseURL(_ url: String) {
        // Accept both http/https and ws/wss formats
        if url.hasPrefix("http://") {
            baseURL = url.replacingOccurrences(of: "http://", with: "ws://")
        } else if url.hasPrefix("https://") {
            baseURL = url.replacingOccurrences(of: "https://", with: "wss://")
        } else if url.hasPrefix("ws://") || url.hasPrefix("wss://") {
            baseURL = url
        } else {
            baseURL = "wss://\(url)"
        }
        disconnect()
        connect()
    }
    
    func clearConversation() {
        conversations.removeAll()
    }
    
    /// Abort the current chat run
    func abortChat() {
        guard isConnected else { return }
        let id = nextRequestId()
        let frame: [String: Any] = [
            "type": "req",
            "id": id,
            "method": "chat.abort",
            "params": [:] as [String: Any]
        ]
        sendJSON(frame)
        isProcessing = false
        
        // Resolve any waiting continuation
        chatResponseContinuation?.resume(returning: streamingBuffer)
        chatResponseContinuation = nil
    }
}

// MARK: - Gateway Response Model

struct GatewayResponse {
    let ok: Bool
    let payload: [String: Any]?
}

// MARK: - API Models (kept for TTS/Whisper HTTP endpoints)

struct TTSRequest: Codable {
    let text: String
    let voice: String
}

struct TranscriptionResponse: Codable {
    let text: String
}

// MARK: - Errors
enum OpenClawError: LocalizedError {
    case invalidResponse
    case apiError(Int)
    case noAuthToken
    case disconnected
    case timeout
    case gatewayError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let code):
            return "API error: \(code)"
        case .noAuthToken:
            return "No authentication token"
        case .disconnected:
            return "Not connected to OpenClaw"
        case .timeout:
            return "Request timed out"
        case .gatewayError(let msg):
            return "Gateway error: \(msg)"
        }
    }
}

// MARK: - KeychainHelper Extensions

extension KeychainHelper {
    func getDeviceToken() -> String? {
        getString(forKey: "com.samglasses.deviceToken")
    }
    
    func storeDeviceToken(_ token: String) {
        storeString(token, forKey: "com.samglasses.deviceToken")
    }
    
    func deleteDeviceToken() {
        deleteItem(forKey: "com.samglasses.deviceToken")
    }
}
