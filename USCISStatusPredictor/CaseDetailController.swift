//
//  CaseDetailController.swift
//  UscisStatusPredictor
//
//  Created by ginny lee on 4/18/19.
//  Copyright © 2019 bing. All rights reserved.
//

import UIKit
import CoreData
import Charts
import Firebase

class CaseDetailController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
    var appDelegate = UIApplication.shared.delegate as? AppDelegate
    lazy var managedContext = appDelegate!.persistentContainer.viewContext
    let searchCount = 300 //TODO change to 300
    var caseTypeMap: [String: String] = [:] //key: number, value: type
    var caseStatusMap: [String: String] = [:] //key: number, value: status
    static let formatter = DateFormatter()
    var pieChartView = PieChartView()
    var textview = UITextView()
    let statusMap = [
        "Fingerprint Fee Was Received": "Fingerprint",
        "Fingerprint Review Was Completed": "Fingerprint",
        "Case Was Received": "Case Received",
        "Case Was Approved": "Approved",
        "Card Was Mailed To Me": "Approved",
        "Card Was Picked Up By The United States Postal Service": "Approved",
        "New Card Is Being Produced": "Approved",
        "Request for Initial Evidence Was Mailed": "RFE",
        "Response To USCIS' Request For Evidence Was Received": "RFE",
        "Interview Cancelled": "Interview Ready",
        "Case is Ready to Be Scheduled for An Interview": "Interview Ready",
        "Interview Was Scheduled": "Interview Scheduled",
        "Case Rejected Because The Version Of The Form I Sent Is No Longer Accepted": "Rejected",
        "Case Was Rejected Because It Was Improperly Filed": "Rejected",
        "Case Rejected Because I Sent An Incorrect Fee": "Rejected"
    ]
    let pFormatter: NumberFormatter = NumberFormatter()
    let ref = Database.database().reference(fromURL: "https://uscisstatuspredictor.firebaseio.com/")

    var number: String? {
        didSet {
            navigationItem.title = number
        }
    }
    var type: String?
    
    func initPFormatter() {
        pFormatter.numberStyle = .percent
        pFormatter.maximumFractionDigits = 0
        pFormatter.multiplier = 1
        pFormatter.percentSymbol = " %"
    }
    
    override open var shouldAutorotate: Bool {
        return false
    }
    
    @objc func refreshDataFromWeb() {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CaseStats")
        fetchRequest.predicate = NSPredicate(format: "mainNumber = %@", number!)
        var caseStat: CaseStats = CaseStats()
        do {
            let caseStats = try managedContext.fetch(fetchRequest)
            assert(caseStats.count < 2) // we shouldn't have any duplicates in CD
            
            if(caseStats.count == 1) {
                caseStat = caseStats.first as! CaseStats
                
                if(-caseStat.refreshTime!.timeIntervalSinceNow / 3600 < 12) {
                    // log
                    Analytics.logEvent(AnalyticsParameterSearchTerm, parameters: ["refresh" : "disabled"])
                    let caseRef = ref.child(number!)
                    let values = ["action": "refresh-existed", "date": CaseDetailController.convertDateToString(date: Date())]
                    caseRef.updateChildValues(values)
                    
                    self.showToast(message: "Refresh too frequently: To avoid USCIS IP ban, next refresh will be available " + String(Int(12 + caseStat.refreshTime!.timeIntervalSinceNow / 3600)) + " hours later.")
                    return
                }
                let caseDetails = caseStat.caseDetails!.split(separator: ":")
                for caseDetail in caseDetails {
                    let details = caseDetail.split(separator: ",")
                    caseTypeMap[String(details[0])] = String(details[1])
                    caseStatusMap[String(details[0])] = String(details[2])
                }
            } else { // count == 0
                caseStat = CaseStats(context: managedContext)
            }
        } catch {
            // handle error
            print("Could not be able to fetch result")
        }
        // update the info from the web
        var diffCountMap: [String:Int] = [:] // key: status change, value: count
        var details : [String] = []
        let prefix = String(number!.prefix(3))
        let suffixNumber = Int(String(number!.suffix(10)))
        var count = 0
        var sameTypeCount = 0
        DispatchQueue.global(priority: .default).async {
            for i in stride(from: suffixNumber!-self.searchCount-1, to: suffixNumber!, by: 1) {
                let currentNumber = prefix + String(i)
                if(self.caseTypeMap.keys.contains(currentNumber) && !(self.caseTypeMap[currentNumber] ?? "").isEmpty && (self.caseTypeMap[currentNumber] != self.type)) {
                    print("not the same type, no download")
                } else {
                    let currentCase = WebHelper.getCaseDetailFromUSCIS(number: currentNumber)
                    if(currentCase.isValid()) {
                        let convertedCaseStatus = (self.statusMap[currentCase.status!] ?? "Other")
                        details.append(currentCase.number! + "," + (currentCase.type ?? "") + "," + convertedCaseStatus)
                        if(currentCase.type! == self.type) {
                            sameTypeCount = sameTypeCount + 1
                            if((self.caseStatusMap[currentCase.number!] != nil) && (self.caseStatusMap[currentCase.number!] != convertedCaseStatus)) {
                                let key = self.caseStatusMap[currentCase.number!]! + " -> " + convertedCaseStatus
                                diffCountMap[key] = 1 + (diffCountMap[key] ?? 0)
                            }
                        }
                        self.caseTypeMap[currentCase.number!] = currentCase.type!
                        self.caseStatusMap[currentCase.number!] = convertedCaseStatus
                    }
                }
                
                DispatchQueue.main.sync {
                    self.drawData(caseDetails: details.joined(separator: ":"), graphDescription: "Processed " + String(count) + " out of " + String(self.searchCount) + " cases.")
                }
                count = count + 1
            }
            
            let caseRef2 = self.ref.child(self.number!)
            let values2 = ["action": "refresh-new", "count": String(sameTypeCount), "date": CaseDetailController.convertDateToString(date: Date())]
            caseRef2.updateChildValues(values2)
            
            // save the info to local
            let detailsString = details.joined(separator: ":")
            print(detailsString)
            caseStat.mainNumber = self.number
            caseStat.refreshTime = Date()
            caseStat.caseDetails = detailsString
            
            do {
                try self.managedContext.save()
                print("Saved successfully")
            } catch let error as NSError {
                print("Could not save. \(error), \(error.userInfo)")
            }
            
            DispatchQueue.main.sync {
                var graphDescription = "Last refresh time: " + CaseDetailController.convertDateToString(date: caseStat.refreshTime!)
                if(diffCountMap.count > 0) {
                    graphDescription += "\n\n"
                    graphDescription += "Status changes after last update:\n"
                    for (key, count) in diffCountMap {
                        graphDescription += "  " + key + ": " + String(count) + " entries\n"
                    }
                }
                // draw the graph
                self.drawData(caseDetails: detailsString, graphDescription: graphDescription)
            }
        }
        Analytics.logEvent(AnalyticsParameterSearchTerm, parameters: ["refresh" : "enabled"])
    }
    
    func loadData() {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CaseStats")
        fetchRequest.predicate = NSPredicate(format: "mainNumber = %@", number!)
        
        do {
            let caseStats = try managedContext.fetch(fetchRequest)
            assert(caseStats.count < 2) // we shouldn't have any duplicates in CD
            
            if let caseStat = caseStats.first as? CaseStats {
                print(caseStat.caseDetails)
                
                drawData(caseDetails: caseStat.caseDetails ?? "", graphDescription: "Last refresh time:" + CaseDetailController.convertDateToString(date: caseStat.refreshTime!))
            } else {
                refreshDataFromWeb()
            }
        } catch {
            // handle error
        }
    }
    
    func drawData(caseDetails: String, graphDescription: String) {
        pieChartView.backgroundColor = UIColor.white
        //pieChartView.chartDescription?.text = "Similar cases"
        let colors = ChartColorTemplates.vordiplom()
            + ChartColorTemplates.joyful()
            + ChartColorTemplates.colorful()
            + ChartColorTemplates.liberty()
            + ChartColorTemplates.pastel()
            + [UIColor(red: 51/255, green: 181/255, blue: 229/255, alpha: 1)
        ]
        
        var dataEntries: [PieChartDataEntry] = []
        
        var statusNumberMap: [String: Int] = [:]
        let caseDetailsArray = caseDetails.split(separator: ":")
        var overallCount = 0
        for item in caseDetailsArray {
            let details = item.split(separator: ",")
            if(String(details[1]) == type) {
                let detailedStatus = String(details[2])
                statusNumberMap[detailedStatus] = (statusNumberMap[detailedStatus] ?? 0) + 1
                overallCount += 1
            }
        }
        Analytics.logEvent(AnalyticsEventViewItem, parameters: [type ?? "" : overallCount])
        
        for (status, count) in statusNumberMap {
            let entry = PieChartDataEntry(value: Double(count), label: status + ":" + String(count))
            dataEntries.append(entry)
        }
        
        let pieChartDataSet = PieChartDataSet(entries: dataEntries, label: "")
        pieChartDataSet.colors = colors
        let pieChartData = PieChartData(dataSet: pieChartDataSet)
        
        let formatter = DefaultValueFormatter(formatter: pFormatter)
        pieChartData.setValueFormatter(formatter)
        pieChartData.setValueTextColor(.black)
        
        pieChartView.data = pieChartData
        pieChartView.centerText = String(overallCount) + " similar " + (type ?? "") + " cases"
        pieChartView.usePercentValuesEnabled = true
        pieChartView.entryLabelColor = UIColor.black
        
        // draw the underlying scrollable text view
        textview.text = graphDescription
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        initPFormatter()
        let refreshBarButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshDataFromWeb))
        self.navigationItem.rightBarButtonItem = refreshBarButton
        collectionView?.backgroundColor = UIColor.white
        pieChartView = PieChartView(frame: CGRect(x: 0, y: 100, width: self.view.frame.size.width, height: self.view.frame.size.height-300))
        textview = UITextView(frame: CGRect(x: 0, y: self.view.frame.size.height-200, width: self.view.frame.size.width, height: 200))
        self.view.addSubview(pieChartView)
        self.view.addSubview(textview)
        
        loadData()
    }
    
    func showToast(message : String) {
        let toastLabel = UILabel(frame: CGRect(x: self.view.frame.size.width/2 - 150, y: self.view.frame.size.height-150, width: 300, height: 100))
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        toastLabel.textColor = UIColor.white
        toastLabel.textAlignment = .center;
        toastLabel.font = UIFont(name: "Montserrat-Light", size: 10.0)
        toastLabel.text = message
        toastLabel.alpha = 1.0
        toastLabel.layer.cornerRadius = 10;
        toastLabel.clipsToBounds  =  true
        toastLabel.lineBreakMode = .byWordWrapping
        toastLabel.numberOfLines = 4
        
        self.view.addSubview(toastLabel)
        UIView.animate(withDuration: 8.0, delay: 0.1, options: .curveEaseOut, animations: {
            toastLabel.alpha = 0.0
        }, completion: {(isCompleted) in
            toastLabel.removeFromSuperview()
        })
    }
    
    static func convertDateToString(date: Date) -> String {
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
