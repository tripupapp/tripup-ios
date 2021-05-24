//
//  DataManager.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 15/11/2017.
//  Copyright © 2017 Vinoth Ramiah. All rights reserved.
//

import Foundation

protocol DataService {
    func uploadFile(at url: URL, callback: @escaping (_ url: URL?) -> Void)
    func downloadFile(at remotePath: URL, to url: URL, callback: @escaping (_ success: Bool) -> Void)
    func deleteFile(at url: URL, callback: @escaping (_ success: Bool) -> Void)
    func delete(_ object: String, callback: @escaping (_ success: Bool) -> Void)
}

class DataManager {
    enum Priority: Int {
        case low
        case high

        static func sort<T>(task1: Task<T>, task2: Task<T>) -> Bool {
            return task1.priority.rawValue > task2.priority.rawValue    // higher value = higher priority
        }
    }

    struct Task<T>: Hashable {
        let id: UUID
        let url: URL
        let priority: Priority
        let remote: URL?
        let callback: (T) -> Void

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: Task, rhs: Task) -> Bool {
            return lhs.id == rhs.id
        }

        init(url: URL, priority: Priority, callback: @escaping (T) -> Void) {
            self.init(remote: nil, url: url, priority: priority, callback: callback)
        }

        init(remote: URL?, url: URL, priority: Priority, callback: @escaping (T) -> Void) {
            self.id = UUID()
            self.remote = remote
            self.url = url
            self.priority = priority
            self.callback = callback
        }
    }

    private let dataService: DataService
    private let uploadQueue = DispatchQueue(label: String(describing: DataManager.self) + ".uploadQueue", target: .global())
    private let downloadQueue = DispatchQueue(label: String(describing: DataManager.self) + ".downloadQueue", target: .global())
    private var uploadTasks = PriorityQueue<Task<URL?>>(sort: Priority.sort)
    private var uploadsInProgress = Set<Task<URL?>>() {
        willSet {
            precondition(.on(uploadQueue))
        }
        didSet {
            guard uploadsInProgress.count < oldValue.count, let task = uploadTasks.dequeue() else { return }
            startUpload(task)
        }
    }
    private var downloadTasks = PriorityQueue<Task<Bool>>(sort: Priority.sort)
    private var downloadsInProgress = Set<Task<Bool>>() {
        willSet {
            precondition(.on(downloadQueue))
        }
        didSet {
            guard downloadsInProgress.count < oldValue.count, let task = downloadTasks.dequeue() else { return }
            startDownload(task)
        }
    }
    private let simultaneousTransfers: Int

    init(dataService: DataService, simultaneousTransfers: Int) {
        self.dataService = dataService
        self.simultaneousTransfers = simultaneousTransfers
    }

    private func startUpload(_ task: Task<URL?>) {
        precondition(.on(uploadQueue))
        dataService.uploadFile(at: task.url) { [weak self] url in
            self?.uploadQueue.async {
                self?.uploadsInProgress.remove(task)
            }
            task.callback(url)
        }
        uploadsInProgress.insert(task)
    }

    private func startDownload(_ task: Task<Bool>) {
        precondition(.on(downloadQueue))
        dataService.downloadFile(at: task.remote!, to: task.url) { [weak self] success in
            self?.downloadQueue.async {
                self?.downloadsInProgress.remove(task)
            }
            task.callback(success)
        }
        downloadsInProgress.insert(task)
    }

    func uploadFile(at url: URL, priority: Priority, callback: @escaping (URL?) -> Void) {
        let task = Task<URL?>(url: url, priority: priority, callback: callback)
        uploadQueue.async { [weak self] in
            guard let self = self else { return }
            if self.uploadsInProgress.count < self.simultaneousTransfers {
                self.startUpload(task)
            } else {
                self.uploadTasks.enqueue(task)
            }
        }
    }

    func downloadFile(at remotePath: URL, to url: URL, priority: Priority, callback: @escaping (Bool) -> Void) {
        let task = Task<Bool>(remote: remotePath, url: url, priority: priority, callback: callback)
        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            if self.downloadsInProgress.count < self.simultaneousTransfers {
                self.startDownload(task)
            } else {
                self.downloadTasks.enqueue(task)
            }
        }
    }

    func deleteFile(at url: URL, callback: @escaping (Bool) -> Void) {
        dataService.deleteFile(at: url, callback: callback)
    }

    func delete(object: String, callback: @escaping (Bool) -> Void) {
        dataService.delete(object, callback: callback)
    }
}
