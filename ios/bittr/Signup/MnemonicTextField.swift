//
//  MnemonicTextField.swift
//  bittr
//
//  Created by Test Suite
//

import UIKit

class MnemonicTextField: UITextField {
    
    private var suggestionLabel: UILabel?
    private var suggestionTimer: Timer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTextField()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextField()
    }
    
    private func setupTextField() {
        // Disable iOS autocorrection and spell checking
        self.autocorrectionType = .no
        self.spellCheckingType = .no
        self.autocapitalizationType = .none
        self.smartQuotesType = .no
        self.smartDashesType = .no
        self.smartInsertDeleteType = .no
        
        // Add suggestion label
        suggestionLabel = UILabel()
        suggestionLabel?.textColor = UIColor.systemGray3
        suggestionLabel?.font = self.font
        suggestionLabel?.isUserInteractionEnabled = false
        suggestionLabel?.backgroundColor = UIColor.clear
        
        addSubview(suggestionLabel!)
        suggestionLabel?.translatesAutoresizingMaskIntoConstraints = false
        
        // Position the suggestion label to overlay the text field
        NSLayoutConstraint.activate([
            suggestionLabel!.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            suggestionLabel!.centerYAnchor.constraint(equalTo: centerYAnchor),
            suggestionLabel!.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: 0)
        ])
        
        // Add target for text changes
        addTarget(self, action: #selector(textDidChange), for: .editingChanged)
    }
    
    @objc private func textDidChange() {
        guard let text = self.text, !text.isEmpty else {
            hideSuggestion()
            return
        }
        
        // Cancel previous timer
        suggestionTimer?.invalidate()
        
        // Start new timer for debouncing - reduced delay for more responsive suggestions
        suggestionTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
            self.updateSuggestion()
        }
    }
    
    private func updateSuggestion() {
        guard let text = self.text, !text.isEmpty else {
            hideSuggestion()
            return
        }
        
        // Don't show suggestions for very short inputs (less than 2 characters)
        if text.count < 2 {
            hideSuggestion()
            return
        }
        
        // Check if the current text is already a complete word
        let isCompleteWord = MnemonicWordListEN.contains { word in
            word.lowercased() == text.lowercased()
        }
        
        if isCompleteWord {
            // Don't show suggestions for complete words
            hideSuggestion()
            return
        }
        
        // Find matching word - start suggesting from first character
        let matchingWord = MnemonicWordListEN.first { word in
            word.lowercased().hasPrefix(text.lowercased()) && word.lowercased() != text.lowercased()
        }
        
        if let suggestion = matchingWord {
            showSuggestion(suggestion)
        } else {
            hideSuggestion()
        }
    }
    
    private func showSuggestion(_ suggestion: String) {
        guard let text = self.text, !text.isEmpty else { return }
        
        // Calculate the position where the suggestion should start
        let textAttributes = [NSAttributedString.Key.font: self.font ?? UIFont.systemFont(ofSize: 16)]
        let textSize = (text as NSString).size(withAttributes: textAttributes)
        
        // Show the suggestion with the remaining part
        let remainingPart = String(suggestion.dropFirst(text.count))
        suggestionLabel?.text = remainingPart
        suggestionLabel?.isHidden = false
        
        // Update the leading constraint to position after the current text
        suggestionLabel?.removeFromSuperview()
        addSubview(suggestionLabel!)
        suggestionLabel?.translatesAutoresizingMaskIntoConstraints = false
        
        // Calculate proper positioning based on text field insets
        let leftInset: CGFloat = 8
        let rightInset: CGFloat = 8
        let textWidth = textSize.width + leftInset
        
        NSLayoutConstraint.activate([
            suggestionLabel!.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textWidth),
            suggestionLabel!.centerYAnchor.constraint(equalTo: centerYAnchor),
            suggestionLabel!.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -rightInset)
        ])
        
        // Animate in
        UIView.animate(withDuration: 0.15) {
            self.suggestionLabel?.alpha = 0.6
        }
    }
    
    private func hideSuggestion() {
        UIView.animate(withDuration: 0.2) {
            self.suggestionLabel?.alpha = 0
        } completion: { _ in
            self.suggestionLabel?.isHidden = true
        }
    }
    
    @objc private func acceptSuggestion() {
        guard let suggestion = suggestionLabel?.text, let currentText = self.text else { return }
        
        // Complete the word
        self.text = currentText + suggestion
        hideSuggestion()
        
        // Notify delegate
        sendActions(for: .editingChanged)
    }
    
    // Method to accept suggestion when return is pressed
    func acceptSuggestionOnReturn() -> Bool {
        guard let suggestion = suggestionLabel?.text, !suggestion.isEmpty else {
            return false
        }
        
        // Check if the current text is already a complete word
        if let currentText = self.text, !currentText.isEmpty {
            let isCompleteWord = MnemonicWordListEN.contains { word in
                word.lowercased() == currentText.lowercased()
            }
            
            if isCompleteWord {
                // Don't accept suggestions for complete words
                return false
            }
        }
        
        acceptSuggestion()
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            updateSuggestion()
        }
        return result
    }
    
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            hideSuggestion()
            // Auto-correct typos when leaving the field
            autoCorrectTypo()
        }
        return result
    }
    
    // MARK: - Keyboard Shortcuts
    
    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(nextField)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(acceptSuggestion)),
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(acceptSuggestion))
        ]
    }
    
    @objc private func nextField() {
        // This will be handled by the parent view controller
        sendActions(for: .editingDidEndOnExit)
    }
    
    func clearSuggestion() {
        hideSuggestion()
    }
    
    override func deleteBackward() {
        super.deleteBackward()
        // Update suggestion after deletion
        DispatchQueue.main.async {
            self.updateSuggestion()
        }
    }
    
    private func autoCorrectTypo() {
        guard let text = self.text, !text.isEmpty else { return }
        
        // Don't auto-correct if it's already a valid word
        let isAlreadyValid = MnemonicWordListEN.contains { word in
            word.lowercased() == text.lowercased()
        }
        
        if isAlreadyValid {
            return
        }
        
        // Find the closest matching word using Levenshtein distance
        let closestWord = findClosestWord(to: text.lowercased())
        
        if let correctedWord = closestWord {
            // Only correct if the distance is reasonable (1-2 characters difference)
            let distance = levenshteinDistance(text.lowercased(), correctedWord)
            let maxDistance = min(2, text.count - 1) // Don't correct if distance is too high
            
            if distance <= maxDistance && distance > 0 {
                print("Auto-correcting '\(text)' to '\(correctedWord)' (distance: \(distance))")
                
                // Show visual feedback for the correction
                showCorrectionFeedback()
                
                self.text = correctedWord
                // Notify delegate of the change
                sendActions(for: .editingChanged)
            }
        }
    }
    
    private func showCorrectionFeedback() {
        // Store original background color
        let originalColor = self.backgroundColor
        
        // Flash green briefly to indicate correction
        UIView.animate(withDuration: 0.1, animations: {
            self.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.3)
        }) { _ in
            UIView.animate(withDuration: 0.2) {
                self.backgroundColor = originalColor
            }
        }
    }
    
    private func findClosestWord(to input: String) -> String? {
        var closestWord: String?
        var minDistance = Int.max
        
        for word in MnemonicWordListEN {
            let distance = levenshteinDistance(input, word.lowercased())
            if distance < minDistance {
                minDistance = distance
                closestWord = word
            }
        }
        
        return closestWord
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let empty = Array(repeating: 0, count: s2.count + 1)
        var last = Array(0...s2.count)
        
        for (i, char1) in s1.enumerated() {
            var current = [i + 1] + empty
            for (j, char2) in s2.enumerated() {
                current[j + 1] = char1 == char2 ? last[j] : min(last[j], last[j + 1], current[j]) + 1
            }
            last = current
        }
        return last[s2.count]
    }
} 