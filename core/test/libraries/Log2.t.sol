// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "src/libraries/Log2.sol";

contract Log2Test is Test {
    function setUp() public {}

    function test_spec_msb() public {
        assertEq(msb(0), 0);
        assertEq(msb(1), 0);
        assertEq(msb(2), 1);
        assertEq(msb(3), 1);
        assertEq(msb(4), 2);

        assertEq(msb(type(uint8).max), 7);
        assertEq(msb(1 << 8), 8);
        assertEq(msb(type(uint16).max), 15);
        assertEq(msb(1 << 16), 16);
        assertEq(msb(type(uint64).max), 63);
        assertEq(msb(1 << 64), 64);
        assertEq(msb(type(uint128).max), 127);
        assertEq(msb(1 << 128), 128);
        assertEq(msb(type(uint248).max), 247);
        assertEq(msb(1 << 248), 248);
        assertEq(msb(type(uint256).max), 255);
    }

    /// forge-config: default.fuzz.runs = 16384
    function test_comparitive_msb(uint256 x) public {
        assertEq(msb(x), msbSimple(x));
    }

    function test_log2_gas(uint256 x) public pure {
        log2(x);
    }

    function test_log2_domain() public {
        assertEq(log2(0), -131072); // WARNING: Not intended to be used like this
        assertEq(log2(1), -131072);
        assertEq(log2(type(uint256).max), 131071);
    }

    function test_log2_range(uint256 x) public {
        vm.assume(x > 0);

        int256 y = log2(x);
        assertGe(y, -128 << 10);
        assertLt(y, 128 << 10);
    }

    function test_log2_match(uint256 x) public {
        vm.assume(x > 0);
        assertEq(log2(x), log2(x, 10) >> 54);
    }

    function test_log2_compression(uint256 x) public {
        int256 y = log2(x);
        int24 compressed = int24(y);
        assertEq(compressed, y);
    }

    function test_exp2_gas(int72 x) public pure {
        exp2(x);
    }

    function test_exp2_domain() public {
        assertEq(exp2(-131072), 1);
        assertEq(exp2(0), 1 << 128);
        assertEq(exp2(131071), 115713735915118693734171220742359026900664100053272090015110578992986330234880);
        assertEq(exp2(131072), 0);
    }

    function test_log2OfExp2(int24 x) public {
        x = int24(bound(x, -131072, 131071));
        // Recovery isn't very precise in this direction!
        assertApproxEqAbs(log2(exp2(x)), x, 1024);
    }

    function test_recoveryPrecision(uint256 x) public {
        vm.assume(x > 0);
        x = bound(x, 1e4, type(uint256).max);

        int256 y = log2(x);
        emit log_named_int("log", y);

        uint256 recovered = exp2(y);
        emit log_named_uint("rec", recovered);

        assertApproxEqRel(recovered, x, 0.001e18);
        assertLe(recovered, x);
    }

    function test_recoveryPrecisionUp(uint256 x) public {
        vm.assume(x > 0);
        x = bound(x, 1e4, 115713735915118693734171220742359026900664100053272090015110578992986330234880);

        int256 y = log2Up(x);
        emit log_named_int("log", y);

        uint256 recovered = exp2(y);
        emit log_named_uint("rec", recovered);

        assertApproxEqRel(recovered, x, 0.001e18);
        assertGe(recovered, x - 2);
        assertGe(recovered / 1e4, x / 1e4);
    }

    function test_rewardsStyleUsage(uint56 rate, uint112 totalSupply) public {
        vm.assume(totalSupply > 0);

        int24 log2TotalSupply;
        unchecked {
            int256 y = log2Up(totalSupply);
            log2TotalSupply = int24(y);
        }
        uint256 recoveredTotalSupply = exp2(log2TotalSupply);

        uint256 a = (1e16 * uint256(rate)) / recoveredTotalSupply;
        uint256 b = (1e16 * uint256(rate)) / totalSupply;

        assertLe(a, b);
        if (a > 1e3) assertApproxEqRel(a, b, 0.002e18);
        else assertApproxEqAbs(a, b, 1);
    }

    function assertApproxEqRel(
        uint256 a,
        uint256 b,
        uint256 maxPercentDelta // An 18 decimal fixed point number, where 1e18 == 100%
    ) internal override {
        if (b == 0) return assertEq(a, b); // If the expected is 0, actual must be too.

        uint256 percentDelta = _percentDelta(a, b);

        if (percentDelta > maxPercentDelta) {
            emit log("Error: a ~= b not satisfied [uint]");
            emit log_named_uint("    Expected", b);
            emit log_named_uint("      Actual", a);
            emit log_named_decimal_uint(" Max % Delta", maxPercentDelta, 18);
            emit log_named_decimal_uint("     % Delta", percentDelta, 18);
            fail();
        }
    }

    function _percentDelta(uint256 a, uint256 b) private pure returns (uint256) {
        uint256 absDelta = stdMath.delta(a, b);

        return Math.mulDiv(absDelta, 1e18, b, Math.Rounding.Up);
    }
}

function msbSimple(uint256 x) pure returns (uint256 y) {
    assembly ("memory-safe") {
        y := shl(7, lt(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, x))
        y := or(y, shl(6, lt(0xFFFFFFFFFFFFFFFF, shr(y, x))))
        y := or(y, shl(5, lt(0xFFFFFFFF, shr(y, x))))
        y := or(y, shl(4, lt(0xFFFF, shr(y, x))))
        y := or(y, shl(3, lt(0xFF, shr(y, x))))
        y := or(y, shl(2, lt(0xF, shr(y, x))))
        y := or(y, shl(1, lt(0x3, shr(y, x))))
        y := or(y, lt(0x1, shr(y, x)))
    }
}
