//
//  ViewController.swift
//  UscisStatusPredictor
//
//  Created by ginny lee on 4/13/19.
//  Copyright © 2019 bing. All rights reserved.
//

import UIKit
import CoreData
import Firebase

class Case: NSObject {
    let characterset = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ")

    var number: String?
    var updateDate: String?
    var status: String?
    var type: String?
    var userRefreshDate: NSDate?
    
    func isValid() -> Bool {
        if((status ?? "").isEmpty || (type ?? "").isEmpty || (updateDate ?? "").isEmpty) {
            return false
        }
        if((status ?? "").contains(":") || (status ?? "").contains("http")) {
            return false
        }
        if (status ?? "").rangeOfCharacter(from: characterset.inverted) != nil {
            return false
        }
        return true
    }
}

class CaseController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
    private let cellId = "cellId"
    var addCaseAction = UIAlertAction()
    var cases: [NSManagedObject] = []
    var appDelegate = UIApplication.shared.delegate as? AppDelegate
    lazy var managedContext = appDelegate!.persistentContainer.viewContext
    
    func updateUseCasesFromStorage() {
        cases = []
        //fetch
        let fetchRequest =
            NSFetchRequest<NSManagedObject>(entityName: "UserCases")
        do {
            let currentCases = try managedContext.fetch(fetchRequest)
            cases.append(contentsOf: currentCases)
        } catch let error as NSError {
            print("Could not fetch. \(error), \(error.userInfo)")
        }
    }
    
    @objc private func addCase() {
        let alert = UIAlertController(title: "Enter USCIS Receipt Number", message: "A unique 13-character identifier, e.g. MSC0123456789", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addTextField { (textField) in
            textField.placeholder = "Enter Your Receipt Number"
            textField.addTarget(self, action: #selector(self.textChanged(_:)), for: .editingChanged)
        }
        
        addCaseAction = UIAlertAction(title: "Add Case", style: .default, handler: { action in
            if let caseNumber = alert.textFields?.first?.text {
                print("Get the case number: \(caseNumber)")
                self.addNewCaseNumber(number:caseNumber)
                self.refreshCases()
                self.collectionView?.reloadData()
            }
        })
        addCaseAction.isEnabled = false
        alert.addAction(addCaseAction)
        
        self.present(alert, animated: true)
    }
    
    @objc func textChanged(_ sender:UITextField) {
        self.addCaseAction.isEnabled  = (sender.text?.count == 13)
    }
    
    override open var shouldAutorotate: Bool {
        return false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
        
        let addBarButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addCase))
        let refreshBarButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshCases))
        
        // Do any additional setup after loading the view, typically from a nib.
        navigationItem.title = "Your USCIS cases"
        self.navigationItem.rightBarButtonItems = [addBarButton, refreshBarButton]
        
        updateUseCasesFromStorage()
        
        refreshCases()
        
        collectionView?.backgroundColor = UIColor.white
        collectionView?.alwaysBounceVertical = true
        collectionView?.register(CaseCell.self, forCellWithReuseIdentifier: cellId)
        
        let textview = UITextView(frame: CGRect(x: 0, y: self.view.frame.size.height-100, width: self.view.frame.size.width, height: 100))
        textview.text = "Last refresh time: " + ToolHelper.convertDateToString(date: Date())
        textview.textAlignment = NSTextAlignment.center
        self.view.addSubview(textview)
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return cases.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellId, for: indexPath) as! CaseCell
        
        let currentCase = cases[indexPath.item]
        cell.numberTextView.text = currentCase.value(forKeyPath: "number") as? String
        cell.statusTextView.text = currentCase.value(forKey: "status") as? String
        cell.typeTextView.text = currentCase.value(forKey: "type") as? String
        cell.updateTimeTextView.text = currentCase.value(forKey: "updateDate") as? String
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: view.frame.width, height: 80)
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let layout = UICollectionViewFlowLayout()
        let controller = CaseDetailController(collectionViewLayout: layout)
        let caseType = cases[indexPath.item].value(forKeyPath: "type") as? String
        if((caseType ?? "").isEmpty) {
            ToolHelper.showToast(view:self.view, message: "Could not get case details, please check your internet connection, or retry tomorrow if your IP is banned by USCIS website")
            return
        }
        controller.number = cases[indexPath.item].value(forKeyPath: "number") as? String
        controller.type = caseType
        navigationController?.pushViewController(controller, animated: true)
    }
    
    func addNewCaseNumber(number: String) {
        for currentCase in cases {
            let currentNumber = currentCase.value(forKey: "number") as? String
            if(currentNumber == number) {
                return
            }
        }
        let entity =
            NSEntityDescription.entity(forEntityName: "UserCases",
                                       in: managedContext)!
        let newCase = NSManagedObject(entity: entity,
                                      insertInto: managedContext)
        newCase.setValue(number, forKeyPath: "number")
        cases.append(newCase)
        do {
            try managedContext.save()
        } catch let error as NSError {
            print("Could not save. \(error), \(error.userInfo)")
        }
    }
    
    @objc func refreshCases() {
        for currentCaseObject in cases {
            let currentNumber = currentCaseObject.value(forKeyPath: "number") as? String
            let currentCase = WebHelper.getCaseDetailFromUSCIS(number: currentNumber!)
            if(currentCase.isValid()) {
                currentCaseObject.setValue(currentCase.status, forKey: "status")
                currentCaseObject.setValue(currentCase.updateDate, forKey: "updateDate")
                currentCaseObject.setValue(currentCase.type, forKey: "type")
            }
        }
        do {
            try managedContext.save()
        } catch let error as NSError {
            print("Could not save. \(error), \(error.userInfo)")
        }
        self.updateUseCasesFromStorage()
        self.collectionView?.reloadData()
    }
}

class CaseCell: BaseCell {
    let numberTextView: UITextView = {
        let textview = UITextView()
        textview.text = "MSC1990268538"
        textview.font = .systemFont(ofSize: 15)
        textview.isEditable = false
        textview.isUserInteractionEnabled = false
        return textview
    }()
    
    let updateTimeTextView: UITextView = {
        let textview = UITextView()
        textview.text = "Nov 27, 2018"
        textview.textAlignment = .right
        textview.font = .systemFont(ofSize: 12)
        textview.textColor = UIColor.darkGray
        textview.isEditable = false
        textview.isUserInteractionEnabled = false
        return textview
    } ()
    
    let statusTextView: UITextView = {
        let textview = UITextView()
        textview.text = "Fingerprint Fee Was Received"
        textview.font = .systemFont(ofSize: 12)
        textview.isEditable = false
        textview.isUserInteractionEnabled = false
        return textview
    } ()
    
    let typeTextView: UITextView = {
        let textview = UITextView()
        textview.text = "I-485"
        textview.textAlignment = .right
        textview.font = .systemFont(ofSize: 12)
        textview.textColor = UIColor.darkGray
        textview.isEditable = false
        textview.isUserInteractionEnabled = false
        return textview
    } ()
    
    let dividerLineView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white:0.5, alpha:0.5)
        return view
    }()
    
    override func setupViews() {
        backgroundColor = UIColor.white
        
        addSubview(numberTextView)
        addSubview(updateTimeTextView)
        addSubview(statusTextView)
        addSubview(typeTextView)
        addSubview(dividerLineView)
        
        
        numberTextView.translatesAutoresizingMaskIntoConstraints = false
        updateTimeTextView.translatesAutoresizingMaskIntoConstraints = false
        statusTextView.translatesAutoresizingMaskIntoConstraints = false
        typeTextView.translatesAutoresizingMaskIntoConstraints = false
        dividerLineView.translatesAutoresizingMaskIntoConstraints = false
        
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-5-[v0(160)]", options: NSLayoutConstraint.FormatOptions.alignAllLeft, metrics: nil, views: ["v0": numberTextView]))
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-5-[v0(34)]", options: NSLayoutConstraint.FormatOptions.alignAllTop, metrics: nil, views: ["v0": numberTextView]))
        addConstraint(NSLayoutConstraint(item: numberTextView, attribute:.centerY, relatedBy:.equal, toItem:self, attribute: .centerY, multiplier:1, constant:0))
        
        
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:[v0(130)]-5-|", options: NSLayoutConstraint.FormatOptions.alignAllTop, metrics: nil, views: ["v0": updateTimeTextView]))
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-5-[v0(34)]", options: NSLayoutConstraint.FormatOptions.alignAllTop, metrics: nil, views: ["v0": updateTimeTextView]))
        addConstraint(NSLayoutConstraint(item: updateTimeTextView, attribute:.centerY, relatedBy:.equal, toItem:self, attribute: .centerY, multiplier:1, constant:0))
        
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-5-[v0(250)]", options: NSLayoutConstraint.FormatOptions.alignAllRight, metrics: nil, views: ["v0": statusTextView]))
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[v0(45)]-2-|", options: NSLayoutConstraint.FormatOptions.alignAllTop, metrics: nil, views: ["v0": statusTextView]))
        addConstraint(NSLayoutConstraint(item: statusTextView, attribute:.centerY, relatedBy:.equal, toItem:self, attribute: .centerY, multiplier:1, constant:0))
        
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:[v0(50)]-5-|", options: NSLayoutConstraint.FormatOptions.alignAllRight, metrics: nil, views: ["v0": typeTextView]))
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[v0(45)]-2-|", options: NSLayoutConstraint.FormatOptions.alignAllTop, metrics: nil, views: ["v0": typeTextView]))
        addConstraint(NSLayoutConstraint(item: statusTextView, attribute:.centerY, relatedBy:.equal, toItem:self, attribute: .centerY, multiplier:1, constant:0))
        
        
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-2-[v0]-2-|", options: NSLayoutConstraint.FormatOptions.alignAllCenterX, metrics: nil, views: ["v0":dividerLineView]))
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[v0(1)]", options: NSLayoutConstraint.FormatOptions.alignAllCenterY, metrics: nil, views: ["v0":dividerLineView]))
    }
}

class BaseCell: UICollectionViewCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupViews() {
        backgroundColor = UIColor.white
    }
}
