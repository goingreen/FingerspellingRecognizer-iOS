//
//  DebugViewController.swift
//  Fingerspelling recognizer
//
//  Created by Artur Antonov on 12/04/2019.
//  Copyright © 2019 aa. All rights reserved.
//

import UIKit

class DebugViewController: UITableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    @IBAction
    func doneButtonTapped() {
        dismiss(animated: true, completion: nil)
    }
}

extension DebugViewController {
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row == 1 {
            cell.accessoryType = Settings.autodetectHand ? .checkmark : .none
        } else if indexPath.row == 2 {
            cell.accessoryType = Settings.debugMode ? .checkmark : .none
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            let datasetController = DatasetViewController()
            present(datasetController, animated: true, completion: nil)
        } else {
            let cell = tableView.cellForRow(at: indexPath)!
            var newValue = false
            if cell.accessoryType == .checkmark {
                cell.accessoryType = .none
                newValue = false
            } else {
                cell.accessoryType = .checkmark
                newValue = true
            }
            if indexPath.row == 1 {
                Settings.autodetectHand = newValue
            } else {
                Settings.debugMode = newValue
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
