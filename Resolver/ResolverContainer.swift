//
//  ResolverContainer.swift
//  Resolver
//
//  Created by Natan Zalkin on 26/07/2019.
//  Copyright © 2019 Natan Zalkin. All rights reserved.
//

/*
* Copyright (c) 2019 Natan Zalkin
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*
*/

import Dispatch

/// Thread safe container allowing to register and extract resolvers
open class ResolverContainer {

    public enum Error: Swift.Error, Equatable {
        case unregisteredType(String)
        case typeMismatch(expected: String)
    }

    var entries: [ObjectIdentifier: () -> Any]
    var syncQueue: DispatchQueue

    /// Initializes the container.
    /// - Parameter qos: The quality of service of the underlying queue used to sync the container changes when accessed from multiple threads.
    /// - Parameter registration: The closure allowing to pre-configure the container upon initialization.
    public init(qos: DispatchQoS = .userInteractive, registration: ((ResolverRegistering) -> Void)? = nil) {
        entries = [:]
        syncQueue = DispatchQueue(label: "ResolverContainer.SyncQueue", qos: qos)

        defer {
            registration?(self)
        }
    }

    /// Merges entries from another container.
    /// - Parameter container: The source container to merge entries from.
    /// - Parameter preservingRegisteredResolvers: When set to true,
    /// any resolvers from another container registered under the same type will be ignored.
    /// If set to false, existing resolvers registered under the same type will be replaced with
    /// the resolvers from another container.
    public func merge(with container: ResolverContainer, preservingRegisteredResolvers: Bool = false) {
        entries.merge(container.entries) { (current, new) in
            return preservingRegisteredResolvers ? current : new
        }
    }
}

extension ResolverContainer: ResolverRegistering {

    public func register<T>(resolver: @escaping () -> T) {
        syncQueue.sync { entries[ObjectIdentifier(T.self)] = resolver }
    }

    @discardableResult
    public func unregister<T>(_ type: T.Type = T.self) -> T? {
        return syncQueue.sync {
            if let resolve = entries.removeValue(forKey: ObjectIdentifier(T.self)) {
                return resolve() as? T
            }

            return nil
        }
    }

    public func unregisterAll() {
        syncQueue.sync { entries.removeAll() }
    }
}

extension ResolverContainer: AnyResolving {

    public func resolve<T>(_ type: T.Type) throws -> T {

        guard let resolver = syncQueue.sync(execute: { entries[ObjectIdentifier(T.self)] }) else {
            throw Error.unregisteredType(String(describing: T.self))
        }

        guard let entry = resolver() as? T else {
            throw Error.typeMismatch(expected: String(describing: T.self))
        }

        return entry
    }
}
