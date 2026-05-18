// Board — 9×9 Sudoku grid model.
//
// 81-cell storage as [UInt8] where 0 = empty, 1–9 = digit.
// Encoded form uses '.' or '0' for empty, and '1'..'9' for digits.
//
// Pure value type. No Foundation imports beyond what `String` needs.

public struct Board: Sendable, Equatable, Hashable, Codable {

    public static let dimension: Int = 9
    public static let cellCount: Int = 81

    /// Flat row-major storage. Length always 81. Each element is 0 (empty) or 1...9.
    public private(set) var cells: [UInt8]

    /// Bitset of indices that were given (clue) at construction time.
    /// Stored as Bool[81] for simplicity and Codable friendliness.
    public private(set) var givenMask: [Bool]

    // MARK: - Init

    public init() {
        self.cells = Array(repeating: 0, count: Self.cellCount)
        self.givenMask = Array(repeating: false, count: Self.cellCount)
    }

    /// Initialize from an 81-character string. `.` or `0` denotes empty; `1`–`9` denotes a clue.
    /// Every non-empty cell is marked as a given.
    public init(clues encoded: String) throws {
        let chars = Array(encoded)
        guard chars.count == Self.cellCount else {
            throw BoardError.malformedLength(actual: chars.count)
        }
        var cells = [UInt8](repeating: 0, count: Self.cellCount)
        var givens = [Bool](repeating: false, count: Self.cellCount)
        for (index, char) in chars.enumerated() {
            switch char {
            case ".", "0":
                cells[index] = 0
            case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                let digit = UInt8(char.asciiValue! - Character("0").asciiValue!)
                cells[index] = digit
                givens[index] = true
            default:
                throw BoardError.malformedCharacter(index: index, character: char)
            }
        }
        self.cells = cells
        self.givenMask = givens
    }

    // MARK: - Encoding

    /// 81-char encoded form. Empty cells become `.`.
    public func encoded() -> String {
        var out = ""
        out.reserveCapacity(Self.cellCount)
        for value in cells {
            if value == 0 {
                out.append(".")
            } else {
                out.append(Character(UnicodeScalar(UInt8(Character("0").asciiValue!) + value)))
            }
        }
        return out
    }

    // MARK: - Cell access

    public static func index(row: Int, column: Int) -> Int {
        row * dimension + column
    }

    public func digit(atRow row: Int, column: Int) -> Int? {
        guard (0..<Self.dimension).contains(row), (0..<Self.dimension).contains(column) else {
            return nil
        }
        let value = cells[Self.index(row: row, column: column)]
        return value == 0 ? nil : Int(value)
    }

    public func digit(atIndex index: Int) -> Int? {
        guard (0..<Self.cellCount).contains(index) else { return nil }
        let value = cells[index]
        return value == 0 ? nil : Int(value)
    }

    public mutating func setDigit(_ digit: Int?, atRow row: Int, column: Int) throws {
        guard (0..<Self.dimension).contains(row), (0..<Self.dimension).contains(column) else {
            throw BoardError.outOfRange
        }
        try setDigit(digit, atIndex: Self.index(row: row, column: column))
    }

    public mutating func setDigit(_ digit: Int?, atIndex index: Int) throws {
        guard (0..<Self.cellCount).contains(index) else { throw BoardError.outOfRange }
        if let digit {
            guard (1...9).contains(digit) else { throw BoardError.outOfRange }
            cells[index] = UInt8(digit)
        } else {
            cells[index] = 0
        }
    }

    /// Indices of cells that were given at construction (clue cells).
    public func givens() -> [Int] {
        var result: [Int] = []
        for index in 0..<Self.cellCount where givenMask[index] {
            result.append(index)
        }
        return result
    }

    /// True if every cell is filled (1-9).
    public var isFullyFilled: Bool {
        !cells.contains(0)
    }

    // MARK: - Internal raw access (engine-private)

    /// Internal raw cell read by flat index. Module-internal callers (Solver,
    /// UniquenessValidator, CandidateGrid) operate on the flat storage directly.
    func cellRaw(at index: Int) -> UInt8 {
        cells[index]
    }

    /// Internal raw cell write — assumes caller has bounds-checked and
    /// validated the digit (0...9). Does not modify givenMask.
    mutating func setCellRaw(_ value: UInt8, at index: Int) {
        cells[index] = value
    }
}
