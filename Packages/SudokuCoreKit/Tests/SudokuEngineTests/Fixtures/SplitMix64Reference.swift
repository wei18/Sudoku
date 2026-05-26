// Frozen reference vectors for SplitMix64 — migrated from Phase 0 scratch
// `scratch/SplitMix64Probe`. Source: meetings/2026-05-17_phase0-gates.md §0.1.
// These values are byte-identical on macOS arm64 and iPhone 16 Pro simulator arm64.

enum SplitMix64Reference {

    /// First 16 outputs for seed = 0x0.
    static let seedZero: [UInt64] = [
        0xE220_A839_7B1D_CDAF,
        0x6E78_9E6A_A1B9_65F4,
        0x06C4_5D18_8009_454F,
        0xF88B_B8A8_724C_81EC,
        0x1B39_896A_51A8_749B,
        0x53CB_9F0C_747E_A2EA,
        0x2C82_9ABE_1F45_32E1,
        0xC584_133A_C916_AB3C,
        0x3EE5_7890_41C9_8AC3,
        0xF3B8_488C_368C_B0A6,
        0x657E_ECDD_3CB1_3D09,
        0xC2D3_26E0_055B_DEF6,
        0x8621_A03F_E0BB_DB7B,
        0x8E1F_7555_983A_A92F,
        0xB54E_0F16_00CC_4D19,
        0x84BB_3F97_971D_80AB
    ]

    /// First 16 outputs for seed = 0x2A (= 42).
    static let seedFortyTwo: [UInt64] = [
        0xBDD7_3226_2FEB_6E95,
        0x28EF_E333_B266_F103,
        0x4752_6757_130F_9F52,
        0x581C_E1FF_0E4A_E394,
        0x09BC_585A_2448_23F2,
        0xDE44_31FA_3C80_DB06,
        0x37E9_671C_4537_6D5D,
        0xCCF6_35EE_9E9E_2FA4,
        0x5705_B877_0B3D_7DD5,
        0x9E54_D738_297F_77AE,
        0x3474_724A_775B_19BF,
        0x7E34_8A0E_4516_50BE,
        0x836D_ED89_7F3E_46E6,
        0x851F_9773_47ED_6DB7,
        0xAA47_E31C_02E7_8EDC,
        0x3414_52C5_4D7C_33F2
    ]
}
