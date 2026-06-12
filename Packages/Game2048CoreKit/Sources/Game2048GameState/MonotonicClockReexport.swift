// Re-export TimeKit (MonotonicClock / LiveMonotonicClock) from Game2048GameState
// so `import Game2048GameState` call sites reach the clock without an extra
// import. Mirrors MinesweeperGameState's MonotonicClockReexport.swift.

@_exported public import TimeKit
