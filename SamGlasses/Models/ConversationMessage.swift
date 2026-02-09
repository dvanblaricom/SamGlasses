//
//  ConversationMessage.swift
//  SamGlasses
//
//  Simple message model for conversation history
//

import Foundation

/// Represents a message in the conversation between user and AI
struct ConversationMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let content: String
    let isFromUser: Bool
    let timestamp: Date
    let messageType: MessageType
    
    init(content: String, isFromUser: Bool, messageType: MessageType = .text) {
        self.id = UUID()
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = Date()
        self.messageType = messageType
    }
}

/// Types of messages that can be sent/received
enum MessageType: String, Codable, CaseIterable {
    case text = "text"
    case image = "image"
    case audio = "audio"
    case error = "error"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .audio:
            return "Audio"
        case .error:
            return "Error"
        case .system:
            return "System"
        }
    }
    
    var icon: String {
        switch self {
        case .text:
            return "text.bubble"
        case .image:
            return "photo"
        case .audio:
            return "waveform"
        case .error:
            return "exclamationmark.triangle"
        case .system:
            return "gear"
        }
    }
}

// MARK: - Extensions for UI
extension ConversationMessage {
    /// Formatted content for display (truncates very long messages)
    var displayContent: String {
        if content.count > 500 {
            return String(content.prefix(497)) + "..."
        }
        return content
    }
    
    /// Short preview of the message (for notifications or lists)
    var preview: String {
        let maxLength = 100
        let preview = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if preview.count > maxLength {
            return String(preview.prefix(maxLength - 3)) + "..."
        }
        return preview
    }
    
    /// Formatted timestamp for display
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        
        // If today, show time only
        if Calendar.current.isDateInToday(timestamp) {
            formatter.timeStyle = .short
            return formatter.string(from: timestamp)
        }
        
        // If within last week, show day and time
        if let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()),
           timestamp > weekAgo {
            formatter.setLocalizedDateFormatFromTemplate("EEE HH:mm")
            return formatter.string(from: timestamp)
        }
        
        // Otherwise show date and time
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Helper Functions
extension ConversationMessage {
    /// Create an error message
    static func error(_ message: String) -> ConversationMessage {
        ConversationMessage(
            content: message,
            isFromUser: false,
            messageType: .error
        )
    }
    
    /// Create a system message
    static func system(_ message: String) -> ConversationMessage {
        ConversationMessage(
            content: message,
            isFromUser: false,
            messageType: .system
        )
    }
    
    /// Create a user text message
    static func userText(_ message: String) -> ConversationMessage {
        ConversationMessage(
            content: message,
            isFromUser: true,
            messageType: .text
        )
    }
    
    /// Create an AI response message
    static func aiResponse(_ message: String) -> ConversationMessage {
        ConversationMessage(
            content: message,
            isFromUser: false,
            messageType: .text
        )
    }
    
    /// Create an image message (user captured image with optional description)
    static func imageMessage(_ description: String = "Image captured") -> ConversationMessage {
        ConversationMessage(
            content: description,
            isFromUser: true,
            messageType: .image
        )
    }
    
    /// Create an audio message (user recorded audio)
    static func audioMessage(_ description: String = "Audio recorded") -> ConversationMessage {
        ConversationMessage(
            content: description,
            isFromUser: true,
            messageType: .audio
        )
    }
}

// MARK: - Conversation History Management
extension Array where Element == ConversationMessage {
    /// Get messages from today only
    var todayMessages: [ConversationMessage] {
        filter { Calendar.current.isDateInToday($0.timestamp) }
    }
    
    /// Get the last N messages
    func last(_ count: Int) -> [ConversationMessage] {
        Array(suffix(count))
    }
    
    /// Get messages of a specific type
    func messages(ofType type: MessageType) -> [ConversationMessage] {
        filter { $0.messageType == type }
    }
    
    /// Get messages from a specific user (user or AI)
    func messages(fromUser: Bool) -> [ConversationMessage] {
        filter { $0.isFromUser == fromUser }
    }
    
    /// Calculate total conversation length in characters
    var totalCharacterCount: Int {
        reduce(0) { $0 + $1.content.count }
    }
}

// MARK: - Persistence Support
extension ConversationMessage {
    /// Convert to dictionary for saving to UserDefaults or other storage
    var dictionary: [String: Any] {
        [
            "id": id.uuidString,
            "content": content,
            "isFromUser": isFromUser,
            "timestamp": timestamp.timeIntervalSince1970,
            "messageType": messageType.rawValue
        ]
    }
    
    /// Create from dictionary (for loading from storage)
    init?(from dictionary: [String: Any]) {
        guard let idString = dictionary["id"] as? String,
              let id = UUID(uuidString: idString),
              let content = dictionary["content"] as? String,
              let isFromUser = dictionary["isFromUser"] as? Bool,
              let timestampInterval = dictionary["timestamp"] as? TimeInterval,
              let messageTypeString = dictionary["messageType"] as? String,
              let messageType = MessageType(rawValue: messageTypeString) else {
            return nil
        }
        
        self.id = id
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = Date(timeIntervalSince1970: timestampInterval)
        self.messageType = messageType
    }
}