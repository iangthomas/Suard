/*
 * Copyright (c) 2015 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

//  Code Modifications © 2017 Geodex Systems
//  All Rights Reserved.

import UIKit
//import Photos
import JSQMessagesViewController
import OneSignal


final class ChatViewController: JSQMessagesViewController {
    
    // MARK: Properties
    private let imageURLNotSetKey = "NOTSET"
    
    var channelRef: FIRDatabaseReference?
    var listOfMessagesAlreadySentNotificationsFor: Dictionary<String, String> = [:]

    
    var thePushIdString: String?
    
    
    private lazy var messageRef: FIRDatabaseReference = self.channelRef!.child("messages")
    private lazy var userIsTypingRef: FIRDatabaseReference = self.channelRef!.child("typingIndicator").child(self.senderId)
    private lazy var usersTypingQuery: FIRDatabaseQuery = self.channelRef!.child("typingIndicator").queryOrderedByValue().queryEqual(toValue: true)
    
    private var newMessageRefHandle: FIRDatabaseHandle?
    private var updatedMessageRefHandle: FIRDatabaseHandle?
    
    private var messages: [JSQMessage] = []
    private var photoMessageMap = [String: JSQPhotoMediaItem]()
    
    private var localTyping = false
    var channel: Channel? {
        didSet {
            title = channel?.name
        }
    }
    
    var isTyping: Bool {
        get {
            return localTyping
        }
        set {
            localTyping = newValue
            userIsTypingRef.setValue(newValue)
        }
    }
    
    lazy var outgoingBubbleImageView: JSQMessagesBubbleImage = self.setupOutgoingBubble()
    lazy var incomingBubbleImageView: JSQMessagesBubbleImage = self.setupIncomingBubble()
    
    // MARK: View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        listOfMessagesAlreadySentNotificationsFor = [:]
        
        self.senderId = FIRAuth.auth()?.currentUser?.uid
        observeMessages()
        
        // No avatars
        collectionView!.collectionViewLayout.incomingAvatarViewSize = CGSize.zero
        collectionView!.collectionViewLayout.outgoingAvatarViewSize = CGSize.zero
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        observeTyping()
    }
    
    deinit {
        if let refHandle = newMessageRefHandle {
            messageRef.removeObserver(withHandle: refHandle)
        }
        if let refHandle = updatedMessageRefHandle {
            messageRef.removeObserver(withHandle: refHandle)
        }
    }
    
    // MARK: Collection view data source (and related) methods
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageDataForItemAt indexPath: IndexPath!) -> JSQMessageData! {
        return messages[indexPath.item]
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return messages.count
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageBubbleImageDataForItemAt indexPath: IndexPath!) -> JSQMessageBubbleImageDataSource! {
        let message = messages[indexPath.item] // 1
        if message.senderId == senderId { // 2
            return outgoingBubbleImageView
        } else { // 3
            return incomingBubbleImageView
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = super.collectionView(collectionView, cellForItemAt: indexPath) as! JSQMessagesCollectionViewCell
        
        let message = messages[indexPath.item]
        
        if message.senderId == senderId { // 1
            cell.textView?.textColor = UIColor.white // 2
        } else {
            cell.textView?.textColor = UIColor.black // 3
        }
        
        return cell
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, avatarImageDataForItemAt indexPath: IndexPath!) -> JSQMessageAvatarImageDataSource! {
        return nil
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, layout collectionViewLayout: JSQMessagesCollectionViewFlowLayout!, heightForMessageBubbleTopLabelAt indexPath: IndexPath!) -> CGFloat {
        return 15
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView?, attributedTextForMessageBubbleTopLabelAt indexPath: IndexPath!) -> NSAttributedString? {
        let message = messages[indexPath.item]
        switch message.senderId {
        case senderId:
            return nil
        default:
            guard let senderDisplayName = message.senderDisplayName else {
                assertionFailure()
                return nil
            }
            return NSAttributedString(string: senderDisplayName)
        }
    }
    

    
    
    // MARK: Firebase related methods
    
    private func observeMessages() {

        messageRef = channelRef!.child("messages")
        let messageQuery = messageRef.queryLimited(toLast:25)
        
        // We can use the observe method to listen for new
        // messages being written to the Firebase DB
        newMessageRefHandle = messageQuery.observe(.childAdded, with: { (snapshot) -> Void in
            let messageData = snapshot.value as! Dictionary<String, String>
            
            if let id = messageData["senderId"] as String!, let name = messageData["senderName"] as String!, let text = messageData["text"] as String!, text.characters.count > 0, let recipientRead = messageData["recipientRead"] as String! {
                
                // the following block read unread messages
                var updatedRecipientRead = recipientRead
                let theMessageId = id

              //  if unread
                if recipientRead == "no" {
                // if you are not the intended recipient
                    if theMessageId != self.senderId {
                        // then read the message!
                        
                        
                        // only do this if the user is looking at the channel
                        if self.isViewLoaded == true && (self.view.window != nil) {
                            updatedRecipientRead = "yes"
                            
                            let newref = self.messageRef.child(snapshot.key).child("recipientRead")
                            
                            newref.setValue(updatedRecipientRead) { (error, ref) in
                                
                                if error == nil {
                                    // add comments here
                                    NotificationCenter.default.post(name: Notification.Name("decrementUnreadMessageCell"), object: messageData)
                                    NotificationCenter.default.post(name: Notification.Name("decrementFriendListBadgeIcon"), object: nil)
                                } else {
                                    // add comments here
                                }
                            }
                        }
                    }
                }
                
                
            
                self.addMessage(withId: id, name: name, text: text, recipientRead: updatedRecipientRead)
                self.finishReceivingMessage()
                
                
            } /*else if let id = messageData["senderId"] as String!, let photoURL = messageData["photoURL"] as String! {
                 if let mediaItem = JSQPhotoMediaItem(maskAsOutgoing: id == self.senderId) {
                 self.addPhotoMessage(withId: id, key: snapshot.key, mediaItem: mediaItem)
                 
                 if photoURL.hasPrefix("gs://") {
                 self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: nil)
                 }
                 }
             } */else {
                print("Error! Could not decode message data")
            }
        })
        
        // We can also use the observer method to listen for
        // changes to existing messages.
        // We use this to be notified when a photo has been stored
        // to the Firebase Storage, so we can update the message data
        
        /*
         updatedMessageRefHandle = messageRef.observe(.childChanged, with: { (snapshot) in
         let key = snapshot.key
         let messageData = snapshot.value as! Dictionary<String, String>
         
         if let photoURL = messageData["photoURL"] as String! {
         // The photo has been updated.
         if let mediaItem = self.photoMessageMap[key] {
         self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: key)
         }
         }
         })
         */
    }
    
    
    
    
    /*
     private func fetchImageDataAtURL(_ photoURL: String, forMediaItem mediaItem: JSQPhotoMediaItem, clearsPhotoMessageMapOnSuccessForKey key: String?) {
     let storageRef = FIRStorage.storage().reference(forURL: photoURL)
     storageRef.data(withMaxSize: INT64_MAX){ (data, error) in
     if let error = error {
     print("Error downloading image data: \(error)")
     return
     }
     
     storageRef.metadata(completion: { (metadata, metadataErr) in
     if let error = metadataErr {
     print("Error downloading metadata: \(error)")
     return
     }
     
     if (metadata?.contentType == "image/gif") {
     mediaItem.image = UIImage.gifWithData(data!)
     } else {
     mediaItem.image = UIImage.init(data: data!)
     }
     self.collectionView.reloadData()
     
     guard key != nil else {
     return
     }
     self.photoMessageMap.removeValue(forKey: key!)
     })
     }
     }
     */
    
    private func observeTyping() {
        let typingIndicatorRef = channelRef!.child("typingIndicator")
        userIsTypingRef = typingIndicatorRef.child(senderId)
        userIsTypingRef.onDisconnectRemoveValue()
        usersTypingQuery = typingIndicatorRef.queryOrderedByValue().queryEqual(toValue: true)
        
        usersTypingQuery.observe(.value) { (data: FIRDataSnapshot) in
            
            // You're the only typing, don't show the indicator
            if data.childrenCount == 1 && self.isTyping {
                return
            }
            
            // Are there others typing?
            self.showTypingIndicator = data.childrenCount > 0
            self.scrollToBottom(animated: true)
        }
    }
    
    override func didPressSend(_ button: UIButton!, withMessageText text: String!, senderId: String!, senderDisplayName: String!, date: Date!) {
        // 1
        let itemRef = messageRef.childByAutoId()
        
        // 2
        
        let formatter = Constants.internetTimeDateFormatter()

        let messageItem = [
            "senderId": senderId!,
            "senderName": senderDisplayName!,
            "text": text!,
            "date": formatter!.string(from: Date.init()),
            "recipientRead" : "no",
            ]
        
        // 3
        itemRef.setValue(messageItem)
        
        
        // 4 post notification
        
        OneSignal.setLocationShared(false)

        OneSignal.postNotification(["contents": ["en": messageItem["text"]], "headings": ["en": messageItem["senderName"]], "include_player_ids": [self.thePushIdString], "content_available" : true])

        
        // 5
        JSQSystemSoundPlayer.jsq_playMessageSentSound()
        
        // 6
        finishSendingMessage()
        isTyping = false
    }
    
    /*
    func sendPhotoMessage() -> String? {
        let itemRef = messageRef.childByAutoId()
        
        let messageItem = [
            "photoURL": imageURLNotSetKey,
            "senderId": senderId!,
            ]
        
        itemRef.setValue(messageItem)
        
        JSQSystemSoundPlayer.jsq_playMessageSentSound()
        
        finishSendingMessage()
        return itemRef.key
    }
    
    func setImageURL(_ url: String, forPhotoMessageWithKey key: String) {
        let itemRef = messageRef.child(key)
        itemRef.updateChildValues(["photoURL": url])
    }
    */
    // MARK: UI and User Interaction
    
    private func setupOutgoingBubble() -> JSQMessagesBubbleImage {
        let bubbleImageFactory = JSQMessagesBubbleImageFactory()
        return bubbleImageFactory!.outgoingMessagesBubbleImage(with: UIColor.jsq_messageBubbleBlue())
    }
    
    private func setupIncomingBubble() -> JSQMessagesBubbleImage {
        let bubbleImageFactory = JSQMessagesBubbleImageFactory()
        return bubbleImageFactory!.incomingMessagesBubbleImage(with: UIColor.jsq_messageBubbleLightGray())
    }
    
    /*
     override func didPressAccessoryButton(_ sender: UIButton) {
     let picker = UIImagePickerController()
     picker.delegate = self
     if (UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera)) {
     picker.sourceType = UIImagePickerControllerSourceType.camera
     } else {
     picker.sourceType = UIImagePickerControllerSourceType.photoLibrary
     }
     
     present(picker, animated: true, completion:nil)
     }*/
    
    private func addMessage(withId id: String, name: String, text: String) {
        if let message = JSQMessage(senderId: id, displayName: name, text: text) {
            messages.append(message)
        }
    }
    
    
    private func addMessage(withId id: String, name: String, text: String, recipientRead: String) {
        if let message = JSQMessage(senderId: id, displayName: name, text: text, recipientRead: recipientRead) {
            messages.append(message)
        }
    }
    
    
    /*
    private func addPhotoMessage(withId id: String, key: String, mediaItem: JSQPhotoMediaItem) {
        if let message = JSQMessage(senderId: id, displayName: "", media: mediaItem) {
            messages.append(message)
            
            if (mediaItem.image == nil) {
                photoMessageMap[key] = mediaItem
            }
            
            collectionView.reloadData()
        }
    }
    */
    // MARK: UITextViewDelegate methods
    
    override func textViewDidChange(_ textView: UITextView) {
        super.textViewDidChange(textView)
        // If the text is not empty, the user is typing
        isTyping = textView.text != ""
    }
    
}

// MARK: Image Picker Delegate
/*
 extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
 func imagePickerController(_ picker: UIImagePickerController,
 didFinishPickingMediaWithInfo info: [String : Any]) {
 
 picker.dismiss(animated: true, completion:nil)
 
 // 1
 if let photoReferenceUrl = info[UIImagePickerControllerReferenceURL] as? URL {
 // Handle picking a Photo from the Photo Library
 // 2
 let assets = PHAsset.fetchAssets(withALAssetURLs: [photoReferenceUrl], options: nil)
 let asset = assets.firstObject
 
 // 3
 if let key = sendPhotoMessage() {
 // 4
 asset?.requestContentEditingInput(with: nil, completionHandler: { (contentEditingInput, info) in
 let imageFileURL = contentEditingInput?.fullSizeImageURL
 
 // 5
 let path = "\(FIRAuth.auth()?.currentUser?.uid)/\(Int(Date.timeIntervalSinceReferenceDate * 1000))/\(photoReferenceUrl.lastPathComponent)"
 
 // 6
 self.storageRef.child(path).putFile(imageFileURL!, metadata: nil) { (metadata, error) in
 if let error = error {
 print("Error uploading photo: \(error.localizedDescription)")
 return
 }
 // 7
 self.setImageURL(self.storageRef.child((metadata?.path)!).description, forPhotoMessageWithKey: key)
 }
 })
 }
 } else {
 // Handle picking a Photo from the Camera - TODO
 }
 }
 
 func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
 picker.dismiss(animated: true, completion:nil)
 }
 }
 */
