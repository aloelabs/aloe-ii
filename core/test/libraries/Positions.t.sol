// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import {Positions} from "src/libraries/Positions.sol";

contract PositionsTest is Test {
    using Positions for int24[6];

    int24[6] public positions;

    function setUp() public {
        positions[0] = 123;
        positions[1] = 456;
        positions[2] = 789;
        positions[3] = 12;
        positions[4] = 345;
        positions[5] = 678;
    }

    function test_singleWrite(int24 xl, int24 xu) public {
        int24[] memory positions_ = new int24[](2);
        positions_[0] = xl;
        positions_[1] = xu;
        positions.write(positions_);

        assertEq(positions[0], xl);
        assertEq(positions[1], xu);
        assertEq(positions[2], 0);
        assertEq(positions[3], 0);
        assertEq(positions[4], 0);
        assertEq(positions[5], 0);
    }

    function test_doubleWrite(int24 xl, int24 xu, int24 yl, int24 yu) public {
        vm.assume(xl != yl || xu != yu);

        int24[] memory positions_ = new int24[](4);
        positions_[0] = xl;
        positions_[1] = xu;
        positions_[2] = yl;
        positions_[3] = yu;
        positions.write(positions_);

        assertEq(positions[0], xl);
        assertEq(positions[1], xu);
        assertEq(positions[2], yl);
        assertEq(positions[3], yu);
        assertEq(positions[4], 0);
        assertEq(positions[5], 0);
    }

    function test_tripleWrite(int24 xl, int24 xu, int24 yl, int24 yu, int24 zl, int24 zu) public {
        vm.assume(xl != yl || xu != yu);
        vm.assume(xl != zl || xu != zu);
        vm.assume(yl != zl || yu != zu);

        int24[] memory positions_ = new int24[](6);
        positions_[0] = xl;
        positions_[1] = xu;
        positions_[2] = yl;
        positions_[3] = yu;
        positions_[4] = zl;
        positions_[5] = zu;
        positions.write(positions_);

        assertEq(positions[0], xl);
        assertEq(positions[1], xu);
        assertEq(positions[2], yl);
        assertEq(positions[3], yu);
        assertEq(positions[4], zl);
        assertEq(positions[5], zu);
    }

    function test_cannotWriteIdenticalXY(int24 xl, int24 xu) public {
        int24[] memory positions_ = new int24[](4);
        positions_[0] = xl;
        positions_[1] = xu;
        positions_[2] = xl;
        positions_[3] = xu;

        vm.expectRevert(bytes(""));
        positions.write(positions_);
    }

    function test_cannotWriteIdenticalYZ(int24 xl, int24 xu, int24 yl, int24 yu) public {
        int24[] memory positions_ = new int24[](6);
        positions_[0] = xl;
        positions_[1] = xu;
        positions_[2] = yl;
        positions_[3] = yu;
        positions_[4] = yl;
        positions_[5] = yu;

        vm.expectRevert(bytes(""));
        positions.write(positions_);
    }

    function test_cannotWriteIdenticalXZ(int24 xl, int24 xu, int24 yl, int24 yu) public {
        int24[] memory positions_ = new int24[](6);
        positions_[0] = xl;
        positions_[1] = xu;
        positions_[2] = yl;
        positions_[3] = yu;
        positions_[4] = xl;
        positions_[5] = xu;

        vm.expectRevert(bytes(""));
        positions.write(positions_);
    }

    function test_singleRead(int24 xl, int24 xu) public {
        positions[0] = xl;
        positions[1] = xu;
        positions[2] = 0;
        positions[3] = 0;
        positions[4] = 0;
        positions[5] = 0;

        int24[] memory positions_ = positions.read();

        if (xl == xu) {
            assertEq(positions_.length, 0);
        } else {
            assertEq(positions_.length, 2);
            assertEq(positions_[0], xl);
            assertEq(positions_[1], xu);
        }
    }

    function test_doubleRead(int24 xl, int24 xu, int24 yl, int24 yu) public {
        positions[0] = xl;
        positions[1] = xu;
        positions[2] = yl;
        positions[3] = yu;
        positions[4] = 0;
        positions[5] = 0;

        int24[] memory positions_ = positions.read();

        if (xl == xu && yl == yu) {
            assertEq(positions_.length, 0);
        } else if (xl == xu) {
            assertEq(positions_.length, 2);
            assertEq(positions_[0], yl);
            assertEq(positions_[1], yu);
        } else if (yl == yu) {
            assertEq(positions_.length, 2);
            assertEq(positions_[0], xl);
            assertEq(positions_[1], xu);
        } else {
            assertEq(positions_.length, 4);
            assertEq(positions_[0], xl);
            assertEq(positions_[1], xu);
            assertEq(positions_[2], yl);
            assertEq(positions_[3], yu);
        }
    }

    function test_tripleRead(int24 xl, int24 xu, int24 yl, int24 yu, int24 zl, int24 zu) public {
        positions[0] = xl;
        positions[1] = xu;
        positions[2] = yl;
        positions[3] = yu;
        positions[4] = zl;
        positions[5] = zu;

        int24[] memory positions_ = positions.read();

        if (xl == xu && yl == yu && zl == zu) {
            assertEq(positions_.length, 0);
            return;
        }

        if (xl != xu && yl == yu && zl == zu) {
            assertEq(positions_.length, 2);
            assertEq(positions_[0], xl);
            assertEq(positions_[1], xu);
            return;
        }

        if (xl == xu && yl != yu && zl == zu) {
            assertEq(positions_.length, 2);
            assertEq(positions_[0], yl);
            assertEq(positions_[1], yu);
            return;
        }

        if (xl == xu && yl == yu && zl != zu) {
            assertEq(positions_.length, 2);
            assertEq(positions_[0], zl);
            assertEq(positions_[1], zu);
            return;
        }

        if (xl != xu && yl != yu && zl == zu) {
            assertEq(positions_.length, 4);
            assertEq(positions_[0], xl);
            assertEq(positions_[1], xu);
            assertEq(positions_[2], yl);
            assertEq(positions_[3], yu);
            return;
        }

        if (xl == xu && yl != yu && zl != zu) {
            assertEq(positions_.length, 4);
            assertEq(positions_[0], yl);
            assertEq(positions_[1], yu);
            assertEq(positions_[2], zl);
            assertEq(positions_[3], zu);
            return;
        }

        if (xl != xu && yl == yu && zl != zu) {
            assertEq(positions_.length, 4);
            assertEq(positions_[0], xl);
            assertEq(positions_[1], xu);
            assertEq(positions_[2], zl);
            assertEq(positions_[3], zu);
            return;
        }

        assertEq(positions_.length, 6);
        assertEq(positions_[0], xl);
        assertEq(positions_[1], xu);
        assertEq(positions_[2], yl);
        assertEq(positions_[3], yu);
        assertEq(positions_[4], zl);
        assertEq(positions_[5], zu);
    }
}
