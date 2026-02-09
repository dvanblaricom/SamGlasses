//
//  KeychainHelper.swift
//  SamGlasses
//
//  Secure storage for sensitive data like auth tokens
//

import Foundation
import Security

/// Helper class for securely storing and retrieving data from the iOS Keychain
class KeychainHelper {
    static let shared = KeychainHelper()
    
    private let service = "com.samglasses.app"
    
    private init() {}
    
    // MARK: - Auth Token Management
    
    /// Store OpenClaw auth token securely in Keychain
    func storeAuthToken(_ token: String) {
        storeString(token, forKey: "openClaw_auth_token")
    }
    
    /// Retrieve OpenClaw auth token from Keychain
    func getAuthToken() -> String? {
        getString(forKey: "openClaw_auth_token")
    }
    
    /// Delete auth token from Keychain
    func deleteAuthToken() {
        deleteItem(forKey: "openClaw_auth_token")
    }
    
    // MARK: - Generic Keychain Operations
    
    /// Store a string value in the Keychain
    @discardableResult
    func storeString(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return storeData(data, forKey: key)
    }
    
    /// Retrieve a string value from the Keychain
    func getString(forKey key: String) -> String? {
        guard let data = getData(forKey: key),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    /// Store data in the Keychain
    @discardableResult
    func storeData(_ data: Data, forKey key: String) -> Bool {
        // First, delete any existing item
        deleteItem(forKey: key)
        
        // Create query for new item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        return status == errSecSuccess
    }
    
    /// Retrieve data from the Keychain
    func getData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else { return nil }
        
        return result as? Data
    }
    
    /// Delete an item from the Keychain
    @discardableResult
    func deleteItem(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Update an existing item in the Keychain
    @discardableResult
    func updateString(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return updateData(data, forKey: key)
    }
    
    /// Update an existing item in the Keychain
    @discardableResult
    func updateData(_ data: Data, forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        return status == errSecSuccess
    }
    
    // MARK: - Keychain Management
    
    /// Check if a key exists in the Keychain
    func itemExists(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnAttributes as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Clear all items for this app from the Keychain
    @discardableResult
    func clearAllItems() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// List all keys for this service (useful for debugging)
    func getAllKeys() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        
        return items.compactMap { item in
            item[kSecAttrAccount as String] as? String
        }
    }
}

// MARK: - Error Handling
extension KeychainHelper {
    /// Get human-readable description of Keychain error
    func errorDescription(for status: OSStatus) -> String {
        switch status {
        case errSecSuccess:
            return "Success"
        case errSecItemNotFound:
            return "Item not found"
        case errSecDuplicateItem:
            return "Duplicate item"
        case errSecAuthFailed:
            return "Authentication failed"
        case errSecUnimplemented:
            return "Unimplemented function"
        case errSecParam:
            return "Invalid parameter"
        case errSecAllocate:
            return "Memory allocation error"
        case errSecNotAvailable:
            return "Service not available"
        case errSecBadReq:
            return "Bad request"
        case errSecInternalComponent:
            return "Internal component error"
        case errSecInteractionNotAllowed:
            return "Interaction not allowed"
        case errSecDecode:
            return "Decode error"
        default:
            return "Unknown error (\(status))"
        }
    }
}

// MARK: - Keychain Keys (for organization)
extension KeychainHelper {
    /// Predefined keys for common items
    enum Keys {
        static let authToken = "openClaw_auth_token"
        static let userPreferences = "user_preferences"
        static let deviceId = "device_id"
        static let encryptionKey = "encryption_key"
    }
}