// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";

import {msb} from "src/libraries/Log2.sol";
import {square, mulDiv96, mulDiv128, mulDiv128Up, mulDiv224} from "src/libraries/MulDiv.sol";

contract MulDivTest is Test {
    function setUp() public {}

    function test_comparitive_square(uint160 a) public {
        assertEq(square(a), Math.mulDiv(a, a, 1 << 64));
    }

    function test_comparitive_mulDiv96(uint256 a, uint256 b) public {
        while (msb(a) + msb(b) >= 351) {
            a = a >> 1;
        }
        assertEq(mulDiv96(a, b), Math.mulDiv(a, b, 1 << 96));
    }

    function test_comparitive_mulDiv128(uint256 a, uint256 b) public {
        while (msb(a) + msb(b) >= 383) {
            a = a >> 1;
        }
        assertEq(mulDiv128(a, b), Math.mulDiv(a, b, 1 << 128));
    }

    function test_comparitive_mulDiv128Up(uint256 a, uint256 b) public {
        while (msb(a) + msb(b) >= 383) {
            a = a >> 1;
        }
        assertEq(mulDiv128Up(a, b), Math.mulDiv(a, b, 1 << 128, Math.Rounding.Up));
    }

    function test_comparitive_mulDiv224(uint256 a, uint256 b) public {
        while (msb(a) + msb(b) >= 479) {
            a = a >> 1;
        }
        assertEq(mulDiv224(a, b), Math.mulDiv(a, b, 1 << 224));
    }

    function test_comparitive_mulDiv(uint256 a, uint256 b, uint256 c) public {
        vm.assume(c != 0);
        while (msb(a) + msb(b) >= 255 + msb(c)) {
            a = a >> 1;
            b = b >> 1;
        }
        assertEq(Math.mulDiv(a, b, c), SoladyMath.fullMulDiv(a, b, c));
    }

    function test_gas_mulDivOpenZeppelin(uint256 a, uint256 b, uint256 c) public pure {
        vm.assume(c != 0);
        while (msb(a) + msb(b) >= 255 + msb(c)) {
            a = a >> 1;
            b = b >> 1;
        }
        Math.mulDiv(a, b, c);
    }

    function test_gas_mulDivSolady(uint256 a, uint256 b, uint256 c) public pure {
        vm.assume(c != 0);
        while (msb(a) + msb(b) >= 255 + msb(c)) {
            a = a >> 1;
            b = b >> 1;
        }
        SoladyMath.fullMulDiv(a, b, c);
    }
}
