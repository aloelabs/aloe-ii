// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity 0.8.17;

// import "forge-std/Test.sol";

// import {Positions, extract, zip} from "src/libraries/Positions.sol";

// contract PositionsTest is Test {
//     using Positions for int24[6];

//     int24[6] public positions;

//     function setUp() public {
//         positions[0] = 123;
//         positions[1] = 456;
//         positions[2] = 789;
//         positions[3] = 12;
//         positions[4] = 345;
//         positions[5] = 678;
//     }

//     function test_memoryZip(int24 xl, int24 xu, int24 yl, int24 yu, int24 zl, int24 zu) public {
//         int24[6] memory arr = [xl, xu, yl, yu, zl, zu];
//         vm.expectSafeMemory(0x00, 0x60);
//         zip(arr);
//     }

//     function test_memoryExtract(int24 xl, int24 xu, int24 yl, int24 yu, int24 zl, int24 zu) public {
//         uint64 count = 0;
//         if (xl != xu) count += 1;
//         if (yl != yu) count += 1;
//         if (zl != zu) count += 1;
//         uint256 zipped = zip([xl, xu, yl, yu, zl, zu]);

//         uint64 ptr;
//         assembly ("memory-safe") {
//             ptr := mload(0x40)
//         }

//         vm.expectSafeMemory(ptr, ptr + 32 * (1 + 2 * count));
//         extract(zipped);
//     }

//     function test_memoryExtractDirty(int24 xl, int24 xu, uint256 dirt) public {
//         uint256 zipped = zip([xl, xu, xl, xu, xl, xu]);

//         // Write data after the free memory pointer, without updating the pointer
//         // (make it dirty)
//         assembly ("memory-safe") {
//             let ptr := mload(0x40)
//             mstore(ptr, dirt)
//             mstore(add(ptr, 0x20), dirt)
//             mstore(add(ptr, 0x40), dirt)
//             mstore(add(ptr, 0x60), dirt)
//             mstore(add(ptr, 0x80), dirt)
//             // ...could add more, doesn't really matter
//         }

//         int24[] memory extracted = extract(zipped);
//         if (xl != xu) {
//             assertEq(extracted.length, 6);
//             assertEq(extracted[0], xl);
//             assertEq(extracted[1], xu);
//             assertEq(extracted[2], xl);
//             assertEq(extracted[3], xu);
//             assertEq(extracted[4], xl);
//             assertEq(extracted[5], xu);
//         } else {
//             assertEq(extracted.length, 0);
//         }
//     }

//     function test_zip(int24 xl, int24 xu, int24 yl, int24 yu, int24 zl, int24 zu) public {
//         uint256 zipped = zip([xl, xu, yl, yu, zl, zu]);

//         unchecked {
//             assertEq(int24(int256(zipped % (1 << 24))), xl);
//             assertEq(int24(int256((zipped >> 24) % (1 << 24))), xu);
//             assertEq(int24(int256((zipped >> 48) % (1 << 24))), yl);
//             assertEq(int24(int256((zipped >> 72) % (1 << 24))), yu);
//             assertEq(int24(int256((zipped >> 96) % (1 << 24))), zl);
//             assertEq(int24(int256((zipped >> 120) % (1 << 24))), zu);
//         }
//     }

//     function test_emptyWrite(int24 xl, int24 xu, int24 yl, int24 yu, int24 zl, int24 zu) public {
//         positions[0] = xl;
//         positions[1] = xu;
//         positions[2] = yl;
//         positions[3] = yu;
//         positions[4] = zl;
//         positions[5] = zu;
        
//         positions.write(0);

//         // Writing `0` tells it not to change anything
//         assertEq(positions[0], xl);
//         assertEq(positions[1], xu);
//         assertEq(positions[2], yl);
//         assertEq(positions[3], yu);
//         assertEq(positions[4], zl);
//         assertEq(positions[5], zu);
//     }

//     function test_writePassthrough(int24 xl, int24 xu, int24 yl, int24 yu, int24 zl, int24 zu) public {
//         positions[0] = xl;
//         positions[1] = xu;
//         positions[2] = yl;
//         positions[3] = yu;
//         positions[4] = zl;
//         positions[5] = zu;
        
//         int24[] memory a = positions.write(0);
//         int24[] memory b = positions.read();

//         assertEq(a.length, b.length);

//         if (a.length > 0) {
//             assertEq(a[0], b[0]);
//             assertEq(a[1], b[1]);
//         }
//         if (a.length > 2) {
//             assertEq(a[2], b[2]);
//             assertEq(a[3], b[3]);
//         }
//         if (a.length > 4) {
//             assertEq(a[4], b[4]);
//             assertEq(a[5], b[5]);
//         }
//     }

//     function test_singleWrite(int24 xl, int24 xu) public {
//         vm.assume(xl != 0 || xu != 0);

//         positions.write(zip([xl, xu, 0, 0, 0, 0]));

//         assertEq(positions[0], xl);
//         assertEq(positions[1], xu);
//         assertEq(positions[2], 0);
//         assertEq(positions[3], 0);
//         assertEq(positions[4], 0);
//         assertEq(positions[5], 0);
//     }

//     function test_doubleWrite(int24 xl, int24 xu, int24 yl, int24 yu) public {
//         vm.assume(xl != yl || xu != yu);

//         positions.write(zip([xl, xu, yl, yu, 0, 0]));

//         assertEq(positions[0], xl);
//         assertEq(positions[1], xu);
//         assertEq(positions[2], yl);
//         assertEq(positions[3], yu);
//         assertEq(positions[4], 0);
//         assertEq(positions[5], 0);
//     }

//     function test_doubleWriteSpaceBetween(int24 xl, int24 xu, int24 yl, int24 yu) public {
//         vm.assume(xl != yl || xu != yu);
//         vm.assume(xl != 0 || xu != 0);
//         vm.assume(yl != 0 || yu != 0);

//         positions.write(zip([xl, xu, 0, 0, yl, yu]));

//         assertEq(positions[0], xl);
//         assertEq(positions[1], xu);
//         assertEq(positions[2], 0);
//         assertEq(positions[3], 0);
//         assertEq(positions[4], yl);
//         assertEq(positions[5], yu);
//     }

//     function test_tripleWrite(int24 xl, int24 xu, int24 yl, int24 yu, int24 zl, int24 zu) public {
//         vm.assume(xl != yl || xu != yu);
//         vm.assume(xl != zl || xu != zu);
//         vm.assume(yl != zl || yu != zu);

//         positions.write(zip([xl, xu, yl, yu, zl, zu]));

//         assertEq(positions[0], xl);
//         assertEq(positions[1], xu);
//         assertEq(positions[2], yl);
//         assertEq(positions[3], yu);
//         assertEq(positions[4], zl);
//         assertEq(positions[5], zu);
//     }

//     function test_cannotWriteIdenticalXY(int24 xl, int24 xu, int24 zl, int24 zu) public {
//         vm.assume(xl != zl || xu != zu);
//         vm.assume(xl != xu);

//         vm.expectRevert(bytes(""));
//         positions.write(zip([xl, xu, xl, xu, zl, zu]));
//     }

//     function test_cannotWriteIdenticalYZ(int24 xl, int24 xu, int24 yl, int24 yu) public {
//         vm.assume(xl != yl || xu != yu);
//         vm.assume(yl != yu);

//         vm.expectRevert(bytes(""));
//         positions.write(zip([xl, xu, yl, yu, yl, yu]));
//     }

//     function test_cannotWriteIdenticalXZ(int24 xl, int24 xu, int24 yl, int24 yu) public {
//         vm.assume(xl != yl || xu != yu);
//         vm.assume(xl != xu);

//         vm.expectRevert(bytes(""));
//         positions.write(zip([xl, xu, yl, yu, xl, xu]));
//     }

//     function test_cannotWriteIdenticalXYZ(int24 xl, int24 xu) public {
//         vm.assume(xl != xu);

//         vm.expectRevert(bytes(""));
//         positions.write(zip([xl, xu, xl, xu, xl, xu]));
//     }

//     function test_emptyRead() public {
//         delete positions;
//         int24[] memory positions_ = positions.read();
//         assertEq(positions_.length, 0);
//     }

//     function test_singleRead(int24 xl, int24 xu) public {
//         positions[0] = xl;
//         positions[1] = xu;
//         positions[2] = 0;
//         positions[3] = 0;
//         positions[4] = 0;
//         positions[5] = 0;

//         int24[] memory positions_ = positions.read();

//         if (xl == xu) {
//             assertEq(positions_.length, 0);
//         } else {
//             assertEq(positions_.length, 2);
//             assertEq(positions_[0], xl);
//             assertEq(positions_[1], xu);
//         }
//     }

//     function test_doubleRead(int24 xl, int24 xu, int24 yl, int24 yu) public {
//         positions[0] = xl;
//         positions[1] = xu;
//         positions[2] = yl;
//         positions[3] = yu;
//         positions[4] = 0;
//         positions[5] = 0;

//         int24[] memory positions_ = positions.read();

//         if (xl == xu && yl == yu) {
//             assertEq(positions_.length, 0);
//         } else if (xl == xu) {
//             assertEq(positions_.length, 2);
//             assertEq(positions_[0], yl);
//             assertEq(positions_[1], yu);
//         } else if (yl == yu) {
//             assertEq(positions_.length, 2);
//             assertEq(positions_[0], xl);
//             assertEq(positions_[1], xu);
//         } else {
//             assertEq(positions_.length, 4);
//             assertEq(positions_[0], xl);
//             assertEq(positions_[1], xu);
//             assertEq(positions_[2], yl);
//             assertEq(positions_[3], yu);
//         }
//     }

//     function test_tripleRead(int24 xl, int24 xu, int24 yl, int24 yu, int24 zl, int24 zu) public {
//         positions[0] = xl;
//         positions[1] = xu;
//         positions[2] = yl;
//         positions[3] = yu;
//         positions[4] = zl;
//         positions[5] = zu;

//         int24[] memory positions_ = positions.read();

//         if (xl == xu && yl == yu && zl == zu) {
//             assertEq(positions_.length, 0);
//             return;
//         }

//         if (xl != xu && yl == yu && zl == zu) {
//             assertEq(positions_.length, 2);
//             assertEq(positions_[0], xl);
//             assertEq(positions_[1], xu);
//             return;
//         }

//         if (xl == xu && yl != yu && zl == zu) {
//             assertEq(positions_.length, 2);
//             assertEq(positions_[0], yl);
//             assertEq(positions_[1], yu);
//             return;
//         }

//         if (xl == xu && yl == yu && zl != zu) {
//             assertEq(positions_.length, 2);
//             assertEq(positions_[0], zl);
//             assertEq(positions_[1], zu);
//             return;
//         }

//         if (xl != xu && yl != yu && zl == zu) {
//             assertEq(positions_.length, 4);
//             assertEq(positions_[0], xl);
//             assertEq(positions_[1], xu);
//             assertEq(positions_[2], yl);
//             assertEq(positions_[3], yu);
//             return;
//         }

//         if (xl == xu && yl != yu && zl != zu) {
//             assertEq(positions_.length, 4);
//             assertEq(positions_[0], yl);
//             assertEq(positions_[1], yu);
//             assertEq(positions_[2], zl);
//             assertEq(positions_[3], zu);
//             return;
//         }

//         if (xl != xu && yl == yu && zl != zu) {
//             assertEq(positions_.length, 4);
//             assertEq(positions_[0], xl);
//             assertEq(positions_[1], xu);
//             assertEq(positions_[2], zl);
//             assertEq(positions_[3], zu);
//             return;
//         }

//         assertEq(positions_.length, 6);
//         assertEq(positions_[0], xl);
//         assertEq(positions_[1], xu);
//         assertEq(positions_[2], yl);
//         assertEq(positions_[3], yu);
//         assertEq(positions_[4], zl);
//         assertEq(positions_[5], zu);
//     }
// }
