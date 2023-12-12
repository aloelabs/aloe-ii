// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";

import {square, mulDiv96, mulDiv128, mulDiv128Up, mulDiv224} from "src/libraries/MulDiv.sol";

function msb(uint256 x) pure returns (uint256 r) {
    /// @solidity memory-safe-assembly
    assembly {
        r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
        r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
        r := or(r, shl(5, lt(0xffffffff, shr(r, x))))

        // For the remaining 32 bits, use a De Bruijn lookup.
        // See: https://graphics.stanford.edu/~seander/bithacks.html
        x := shr(r, x)
        x := or(x, shr(1, x))
        x := or(x, shr(2, x))
        x := or(x, shr(4, x))
        x := or(x, shr(8, x))
        x := or(x, shr(16, x))

        // forgefmt: disable-next-item
        r := or(
            r,
            byte(
                shr(251, mul(x, shl(224, 0x07c4acdd))),
                0x0009010a0d15021d0b0e10121619031e080c141c0f111807131b17061a05041f
            )
        )
    }
}

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
