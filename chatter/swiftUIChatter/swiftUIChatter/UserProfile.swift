//
//  UserProfile.swift
//  swiftUIChatter
//
//  Created by AI Assistant on 3/5/25.
//

import Foundation
import SwiftUI
import GoogleSignIn

@Observable
final class UserProfile {
    static let shared = UserProfile() // Singleton instance
    private init() {
        loadFromUserDefaults()
        checkAndUpdateStreak()
    }
    
    // User profile data
    private(set) var displayName: String = "Anonymous User"
    private(set) var email: String?
    private(set) var profilePictureURL: URL?
    private(set) var isLoggedIn: Bool = false
    private(set) var userId: String?
    private(set) var givenName: String?
    private(set) var familyName: String?
    
    // ChatterID integration
    var chatterId: String? {
        ChatterID.shared.id
    }
    
    var chatterIdExpiration: Date {
        ChatterID.shared.expiration
    }
    
    // Google Auth Token (For backend authentication)
    private(set) var idToken: String?
    
    // Additional stats
    private(set) var eloRating: Int = 100
    private(set) var completedModules: Int = 0
    private(set) var totalModules: Int = 5
    
    // Streak tracking
    private(set) var currentStreak: Int = 0
    private(set) var longestStreak: Int = 0
    private(set) var lastActivityDate: Date?
    private(set) var streakFreeze: Int = 0 // Number of streak freezes available
    
    // Add dictionary to store exercise scores
    internal var userExerciseScores: [String: Int] = [:]
    
    // Add structure to store exercise averages and related metrics
    internal struct ExerciseMetrics {
        var difficulty: Double
        var totalSubmissions: Int
        var averageScorePercentage: Double
        var averageScore: Double
        var latestScore: Double
        var latestScorePercentage: Double
    }
    
    // Dictionary to store exercise metrics
    internal var exerciseMetrics: [String: ExerciseMetrics] = [:]
    
    // Update user profile with Google sign-in data
    func updateProfile(name: String?, email: String?, profilePictureURL: URL?, userId: String?, givenName: String? = nil, familyName: String? = nil, idToken: String? = nil) {
        self.displayName = name ?? "Anonymous User"
        self.email = email
        self.profilePictureURL = profilePictureURL
        self.userId = userId
        self.givenName = givenName
        self.familyName = familyName
        self.idToken = idToken
        self.isLoggedIn = true
        
        // Record activity for streak
        recordActivity()
        
        saveToUserDefaults()
    }
    
    // Update from Google Sign-In
    func updateFromGoogleUser(_ googleUser: GIDGoogleUser) {
        // Reset all profile data to defaults before updating
        resetProfileData()
        
        let email = googleUser.profile?.email
        let fullName = googleUser.profile?.name
        let givenName = googleUser.profile?.givenName
        let familyName = googleUser.profile?.familyName
        let profilePicURL = googleUser.profile?.imageURL(withDimension: 320)
        let userId = googleUser.userID
        
        // Get ID token for secure backend communication
        let idToken = googleUser.idToken?.tokenString
        
        // Update UserID in ChatterID if needed
        if let userId = userId {
            ChatterID.shared.id = userId
            // Set expiration to 30 days from now
            ChatterID.shared.expiration = Date().addingTimeInterval(30 * 24 * 60 * 60)
            
            // Save to keychain
            Task {
                await ChatterID.shared.save()
            }
        }
        
        // Update profile
        updateProfile(
            name: fullName,
            email: email,
            profilePictureURL: profilePicURL,
            userId: userId,
            givenName: givenName,
            familyName: familyName,
            idToken: idToken
        )
        
        // Call upsertUser to save user data to Supabase
        Task {
            await upsertUser(
                userId: userId ?? "",
                displayName: fullName ?? "Anonymous User",
                email: email ?? "",
                profilePicture: profilePicURL?.absoluteString
            )
        }
    }
    
    // Reset all profile data to default values
    private func resetProfileData() {
        // Reset basic profile info
        displayName = "Anonymous User"
        email = nil
        profilePictureURL = nil
        isLoggedIn = false
        userId = nil
        givenName = nil
        familyName = nil
        idToken = nil
        
        // Reset stats to default values
        eloRating = 100  // Reset to initial default
        completedModules = 0
        totalModules = 5
        
        // Reset streak data
        currentStreak = 0
        longestStreak = 0
        lastActivityDate = nil
        streakFreeze = 0
        
        // Reset exercise scores
        userExerciseScores = [:]
        
        // Clear UserDefaults for all profile keys
        let userDefaults = UserDefaults.standard
        let keysToRemove = [
            "userProfile_displayName",
            "userProfile_email",
            "userProfile_profilePictureURL",
            "userProfile_isLoggedIn",
            "userProfile_userId",
            "userProfile_givenName",
            "userProfile_familyName",
            "userProfile_idToken",
            "userProfile_eloRating",
            "userProfile_completedModules",
            "userProfile_totalModules",
            "userProfile_currentStreak",
            "userProfile_longestStreak",
            "userProfile_lastActivityDate",
            "userProfile_streakFreeze",
            "userProfile_exerciseScores",
            "userProfile_exerciseMetrics"
        ]
        
        for key in keysToRemove {
            userDefaults.removeObject(forKey: key)
        }
    }
    
    // Update user stats
    func updateStats(eloRating: Int? = nil, completedModules: Int? = nil, totalModules: Int? = nil) {
        if let eloRating = eloRating {
            self.eloRating = eloRating
        }
        
        if let completedModules = completedModules {
            self.completedModules = completedModules
        }
        
        if let totalModules = totalModules {
            self.totalModules = totalModules
        }
        
        // Record activity for streak
        recordActivity()
        
        saveToUserDefaults()
    }
    
    // Clear profile data on logout
    func clearProfile() {
        displayName = "Anonymous User"
        email = nil
        profilePictureURL = nil
        isLoggedIn = false
        userId = nil
        givenName = nil
        familyName = nil
        idToken = nil
        resetProfileData()

        
        // Clear ChatterID
        Task {
            ChatterID.shared.id = nil
            ChatterID.shared.expiration = Date(timeIntervalSince1970: 0.0)
            await ChatterID.shared.delete()
        }
        
        // Save changes to UserDefaults
        saveToUserDefaults()
    }
    
    // Streak management
    
    // Record user activity and update streak
    func recordActivity() {
        let today = Calendar.current.startOfDay(for: Date())
        
        // If this is the first activity, initialize
        if lastActivityDate == nil {
            lastActivityDate = today
            currentStreak = 1
            longestStreak = max(longestStreak, currentStreak)
            saveToUserDefaults()
            return
        }
        
        guard let lastActivity = lastActivityDate else { return }
        let lastActivityDay = Calendar.current.startOfDay(for: lastActivity)
        
        // If already recorded activity today, just return
        if lastActivityDay == today {
            return
        }
        
        // Calculate days between last activity and today
        if let daysBetween = Calendar.current.dateComponents([.day], from: lastActivityDay, to: today).day {
            if daysBetween == 1 {
                // Next consecutive day, increment streak
                currentStreak += 1
                longestStreak = max(longestStreak, currentStreak)
            } else if daysBetween == 2 && streakFreeze > 0 {
                // Missed one day but have streak freeze
                streakFreeze -= 1
                currentStreak += 1
                longestStreak = max(longestStreak, currentStreak)
            } else {
                // Streak broken
                currentStreak = 1
            }
        }
        
        lastActivityDate = today
        saveToUserDefaults()
    }
    
    // Check and update streak on app launch
    private func checkAndUpdateStreak() {
        guard let lastActivity = lastActivityDate else { return }
        
        let today = Calendar.current.startOfDay(for: Date())
        let lastActivityDay = Calendar.current.startOfDay(for: lastActivity)
        
        // If more than 1 day (or 2 with freeze) has passed without activity, reset streak
        if let daysSinceLastActivity = Calendar.current.dateComponents([.day], from: lastActivityDay, to: today).day,
           daysSinceLastActivity > 1 {
            if daysSinceLastActivity == 2 && streakFreeze > 0 {
                // Use streak freeze if available
                streakFreeze -= 1
            } else {
                // Reset streak
                currentStreak = 0
                saveToUserDefaults()
            }
        }
    }
    
    // Add streak freeze (could be earned or purchased)
    func addStreakFreeze(count: Int = 1) {
        streakFreeze += count
        saveToUserDefaults()
    }
    
    // Save profile to UserDefaults
    private func saveToUserDefaults() {
        let userDefaults = UserDefaults.standard
        
        userDefaults.set(displayName, forKey: "userProfile_displayName")
        userDefaults.set(email, forKey: "userProfile_email")
        userDefaults.set(profilePictureURL?.absoluteString, forKey: "userProfile_profilePictureURL")
        userDefaults.set(isLoggedIn, forKey: "userProfile_isLoggedIn")
        userDefaults.set(userId, forKey: "userProfile_userId")
        userDefaults.set(givenName, forKey: "userProfile_givenName")
        userDefaults.set(familyName, forKey: "userProfile_familyName")
        userDefaults.set(idToken, forKey: "userProfile_idToken")
        userDefaults.set(eloRating, forKey: "userProfile_eloRating")
        userDefaults.set(completedModules, forKey: "userProfile_completedModules")
        userDefaults.set(totalModules, forKey: "userProfile_totalModules")
        
        // Save streak data
        userDefaults.set(currentStreak, forKey: "userProfile_currentStreak")
        userDefaults.set(longestStreak, forKey: "userProfile_longestStreak")
        userDefaults.set(lastActivityDate, forKey: "userProfile_lastActivityDate")
        userDefaults.set(streakFreeze, forKey: "userProfile_streakFreeze")
        
        // Save exercise scores and metrics
        saveExerciseScoresToUserDefaults()
        saveExerciseMetricsToUserDefaults()
    }
    
    // Load profile from UserDefaults
    private func loadFromUserDefaults() {
        let userDefaults = UserDefaults.standard
        
        displayName = userDefaults.string(forKey: "userProfile_displayName") ?? "Anonymous User"
        email = userDefaults.string(forKey: "userProfile_email")
        
        if let urlString = userDefaults.string(forKey: "userProfile_profilePictureURL") {
            profilePictureURL = URL(string: urlString)
        }
        
        isLoggedIn = userDefaults.bool(forKey: "userProfile_isLoggedIn")
        userId = userDefaults.string(forKey: "userProfile_userId")
        givenName = userDefaults.string(forKey: "userProfile_givenName")
        familyName = userDefaults.string(forKey: "userProfile_familyName")
        idToken = userDefaults.string(forKey: "userProfile_idToken")
        
        eloRating = userDefaults.integer(forKey: "userProfile_eloRating")
        if eloRating == 0 { eloRating = 101 } // Default value if not set
        
        completedModules = userDefaults.integer(forKey: "userProfile_completedModules")
        totalModules = userDefaults.integer(forKey: "userProfile_totalModules")
        if totalModules == 0 { totalModules = 5 } // Default value if not set
        
        // Load streak data
        currentStreak = userDefaults.integer(forKey: "userProfile_currentStreak")
        longestStreak = userDefaults.integer(forKey: "userProfile_longestStreak")
        lastActivityDate = userDefaults.object(forKey: "userProfile_lastActivityDate") as? Date
        streakFreeze = userDefaults.integer(forKey: "userProfile_streakFreeze")
        
        // Load exercise scores
        loadExerciseScoresFromUserDefaults()
        
        // Load exercise metrics
        loadExerciseMetricsFromUserDefaults()
    }
    
    // Add method to update exercise scores and recalculate ELO rating
    func updateExerciseScore(exerciseId: String, score: Int) {
        // Update the score for this exercise
        userExerciseScores[exerciseId] = score
        
        // Calculate total ELO score (minimum at 100)
        let totalScore = userExerciseScores.values.reduce(0, +) + 100
        let newEloRating = max(totalScore, 100)
        
        // Update ELO rating
        updateStats(eloRating: newEloRating)
        
        print("DEBUG: Updated ELO score to \(newEloRating) after exercise \(exerciseId) with score \(score)")
        print("DEBUG: Current exercise scores: \(userExerciseScores)")
        
        // Save exercise scores to UserDefaults
        saveExerciseScoresToUserDefaults()
    }
    
    // Add methods to save and load exercise scores
    private func saveExerciseScoresToUserDefaults() {
        if let data = try? JSONEncoder().encode(userExerciseScores) {
            UserDefaults.standard.set(data, forKey: "userProfile_exerciseScores")
        }
    }
    
    private func loadExerciseScoresFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: "userProfile_exerciseScores"),
           let scores = try? JSONDecoder().decode([String: Int].self, from: data) {
            userExerciseScores = scores
        }
    }
    
    // Computed property to get the count of completed exercises
    var completedExercisesCount: Int {
        return userExerciseScores.count
    }
    
    // Update exercise metrics and save to UserDefaults
    func updateExerciseScoresAverages(
        moduleId: String,
        difficulty: Double,
        totalSubmissions: Int,
        averageScorePercentage: Double,
        averageScore: Double,
        latestScore: Double,
        latestScorePercentage: Double
    ) {
        // Store the metrics for this exercise
        exerciseMetrics[moduleId] = ExerciseMetrics(
            difficulty: difficulty,
            totalSubmissions: totalSubmissions,
            averageScorePercentage: averageScorePercentage,
            averageScore: averageScore,
            latestScore: latestScore,
            latestScorePercentage: latestScorePercentage
        )
        
        // Save to UserDefaults
        saveExerciseMetricsToUserDefaults()
        
        // Optionally update ELO rating based on latest score
        updateExerciseScore(exerciseId: moduleId, score: Int(latestScore))
        
        print("DEBUG: Updated metrics for exercise \(moduleId): difficulty=\(difficulty), submissions=\(totalSubmissions), avgScore=\(averageScore)")
    }
    
    // Add methods to save and load exercise metrics
    private func saveExerciseMetricsToUserDefaults() {
        if let data = try? JSONEncoder().encode(exerciseMetrics) {
            UserDefaults.standard.set(data, forKey: "userProfile_exerciseMetrics")
        }
    }
    
    private func loadExerciseMetricsFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: "userProfile_exerciseMetrics"),
           let metrics = try? JSONDecoder().decode([String: ExerciseMetrics].self, from: data) {
            exerciseMetrics = metrics
        }
    }
}

func upsertUser(userId: String, displayName: String, email: String, profilePicture: String?) async {
    let url = URL(string: "https://oozwwgcihpunaaatfjwn.supabase.co/rest/v1/users")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9vend3Z2NpaHB1bmFhYXRmanduIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc0MjE3NjE5MiwiZXhwIjoyMDU3NzUyMTkyfQ.KjcU_btA7LBYLgxGA_5iRGNzmBcR2Dx4eYkw3wp-nfc", forHTTPHeaderField: "apikey")
    request.setValue("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9vend3Z2NpaHB1bmFhYXRmanduIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc0MjE3NjE5MiwiZXhwIjoyMDU3NzUyMTkyfQ.KjcU_btA7LBYLgxGA_5iRGNzmBcR2Dx4eYkw3wp-nfc", forHTTPHeaderField: "authorization")
    request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

    let user: [String: Any] = [
        "user_id": userId,
        "display_name": displayName,
        "email": email,
        "profile_picture": profilePicture ?? ""
    ]

    request.httpBody = try? JSONSerialization.data(withJSONObject: user)

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            print("User upserted successfully")
        } else {
            print("Failed to upsert user")
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
} 