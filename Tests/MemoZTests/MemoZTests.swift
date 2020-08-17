
import XCTest
import Dispatch
import MemoZ

extension Sequence where Element : Numeric {
    /// The sum of all the elements.
    /// - Complexity: O(N)
    var sum: Element { self.reduce(0, +) }
}

extension Sequence where Element : Numeric, Self : Hashable {
    /// The (memoized) sum of all the elements.
    /// - Complexity: Initial: O(N) MemoiZed: O(1)
    var sumZ: Element { self.memoz.sum }
}

// Measure the performance of non-memoized & memoized `sum`
class MemoZDemo: XCTestCase {
    /// A sequence of integers ranging from -1M through +1M
    let millions = (-1_000_000...1_000_000)

    func testCalculatedSum() {
        // average: 1.299, relative standard deviation: 0.509%, values: [1.312717, 1.296008, 1.306766, 1.298375, 1.299257, 1.303043, 1.296738, 1.294311, 1.288839, 1.293301]
        measure { XCTAssertEqual(millions.sum, 0) }
    }

    func testMemoizedSum() {
        // average: 0.133, relative standard deviation: 299.900%, values: [1.332549, 0.000051, 0.000018, 0.000032, 0.000110, 0.000021, 0.000016, 0.000015, 0.000014, 0.000123]
        measure { XCTAssertEqual(millions.sumZ, 0) }
    }

    override func tearDown() {
        super.tearDown()
        MemoizationCache.shared.clear() // clear out the global cache
    }
}

extension Sequence where Element : Numeric {
    /// The product of all the elements.
    /// - Complexity: O(N)
    var product: Element { reduce(1, *) }
}

extension MemoZDemo {
    /// A bunch of random numbers from the given offset
    func rangeLimts(count: Int = 20, offset: Int = 1_000_000) -> [Int] {
        (0..<count).map({ $0 + offset }).shuffled()
    }

    func testCalculatedSumParallel() {
        let ranges = rangeLimts()
        measure { // average: 7.115, relative standard deviation: 3.274%, values: [6.579956, 6.785192, 7.074619, 7.123436, 7.242951, 7.295850, 7.326060, 7.285277, 7.249500, 7.187203]
            DispatchQueue.concurrentPerform(iterations: ranges.count) { i in
                XCTAssertEqual((-ranges[i]...ranges[i]).sum, 0)
            }
        }
    }

    func testMemoziedSumParallel() {
        let ranges = rangeLimts()
        measure { // average: 0.671, relative standard deviation: 299.856%, values: [6.708572, 0.000535, 0.000298, 0.000287, 0.000380, 0.000400, 0.000337, 0.000251, 0.000225, 0.000183]
            DispatchQueue.concurrentPerform(iterations: ranges.count) { i in
                XCTAssertEqual((-ranges[i]...ranges[i]).sumZ, 0)
            }
        }
    }
}

extension BinaryInteger where Self.Stride : SignedInteger {
    var isEven: Bool { self % 2 == 0 }
    var squareRoot: Double { sqrt(Double(self)) }
    func isMultiple(of i: Self) -> Bool { self % i == 0 }

    var isPrime: Bool {
        self <= 1 ? false : self == 2 ? true
            : (3...Self(self.squareRoot)).first(where: isMultiple(of:)) == .none
    }
}

extension String {
    /// Returns this string with a random UUID at the end
    var withRandomUUIDSuffix: String { self + UUID().uuidString }
}

final class MemoZTests: XCTestCase {
    /// This is an example of mis-use of the cache by caching a non-referrentially-transparent keypath function
    func testMisuse() {
        XCTAssertNotEqual("".withRandomUUIDSuffix, "".withRandomUUIDSuffix)
        XCTAssertEqual("".memoz.withRandomUUIDSuffix, "".memoz.withRandomUUIDSuffix) // two random IDs are the same!

        XCTAssertNotEqual("".memoz.withRandomUUIDSuffix, "xyz".memoz.withRandomUUIDSuffix)
        XCTAssertEqual("xyz".memoz.withRandomUUIDSuffix, "xyz".memoz.withRandomUUIDSuffix)
    }

    func testCacheCountLimit() {
        // mis-use the cache to show that the count limit will purge older references
        let cache = MemoizationCache(countLimit: 10)
        let randid = ""[memoz: cache].withRandomUUIDSuffix
        XCTAssertEqual(randid, ""[memoz: cache].withRandomUUIDSuffix)

        for i in 1...1000 {
            let _ = "\(i)"[memoz: cache].withRandomUUIDSuffix
        }

        XCTAssertNotEqual(randid, ""[memoz: cache].withRandomUUIDSuffix, "cache should have been purged")
    }

    func testSum() {
        XCTAssertEqual(15, (1...5).sum)
        XCTAssertEqual(15, (1...5).memoz.sum)
        XCTAssertEqual(120, (1...5).product)
        XCTAssertEqual(120, (1...5).memoz.product)
        XCTAssertEqual(true, 87178291199.isPrime)

        XCTAssertEqual(false, UInt64(3314192745739 - 1).isPrime)
        XCTAssertEqual(true, UInt64(3314192745739).isPrime)
        XCTAssertEqual(false, UInt64(3314192745739 + 1).isPrime)

        //XCTAssertEqual(true, UInt64(3331113965338635107).isPrime) // 1,133 seconds!
        XCTAssertEqual(false, 1002.isPrime)

        XCTAssertEqual(false, 1002.memoz.isPrime)
    }

    let millions = (-1_000_000)...(+1_000_000)

    func testSumCached() {
        measure { // average: 0.129, relative standard deviation: 299.957%
            XCTAssertEqual(0, millions.memoz.sum)
        }
    }

    func testSumUncached() {
        measure { // average: 1.288, relative standard deviation: 1.363%
            XCTAssertEqual(0, millions.sum)
        }
    }

    struct Pointless : Hashable {
        var alwaysOne: Int { 1 }
        var alwaysOneZ: Int { memoz.alwaysOne }
    }

    func testPointlessComputation() {
        let pointless = Pointless()
        measure { // average: 0.002, relative standard deviation: 20.745%, values: [0.002702, 0.001852, 0.001622, 0.001521, 0.001567, 0.001608, 0.002050, 0.001541, 0.001496, 0.001484]
            for _ in 1...1_000 {
                XCTAssertEqual(1, pointless.alwaysOne)
            }
        }
    }

    func testPointlessMemoization() {
        let pointless = Pointless()
        measure { // average: 0.005, relative standard deviation: 21.496%, values: [0.007675, 0.004570, 0.004279, 0.004338, 0.004126, 0.004233, 0.004466, 0.004147, 0.004400, 0.004680]
            for _ in 1...1_000 {
                XCTAssertEqual(1, pointless.alwaysOneZ)
            }
        }
    }


    func testValueTypes() {
        let str = "xyz" as NSString
        XCTAssertEqual(3, (str as String).memoz.count)
        XCTAssertEqual("Xyz", (str as NSString).memoz.capitalized) // we should get a deprecation warning here
    }

    func testLocalCalculation() {
        /// Sum all the numbers from from to to
        /// - Complexity: initial: O(to-from) memoized: O(1)
        func summit(from: Int, to: Int) -> Int {
            /// Sum all the numbers from from to to
            /// - Complexity: O(to-from)
            func sumSequence(from: Int, to: Int) -> Int {
                (from...to).reduce(0, +)
            }

            /// Wrap the arguments to `sumSequence`
            struct Summer : Hashable {
                let from: Int
                let to: Int
                var sum: Int {
                    sumSequence(from: from, to: to)
                }
            }

            return Summer(from: from, to: to).memoz.sum
        }

        measure { // average: 0.064, relative standard deviation: 299.894%, values: [0.641700, 0.000073, 0.000020, 0.000015, 0.000014, 0.000028, 0.000015, 0.000013, 0.000013, 0.000013]
            XCTAssertEqual(1500001500000, summit(from: 1_000_000, to: 2_000_000))
        }
    }

    func testCachePartition() {
        let uuids = (0...100_000).map({ _ in UUID() })
        measure {
            // the following two calls are the same, except the second one uses a partitioned cache
            XCTAssertEqual(3800038, uuids.memoz.description.count)
            XCTAssertEqual(3800038, uuids.memoize(with: .domainCache, \.description).count)
            XCTAssertEqual(3800038, uuids[memoz: .domainCache].description.count)
        }
    }

    #if !os(Linux)
    func testJSONFormatted() {
        do {
            let data = try ["x": "A", "y": "B", "z": "C"][JSONFormatted: false, sorted: true].get()
            XCTAssertEqual(String(data: data, encoding: .utf8), "{\"x\":\"A\",\"y\":\"B\",\"z\":\"C\"}")

            let _ = try ["x": "A", "y": "B", "z": "C"].memoz[JSONFormatted: false, sorted: nil].get()
        } catch {
            XCTFail("\(error)")
        }
    }
    #endif

    #if !os(Linux)
    func testCacheThreading() {
        // make a big map with some duplicated UUIDs
        var uuids = (1...10).map({ _ in [[UUID()]] })
        for _ in 1...12 {
            uuids += uuids
        }
        uuids.shuffle()

        XCTAssertEqual(40960, uuids.count)
        print("checking cache for \(uuids.count) random UUIDs")

        func checkUUID(at index: Int) {
            let pretty = Bool.random()
            let str1 = uuids[index].memoz[JSONFormatted: pretty]
            let str2 = uuids[index].memoz[JSONFormatted: !pretty, sorted: true]
            // make sure the two memoz were keyed on different parameters
            XCTAssertNotEqual(try str1.get(), try str2.get())
        }

        measure {
            DispatchQueue.concurrentPerform(iterations: uuids.count, execute: checkUUID)
        }
    }
    #endif

    func testErrorHandling() {
        XCTAssertThrowsError(try Array<Bool>().memoz.firstAndLast.get())
    }
}

extension MemoizationCache {
    /// A domain-specific cache
    static let domainCache = MemoizationCache()
}

#if !os(Linux)
extension Encodable {
    /// A JSON blob with the given parameters.
    ///
    /// For example:
    /// ```["x": "A", "y": "B", "z": "C"][JSONFormatted: false, sorted: true]```
    ///
    /// will return the result with data:
    ///
    /// ```{"x":"A","y":"B","z":"C"}```
    subscript(JSONFormatted pretty: Bool, sorted sorted: Bool? = nil, noslash noslash: Bool = true) -> Result<Data, Error> {
        Result {
            let encoder = JSONEncoder()
            var fmt = JSONEncoder.OutputFormatting()
            if pretty { fmt.insert(.prettyPrinted) }
            if sorted ?? pretty { fmt.insert(.sortedKeys) }
            if noslash { fmt.insert(.withoutEscapingSlashes) }
            encoder.outputFormatting = fmt
            return try encoder.encode(self)
        }
    }
}
#endif

extension BidirectionalCollection {
    /// Returns the first and last element of this collection, or else an error if the collection is empty
    var firstAndLast: Result<(Element, Element), Error> {
        Result {
            guard let first = first else {
                throw CocoaError(.coderValueNotFound)
            }
            return (first, last ?? first)
        }
    }
}


extension Sequence {
    /// Sorts the collection by the the given `keyPath` of the element
    subscript<T: Comparable>(sorting sortPath: KeyPath<Element, T>) -> [Element] {
        return self.sorted(by: {
            $0[keyPath: sortPath] < $1[keyPath: sortPath]
        })
    }
}

extension Array where Element: Collection & Hashable {
    /// "C", "BB", "AAA"
    var sortedByCountZ: [Element] {
        self.memoz[sorting: \.count]
    }
}

extension Array where Element: Comparable & Hashable {
    /// "AAA", "BB", "C"
    var sortedBySelfZ: [Element] {
        self.memoz[sorting: \.self]
    }
}

extension MemoZTests {
    func testMemoKeyedSubscript() {
        let strs = ["AAA", "C", "BB"]
        XCTAssertEqual(strs.sortedBySelfZ, ["AAA", "BB", "C"])
        XCTAssertEqual(strs.sortedByCountZ, ["C", "BB", "AAA"])
    }
}

