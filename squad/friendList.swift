//
//  friendList.swift
//  squad
//
//  Created by Ian Thomas on 11/4/16.
//  Copyright © 2016 KKIT Creations. All rights reserved.
//

import UIKit

class friendList : UITableViewController {

    
    var items: [individualFriend] = []
    let userId = UserDefaults.standard.object(forKey: kDocentUserId) as! String
    

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationItem.title = "Friends List"

        let friendsPath = FIRDatabase.database().reference().child("users").child(userId).child("friends")
        friendsPath.observe(.value, with: { snapshot in
            var newItems: [individualFriend] = []
            
            for item in snapshot.children {
                let requestItem = individualFriend(snapshot: item as! FIRDataSnapshot)
                newItems.append(requestItem)
            }
            
            self.items = newItems
            self.tableView.reloadData()
        })
        
    }
    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "itemCell", for: indexPath)
        let requestItem = items[indexPath.row]
        
        cell.textLabel?.text = requestItem.key
        
        return cell
    }
    
    /*
     
     
     UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addNewFriend:)];
     add.tintColor = [UIColor whiteColor];
     
     self.navigationItem.rightBarButtonItem = add;
     
     
     -(IBAction)addNewFriend:(id)sender {
     
     [self performSegueWithIdentifier:@"addNewFriend" sender:self];
     }
     
     
     
     
     */
    
    
}
