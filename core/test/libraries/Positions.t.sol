// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import {Positions, zip} from "src/libraries/Positions.sol";

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

    function test_zip(int24 xl, int24 xu, int24 yl, int24 yu, int24 zl, int24 zu) public {
        uint256 zipped = zip([xl, xu, yl, yu, zl, zu]);

        unchecked {
            assertEq(int24(int256(zipped % (1 << 24))), xl);
            assertEq(int24(int256((zipped >> 24) % (1 << 24))), xu);
            assertEq(int24(int256((zipped >> 48) % (1 << 24))), yl);
            assertEq(int24(int256((zipped >> 72) % (1 << 24))), yu);
            assertEq(int24(int256((zipped >> 96) % (1 << 24))), zl);
            assertEq(int24(int256((zipped >> 120) % (1 << 24))), zu);
        }
    }

    function test_writeShouldSucceedWhenPositionsAreUnique(uint144 zipped) public {
        int24 xl = int24(int144(zipped % (1 << 24)));
        int24 xu = int24(int144((zipped >> 24) % (1 << 24)));
        int24 yl = int24(int144((zipped >> 48) % (1 << 24)));
        int24 yu = int24(int144((zipped >> 72) % (1 << 24)));
        int24 zl = int24(int144((zipped >> 96) % (1 << 24)));
        int24 zu = int24(int144((zipped >> 120) % (1 << 24)));

        vm.assume(xl != yl || xu != yu);
        vm.assume(yl != zl || yu != zu);
        vm.assume(zl != xl || zu != xu);

        positions.write(zipped);
        assertEq(positions[0], xl);
        assertEq(positions[1], xu);
        assertEq(positions[2], yl);
        assertEq(positions[3], yu);
        assertEq(positions[4], zl);
        assertEq(positions[5], zu);
    }

    function test_writePassthrough(uint144 zipped) public {
        int24 xl = int24(int144(zipped % (1 << 24)));
        int24 xu = int24(int144((zipped >> 24) % (1 << 24)));
        int24 yl = int24(int144((zipped >> 48) % (1 << 24)));
        int24 yu = int24(int144((zipped >> 72) % (1 << 24)));
        int24 zl = int24(int144((zipped >> 96) % (1 << 24)));
        int24 zu = int24(int144((zipped >> 120) % (1 << 24)));

        vm.assume(xl != yl || xu != yu);
        vm.assume(yl != zl || yu != zu);
        vm.assume(zl != xl || zu != xu);
        
        vm.assume(xl != xu);
        vm.assume(yl != yu);
        vm.assume(zl != zu);

        int24[] memory filtered = positions.write(zipped);
        assertEq(filtered.length, 6);
        assertEq(filtered[0], xl);
        assertEq(filtered[1], xu);
        assertEq(filtered[2], yl);
        assertEq(filtered[3], yu);
        assertEq(filtered[4], zl);
        assertEq(filtered[5], zu);
    }

    function test_singleWrite(int24 xl, int24 xu) public {
        int24[] memory filtered = positions.write(zip([xl, xu, 0, 0, 0, 0]));

        assertEq(positions[0], xl);
        assertEq(positions[1], xu);
        assertEq(positions[2], 0);
        assertEq(positions[3], 0);
        assertEq(positions[4], 0);
        assertEq(positions[5], 0);

        if (xl == xu) {
            assertEq(filtered.length, 0);
        } else {
            assertEq(filtered[0], xl);
            assertEq(filtered[1], xu);
        }
    }

    function test_doubleWrite(int24 xl, int24 xu, int24 yl, int24 yu) public {
        vm.assume(xl != yl || xu != yu);

        int24[] memory filtered = positions.write(zip([xl, xu, yl, yu, 0, 0]));

        assertEq(positions[0], xl);
        assertEq(positions[1], xu);
        assertEq(positions[2], yl);
        assertEq(positions[3], yu);
        assertEq(positions[4], 0);
        assertEq(positions[5], 0);

        if (xl == xu && yl == yu) {
            assertEq(filtered.length, 0);
        } else if (xl == xu) {
            assertEq(filtered[0], yl);
            assertEq(filtered[1], yu);
        } else if (yl == yu) {
            assertEq(filtered[0], xl);
            assertEq(filtered[1], xu);
        } else {
            assertEq(filtered[0], xl);
            assertEq(filtered[1], xu);
            assertEq(filtered[2], yl);
            assertEq(filtered[3], yu);
        }
    }

    function test_tripleWrite(int24 xl, int24 xu, int24 yl, int24 yu, int24 zl, int24 zu) public {
        vm.assume(xl != yl || xu != yu);
        vm.assume(yl != zl || yu != zu);
        vm.assume(zl != xl || zu != xu);

        positions.write(zip([xl, xu, yl, yu, zl, zu]));

        assertEq(positions[0], xl);
        assertEq(positions[1], xu);
        assertEq(positions[2], yl);
        assertEq(positions[3], yu);
        assertEq(positions[4], zl);
        assertEq(positions[5], zu);
    }

    function test_cannotWriteIdenticalXY(int24 xl, int24 xu) public {
        if (xl != xu) {
            vm.expectRevert(bytes(""));
            positions.write(zip([xl, xu, xl, xu, 0, 0]));
        } else {
            int24[] memory filtered = positions.write(zip([xl, xu, xl, xu, 0, 0]));
            assertEq(filtered.length, 0);
        }
    }

    function test_cannotWriteIdenticalYZ(int24 xl, int24 xu, int24 yl, int24 yu) public {
        vm.assume(yl != yu);
        vm.expectRevert(bytes(""));
        positions.write(zip([xl, xu, yl, yu, yl, yu]));
    }

    function test_cannotWriteIdenticalXZ(int24 xl, int24 xu, int24 yl, int24 yu) public {
        vm.assume(xl != xu);
        vm.expectRevert(bytes(""));
        positions.write(zip([xl, xu, yl, yu, xl, xu]));
    }

    function test_cannotWriteIdenticalXYZ(int24 xl, int24 xu) public {
        if (xl != xu) {
            vm.expectRevert(bytes(""));
            positions.write(zip([xl, xu, xl, xu, xl, xu]));
        } else {
            int24[] memory filtered = positions.write(zip([xl, xu, xl, xu, xl, xu]));
            assertEq(filtered.length, 0);
        }        
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

    function test_tripleWriteFilter(int24 xl, int24 xu, int24 yl, int24 yu, int24 zl, int24 zu) public {
        vm.assume(xl != yl || xu != yu);
        vm.assume(yl != zl || yu != zu);
        vm.assume(zl != xl || zu != xu);

        int24[] memory positions_ = positions.write(zip([xl, xu, yl, yu, zl, zu]));

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
