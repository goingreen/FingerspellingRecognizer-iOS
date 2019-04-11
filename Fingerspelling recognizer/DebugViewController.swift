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

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            let datasetController = DatasetViewController()
            present(datasetController, animated: true, completion: nil)
        } else {
            let cell = tableView.cellForRow(at: indexPath)!
            if cell.accessoryType == .checkmark {
                cell.accessoryType = .none
            } else {
                cell.accessoryType = .checkmark
            }
        }
    }
}
