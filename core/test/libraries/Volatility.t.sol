// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import {TickMath} from "src/libraries/TickMath.sol";
import {Volatility} from "src/libraries/Volatility.sol";

contract VolatilityTest is Test {
    function setUp() public {}

    function test_spec_estimate() public {
        Volatility.PoolMetadata memory metadata = Volatility.PoolMetadata(3000, 3000, 60);
        uint160 sqrtMeanPriceX96 = TickMath.getSqrtRatioAtTick(193730);
        uint256 dailyIV = Volatility.estimate(
            metadata,
            sqrtMeanPriceX96,
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                0
            ),
            Volatility.FeeGrowthGlobals(
                1501968291161650295867029090958139,
                527315901327546020416261134123578344760082,
                8640
            ),
            1 days
        );
        assertEq(dailyIV, 17276173878);

        dailyIV = Volatility.estimate(
            metadata,
            sqrtMeanPriceX96,
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                0
            ),
            Volatility.FeeGrowthGlobals(
                1501968291161650295867029090958139,
                527315901327546020416261134123578344760082,
                8640
            ),
            1 hours
        );
        assertEq(dailyIV, 3526484226);

        dailyIV = Volatility.estimate(
            metadata,
            sqrtMeanPriceX96,
            Volatility.FeeGrowthGlobals(0, 0, 0),
            Volatility.FeeGrowthGlobals(
                1501968291161650295867029090958139,
                527315901327546020416261134123578344760082,
                uint32(1660599905)
            ),
            1 days
        );
        assertEq(dailyIV, 5901190938);

        dailyIV = Volatility.estimate(
            metadata,
            sqrtMeanPriceX96,
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                0
            ),
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                8640
            ),
            1 days
        );
        assertEq(dailyIV, 0);

        dailyIV = Volatility.estimate(
            metadata,
            sqrtMeanPriceX96,
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                0
            ),
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                uint32(1660599905)
            ),
            1 days
        );
        assertEq(dailyIV, 0);
    }

    function test_fuzz_estimateDoesNotRevertA(
        int16 tick,
        int8 tickMeanOffset,
        uint192 a,
        uint192 b,
        uint48 c,
        uint48 d
    ) public pure {
        Volatility.PoolMetadata memory metadata = Volatility.PoolMetadata(3000, 3000, 60);
        Volatility.estimate(
            metadata,
            TickMath.getSqrtRatioAtTick(tick + int24(tickMeanOffset)),
            Volatility.FeeGrowthGlobals(a, b, 0),
            Volatility.FeeGrowthGlobals(uint256(a) + uint256(c), uint256(b) + uint256(d), 7777),
            1 days
        );
    }

    function test_fuzz_estimateDoesNotRevertB(
        uint32 feeGrowthSampleAge,
        uint256 feeGrowthGlobalA0X128,
        uint256 feeGrowthGlobalA1X128,
        uint96 feeGrowthGlobalDelta0X128,
        uint128 feeGrowthGlobalDelta1X128,
        uint48 gammas,
        int24 arithmeticMeanTick,
        uint32 scale
    ) public {
        scale = uint32(bound(scale, 1 minutes, 2 days));

        Volatility.PoolMetadata memory metadata = Volatility.PoolMetadata(
            uint24(gammas % (1 << 24)),
            uint24(gammas >> 24),
            0
        );
        {
            // reusing randomness to avoid stack-too-deep
            uint256 tier = feeGrowthSampleAge % 4;
            if (tier == 0) metadata.tickSpacing = 1;
            else if (tier == 1) metadata.tickSpacing = 10;
            else if (tier == 2) metadata.tickSpacing = 60;
            else if (tier == 3) metadata.tickSpacing = 100;
        }

        arithmeticMeanTick = _boundTick(arithmeticMeanTick, metadata.tickSpacing);

        Volatility.FeeGrowthGlobals memory a;
        Volatility.FeeGrowthGlobals memory b;
        unchecked {
            a.feeGrowthGlobal0X128 = feeGrowthGlobalA0X128;
            a.feeGrowthGlobal1X128 = feeGrowthGlobalA1X128;
            a.timestamp = 0;
            b.feeGrowthGlobal0X128 = feeGrowthGlobalA0X128 + feeGrowthGlobalDelta0X128;
            b.feeGrowthGlobal1X128 = feeGrowthGlobalA1X128 + feeGrowthGlobalDelta1X128;
            b.timestamp = feeGrowthSampleAge;
        }

        assertLt(Volatility.estimate(metadata, TickMath.getSqrtRatioAtTick(arithmeticMeanTick), a, b, scale), 1 << 128);
    }

    function _boundTick(int24 tick, int24 tickSpacing) private pure returns (int24) {
        if (tick < TickMath.MIN_TICK + tickSpacing) return TickMath.MIN_TICK + tickSpacing;
        else if (tick > TickMath.MAX_TICK - tickSpacing) return TickMath.MAX_TICK - tickSpacing;
        else return tick;
    }
}
