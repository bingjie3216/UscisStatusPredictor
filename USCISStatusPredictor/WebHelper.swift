//
//  WebHelper.swift
//  UscisStatusPredictor
//
//  Created by ginny lee on 4/21/19.
//  Copyright © 2019 bing. All rights reserved.
//

import Foundation

class WebHelper {
    
    static func getCaseDetailFromUSCIS(number: String) -> Case {
        let uscisUrlString = "https://egov.uscis.gov/casestatus/mycasestatus.do?changeLocale=&appReceiptNum=" + number + "&initCaseSearch=CHECK+STATUS"
        let currentCase = Case()
        
        guard let uscisUrl = URL(string: uscisUrlString) else {
            print("Error: \(uscisUrlString) doesn't seem to be a valid URL")
            return currentCase
        }
        
        do {
            let rawUscisContent = try String(contentsOf: uscisUrl, encoding: .ascii)
            currentCase.number = number
            let uscisContent = getStringBetweenStrings(content: rawUscisContent, start: "<div class=\"rows text-center\">", end: "</div>")
            currentCase.status = getStringBetweenStrings(content: uscisContent, start: "<h1>", end: "</h1>")
            var rawParagraph = getStringBetweenStrings(content: uscisContent, start: "<p>", end: "</p>")
            currentCase.type = getStringBetweenStrings(content: rawParagraph, start: "your Form ", end: ",")
            var dateStartMark = "On "
            if(rawParagraph.starts(with: "As of ")) {
                dateStartMark = "As of "
            }
            if let dateStartRange = rawParagraph.range(of: dateStartMark) {
                rawParagraph.removeSubrange(rawParagraph.startIndex..<dateStartRange.upperBound)
            }
            let wordArray = rawParagraph.components(separatedBy: ",")
            if(wordArray.count >= 2 && wordArray[1].isNumeric) {
                currentCase.updateDate = wordArray[0] + "," + wordArray[1]
            } else {
                currentCase.updateDate = ""
            }
            print("HTML : \(uscisContent)")
        } catch let error {
            print("Error: \(error)")
        }
        return currentCase
    }
    
    static func getStringBetweenStrings(content: String, start: String, end: String) -> String {
        var currentContent = content
        if let startDivRange = currentContent.range(of: start) {
            currentContent.removeSubrange(currentContent.startIndex..<startDivRange.upperBound)
        }
        if let endDivRange = currentContent.range(of: end) {
            currentContent.removeSubrange(endDivRange.lowerBound..<currentContent.endIndex)
        }
        return currentContent
    }
}

extension String {
    var isNumeric: Bool {
        guard self.characters.count > 0 else { return false }
        let nums: Set<Character> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", " "]
        return Set(self.characters).isSubset(of: nums)
    }
}
