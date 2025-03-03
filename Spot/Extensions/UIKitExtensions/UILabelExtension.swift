//
//  UILabelExtension.swift
//  Spot
//
//  Created by Oforkanji Odekpe on 10/22/22.
//  Copyright © 2022 sp0t, LLC. All rights reserved.
//

import Firebase
import UIKit

/// https://stackoverflow.com/questions/32309247/add-read-more-to-the-end-of-uilabel

extension UILabel {
    
    // MARK: - This should be removed!!!
    // It's not a good practive to initialize views this way with closures
    @available(*, deprecated, message: "This initializer will be removed in the future. It's a practice")
    convenience init(configureHandler: (Self) -> Void) {
        self.init()
        configureHandler(self)
    }
    
    func addTrailing(with trailingText: String, moreText: String, moreTextFont: UIFont?, moreTextColor: UIColor) {
        
        let readMoreText: String = trailingText + moreText
        if self.visibleTextLength == 0 { return }
        
        let lengthForVisibleString: Int = self.visibleTextLength
        
        if let myText = self.text {
            
            let mutableString = NSString(string: myText) /// use mutable string for length for correct length calculations
            
            let trimmedString: String? = mutableString.replacingCharacters(in: NSRange(location: lengthForVisibleString, length: mutableString.length - lengthForVisibleString), with: "")
            let readMoreLength: Int = (readMoreText.count)
            let safeTrimmedString = NSString(string: trimmedString ?? "")
            if safeTrimmedString.length <= readMoreLength { return }
            
            // "safeTrimmedString.count - readMoreLength" should never be less then the readMoreLength because it'll be a negative value and will crash
            let trimmedForReadMore: String = (safeTrimmedString as NSString)
                .replacingCharacters(
                    in: NSRange(
                        location: safeTrimmedString.length - readMoreLength,
                        length: readMoreLength
                    ),
                    with: ""
                ) + trailingText
            
            let answerAttributed = NSMutableAttributedString(string: trimmedForReadMore, attributes: [NSAttributedString.Key.font: self.font as Any])
            let readMoreAttributed = NSMutableAttributedString(string: moreText, attributes: [NSAttributedString.Key.font: moreTextFont as Any, NSAttributedString.Key.foregroundColor: moreTextColor])
            answerAttributed.append(readMoreAttributed)
            self.attributedText = answerAttributed
        }
    }
    
    var visibleTextLength: Int {
        
        let font: UIFont = self.font
        let mode: NSLineBreakMode = self.lineBreakMode
        let labelWidth: CGFloat = self.frame.size.width
        let labelHeight: CGFloat = self.frame.size.height
        let sizeConstraint = CGSize(width: labelWidth, height: CGFloat.greatestFiniteMagnitude)
        
        if let myText = self.text {
            
            let attributes: [AnyHashable: Any] = [NSAttributedString.Key.font: font]
            let attributedText = NSAttributedString(string: myText, attributes: attributes as? [NSAttributedString.Key: Any])
            let boundingRect: CGRect = attributedText.boundingRect(with: sizeConstraint, options: .usesLineFragmentOrigin, context: nil)
            
            if boundingRect.size.height > labelHeight {
                var index: Int = 0
                var prev: Int = 0
                let characterSet = CharacterSet.whitespacesAndNewlines
                repeat {
                    prev = index
                    if mode == NSLineBreakMode.byCharWrapping {
                        index += 1
                    } else {
                        index = (myText as NSString).rangeOfCharacter(from: characterSet, options: [], range: NSRange(location: index + 1, length: myText.count - index - 1)).location
                    }
                } while index != NSNotFound
                && index < myText.count
                && (myText as NSString)
                    .substring(to: index)
                    .boundingRect(
                        with: sizeConstraint,
                        options: .usesLineFragmentOrigin,
                        attributes: attributes as? [NSAttributedString.Key: Any],
                        context: nil
                    ).size.height <= labelHeight
                
                return prev
            }
        }

        return self.text?.count ?? 0
    }
    
    var maxNumberOfLines: Int {
        let maxSize = CGSize(width: frame.size.width, height: CGFloat(MAXFLOAT))
        let text = (self.text ?? "") as NSString
        let textHeight = text.boundingRect(with: maxSize, options: .usesLineFragmentOrigin, attributes: [.font: font as Any], context: nil).height
        let lineHeight = font.lineHeight
        return Int(ceil(textHeight / lineHeight))
    }

    func createBorderedLabel(text: String, strokeColor: UIColor? = .white, textColor: UIColor? = .black, strokeWidth: Int, font: UIFont?) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.strokeColor: strokeColor as Any,
            NSAttributedString.Key.foregroundColor: textColor as Any,
            NSAttributedString.Key.strokeWidth: strokeWidth,
            NSAttributedString.Key.font: font as Any
        ]
        self.attributedText = NSAttributedString(string: text, attributes: attributes)
    }
}
