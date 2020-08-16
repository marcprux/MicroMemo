//
//  MemoZ
//  Memoize All The Things!
//
//  Marc Prud'hommeaux, 2020
//  MIT License
//

import Foundation

extension Hashable {
    /// Memoize the result of the execution of a predicate for the `Hashable` receiver.
    ///
    /// The source subject (the receiver) and the result object (the return value) should be value types, and the `predicate` must be a *pure* function that captures *no state*, in that:
    ///
    /// 1. Its return value is the same for the same arguments (no variation with local static variables, non-local variables, mutable reference arguments or input streams from I/O devices).
    /// 2. Its evaluation has no side effects (no mutation of local static variables, non-local variables, mutable reference arguments or I/O streams).
    ///
    /// - Note: The calling function's source file and line are used as the cache key, so care must be taken to avoid having multiple calls to `memoize` occur from a single line of source code.
    ///
    /// - Parameters:
    ///   - cache: the shared cache to use; `nil` disables caching and simply returns the result of `predicate` directly
    ///   - predicate: the key path; it may be called zero or more times, and it must be a pure function (no references to other state; always repeatable with the same arguments, no side-effects)
    ///
    /// - Throws: re-throws and errors from `predicate`
    /// - Returns: the result from the `predicate`, either a previously cached value, or the result of executing the `predicate`
    @available(OSX 10.12, iOS 12, *)
    @inlinable public func memoize<T>(with cache: MemoizationCache? = MemoizationCache.shared, _ keyPath: KeyPath<Self, T>) -> T {
        cache?.fetch(key: .init(subject: self, keyPath: keyPath)) { _ in
            self[keyPath: keyPath]
        } as? T ?? mismatched(self[keyPath: keyPath], active: cache != nil, keyPath: keyPath)
    }

    @usableFromInline func mismatched<T>(_ val: T, active: Bool, keyPath: KeyPath<Self, T>) -> T {
        if !active {
            print("MemoZ Warning: cache return value did not match expected type", T.self, "… this indicates a bug in MemoZ or NSCache")
        }
        return val
    }
}

public extension Hashable {
    /// `memoize`s the result of the subsequent path in a global cache.
    /// - Returns: the cached or uncached key path
    /// - Note: Should only be used with value types and functionally-pure key paths
    @available(OSX 10.12, iOS 12, *)
    @inlinable var memoz: Memoizer<Self> {
        Memoizer(value: self, cache: .shared)
    }

    /// `memoize`s the result of the subsequent path in the specified cache.
    /// - Parameter cache: the custom memoization cache to use; use .shared for the global cache, or `nil` to disable caching
    /// - Returns: the cached or uncached key path
    /// - Note: Should only be used with value types and functionally-pure key paths
    @available(OSX 10.12, iOS 12, *)
    @inlinable subscript(memoz cache: MemoizationCache?) -> Memoizer<Self> {
        Memoizer(value: self, cache: cache)
    }
}

public extension Hashable where Self : AnyObject {
    /// `memoize` should only be used on value types. It is permitted but discouraged.
    @available(*, deprecated, message: "memoize should not be used with reference types")
    @available(OSX 10.12, iOS 12, *)
    @inlinable var memoz: Memoizer<Self> {
        Memoizer(value: self, cache: .shared)
    }
}

/// A pass-through instance that memoizes the result of the given key path.
@available(OSX 10.12, iOS 12, *)
@dynamicMemberLookup public struct Memoizer<Value: Hashable> {
    @usableFromInline let value: Value
    @usableFromInline let cache: MemoizationCache?

    @usableFromInline init(value: Value, cache: MemoizationCache?) {
        self.value = value
        self.cache = cache
    }

    @available(OSX 10.12, iOS 12, *)
    @inlinable public subscript<T>(dynamicMember keyPath: KeyPath<Value, T>) -> T {
        value.memoize(with: cache, keyPath)
    }
}

extension Hashable where Self : AnyObject {
    /// Using `memoize` with reference types is technically possible, but is considered a mis-use of the framework.
    /// This warning can be bypassed by specifying the `cache` argument, in which case the method will use `Hashable.memoize`.
    @available(*, deprecated, message: "memoize should not be used with reference types")
    public func memoize<T>(_ keyPath: KeyPath<Self, T>) -> T {
        self[keyPath: keyPath]
    }
}

// MARK: MemoizationCache

/// A type-erased cache of memoization results, keyed on an arbitray `Hashable` and a key path.
/// - Seealso: https://stackoverflow.com/questions/37963327/what-is-a-good-alternative-for-static-stored-properties-of-generic-types-in-swif
@available(OSX 10.12, iOS 12, *)
public typealias MemoizationCache = Cache<MemoizationCacheKey, Any>

/// A key for memoization that uses a `Hashable` instance with a hashable `KeyPath` to form a cache key.
public struct MemoizationCacheKey : Hashable {
    /// The subject of the memoization call
    let subject: AnyHashable
    /// The key path for the call
    let keyPath: AnyKeyPath

    /// Internal-only key init – keys should be created only via `Hashable.memoize`
    @usableFromInline internal init(subject: AnyHashable, keyPath: AnyKeyPath) {
        self.subject = subject
        self.keyPath = keyPath
    }
}

@available(OSX 10.12, iOS 12, *)
public extension MemoizationCache {
    /// A single global cache of memoization results. The cache is thread-safe and backed by an `NSCache` for automatic memory management.
    /// - Seealso: `Hashable.memoize`
    static let shared = MemoizationCache()
}


// MARK: Cache

/// Wrapper around `NSCache` that allows keys/values to be value types and has an atomic `fetch` option.
@available(OSX 10.12, iOS 12, *)
public final class Cache<Key : Hashable, Value> {
    private typealias CacheType = NSCache<KeyRef<Key>, Ref<Value?>>

    /// We work with an internal cache because “Extension of a generic Objective-C class cannot access the class's generic parameters at runtime”
    private let cache = CacheType()

    // private let logger = LoggingDelegate()

    public init(name: String = "\(#file):\(#line)", countLimit: Int? = 0) {
        self.cache.name = name
        // self.cache.delegate = logger
        if let countLimit = countLimit {
            self.cache.countLimit = countLimit
        }
    }

    private class LoggingDelegate : NSObject, NSCacheDelegate {
        func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
            if let obj = obj as? Ref<Value> {
                print("evicting", obj.val, "from", Cache<Key, Value>.self)
            } else {
                print("evicting", obj, "from", Cache<Key, Value>.self)
            }
        }
    }

    public subscript(key: Key) -> Value? {
        get {
            cache.object(forKey: KeyRef(key))?.val
        }

        set {
            if let newValue = newValue {
                cache.setObject(Ref(.init(newValue)), forKey: KeyRef(key))
            } else {
                cache.removeObject(forKey: KeyRef(key))
            }
        }
    }

    /// Gets the instance from the cache, or `create`s it if is not present
    public func fetch(key: Key, create: (Key) throws -> (Value)) rethrows -> Value {
        let keyRef = KeyRef(key)
        if let value = cache.object(forKey: keyRef)?.val {
            return value
        } else {
            let value = try create(key)
            cache.setObject(Ref(value), forKey: keyRef)
            return value
        }
    }

    /// Empties the cache.
    public func clear() {
        cache.removeAllObjects()
    }

    /// The maximum total cost that the cache can hold before it starts evicting objects.
    /// If 0, there is no total cost limit. The default value is 0.
    /// When you add an object to the cache, you may pass in a specified cost for the object, such as the size in bytes of the object. If adding this object to the cache causes the cache’s total cost to rise above totalCostLimit, the cache may automatically evict objects until its total cost falls below totalCostLimit. The order in which the cache evicts objects is not guaranteed.
    /// - Note: This is not a strict limit, and if the cache goes over the limit, an object in the cache could be evicted instantly, at a later point in time, or possibly never, all depending on the implementation details of the cache.
    public var totalCostLimit: Int {
        get { cache.totalCostLimit }
        set { cache.totalCostLimit = newValue }
    }

    /// The maximum number of objects the cache should hold.
    /// If 0, there is no count limit. The default value is 0.
    /// - Note: This is not a strict limit—if the cache goes over the limit, an object in the cache could be evicted instantly, later, or possibly never, depending on the implementation details of the cache.
    public var countLimit: Int {
        get { cache.countLimit }
        set { cache.countLimit = newValue }
    }
}

/// A reference wrapper around another type; this will typically be used to provide reference semantics for value types
/// https://github.com/apple/swift/blob/master/docs/OptimizationTips.rst#advice-use-copy-on-write-semantics-for-large-values
final class Ref<T> {
    var val: T
    @inlinable init(_ val: T) { self.val = val }
}

/// A reference that can be used as a cache key for `NSCache` that wraps a value type.
/// Simply using a `Ref` as the cache key doesn't work (for unknown reasons).
@usableFromInline final class KeyRef<T: Hashable>: NSObject {
    @usableFromInline let val: T

    @usableFromInline init(_ val: T) {
        self.val = val
    }

    @inlinable override func isEqual(_ object: Any?) -> Bool {
        return (object as? KeyRef<T>)?.val == self.val
    }

    @inlinable static func ==(lhs: KeyRef, rhs: KeyRef) -> Bool {
        return lhs.val == rhs.val
    }

    @inlinable override var hash: Int {
        return self.val.hashValue
    }
}