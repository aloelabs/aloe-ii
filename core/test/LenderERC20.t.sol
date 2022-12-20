// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "src/Lender.sol";

import {deploySingleLender} from "./Utils.sol";

contract LenderERC20Test is Test {
    using stdStorage for StdStorage;

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    event Transfer(address indexed from, address indexed to, uint256 amount);

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    ERC20 asset;

    Lender lender;

    function setUp() public {
        asset = new MockERC20("Token", "TKN", 18);
        lender = deploySingleLender(asset, address(2), new InterestModel());
    }

    function test_canTransferUpToBalance(address from, address to, uint112 balance, uint112 shares) public {
        if (balance < shares) (balance, shares) = (shares, balance);

        deal(address(lender), from, balance);

        vm.prank(from);
        vm.expectEmit(true, true, false, true, address(lender));
        emit Transfer(from, to, shares);
        assertTrue(lender.transfer(to, shares));

        if (from == to) {
            assertEq(lender.balanceOf(from), balance);
        } else {
            assertEq(lender.balanceOf(from), balance - shares);
            assertEq(lender.balanceOf(to), shares);
        }
    }

    function test_cannotTransferMoreThanBalance(address from, address to, uint112 balance, uint112 shares) public {
        vm.assume(balance != shares);
        if (balance > shares) (balance, shares) = (shares, balance);

        deal(address(lender), from, balance);

        vm.prank(from);
        vm.expectRevert(bytes(""));
        lender.transfer(to, shares);
    }

    function test_cannotTransferOthersTokens(address from, address to, uint112 shares) public {
        vm.assume(from != address(this));
        vm.assume(shares != 0);

        deal(address(lender), from, shares);

        vm.expectRevert(bytes(""));
        lender.transfer(to, shares);
    }

    function test_cannotTransferIfFromAssociatedWithCourier(address from, address to, uint112 shares, uint32 id) public {
        vm.assume(id != 0);

        uint256 value = (uint256(id) << 224) + shares;
        stdstore.target(address(lender)).sig("balances(address)").with_key(from).depth(0).checked_write(value);

        vm.prank(from);
        vm.expectRevert(bytes(""));
        lender.transfer(to, shares);
    }

    function test_cannotTransferIfToAssociatedWithCourier(address from, address to, uint112 shares, uint32 id) public {
        vm.assume(id != 0);

        stdstore.target(address(lender)).sig("balances(address)").with_key(from).depth(0).checked_write(shares);
        stdstore.target(address(lender)).sig("balances(address)").with_key(to).depth(0).checked_write(uint256(id) << 224);

        vm.prank(from);
        vm.expectRevert(bytes(""));
        lender.transfer(to, shares);
    }

    function test_canApprove(address from, address spender, uint256 amount) public {
        vm.prank(from);
        vm.expectEmit(true, true, false, true, address(lender));
        emit Approval(from, spender, amount);
        assertTrue(lender.approve(spender, amount));

        assertEq(lender.allowance(from, spender), amount);
    }

    function test_canTransferFromUpToAllowance(address from, address to, uint112 shares, uint112 allowance) public {
        if (allowance < shares) (allowance, shares) = (shares, allowance);

        deal(address(lender), from, type(uint112).max);

        vm.prank(from);
        lender.approve(address(this), allowance);

        vm.expectEmit(true, true, false, true, address(lender));
        emit Transfer(from, to, shares);
        assertTrue(lender.transferFrom(from, to, shares));

        if (from == to) {
            assertEq(lender.balanceOf(from), type(uint112).max);
        } else {
            assertEq(lender.balanceOf(from), type(uint112).max - shares);
            assertEq(lender.balanceOf(to), shares);
            assertEq(lender.allowance(from, address(this)), allowance - shares);
        }
    }

    function test_cannotTransferFromMoreThanBalance(address from, address to, uint112 balance, uint112 shares) public {
        vm.assume(balance != shares);
        if (balance > shares) (balance, shares) = (shares, balance);

        deal(address(lender), from, balance);

        vm.prank(from);
        lender.approve(address(this), type(uint256).max);

        vm.expectRevert(bytes(""));
        lender.transferFrom(from, to, shares);
    }

    function test_cannotTransferFromMoreThanAllowance(
        address from,
        address to,
        uint112 shares,
        uint112 allowance
    ) public {
        vm.assume(allowance != shares);
        if (allowance > shares) (allowance, shares) = (shares, allowance);

        deal(address(lender), from, type(uint112).max);

        vm.prank(from);
        lender.approve(address(this), allowance);

        console.log(allowance);
        console.log(shares);

        vm.expectRevert();
        lender.transferFrom(from, to, shares);
    }

    function test_canApproveInfinite(address from, address to, uint112 shares) public {
        vm.assume(from != to);

        deal(address(lender), from, type(uint112).max);

        vm.prank(from);
        lender.approve(address(this), type(uint256).max);

        assertEq(lender.balanceOf(from), type(uint112).max);
        lender.transferFrom(from, to, shares);
        assertEq(lender.balanceOf(from), type(uint112).max - shares);
        assertEq(lender.balanceOf(to), shares);
        assertEq(lender.allowance(from, address(this)), type(uint256).max);
    }

    function test_canPermit(uint256 privateKey, address spender, uint256 amount, uint256 nonce) public {
        privateKey = privateKey / 2 + 1;
        address owner = vm.addr(privateKey);

        if (nonce == type(uint256).max) nonce -= 1;
        stdstore.target(address(lender)).sig("nonces(address)").with_key(owner).depth(0).checked_write(nonce);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    lender.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, amount, nonce, block.timestamp))
                )
            )
        );

        lender.permit(owner, spender, amount, block.timestamp, v, r, s);
        assertEq(lender.allowance(owner, spender), amount);
        assertEq(lender.nonces(owner), nonce + 1);
    }

    function test_cannotPermitAfterDeadline(uint256 privateKey, address spender, uint256 amount, uint256 nonce) public {
        privateKey = privateKey / 2 + 1;
        address owner = vm.addr(privateKey);

        if (nonce == type(uint256).max) nonce -= 1;
        stdstore.target(address(lender)).sig("nonces(address)").with_key(owner).depth(0).checked_write(nonce);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    lender.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, amount, nonce, block.timestamp - 1))
                )
            )
        );

        vm.expectRevert(bytes("PERMIT_DEADLINE_EXPIRED"));
        lender.permit(owner, spender, amount, block.timestamp - 1, v, r, s);
    }

    function test_cannotPermitWithBadSignature(
        uint256 privateKey,
        address spender,
        uint256 amount,
        uint256 nonce
    ) public {
        privateKey = privateKey / 2 + 1;
        address owner = vm.addr(privateKey);

        if (nonce == type(uint256).max) nonce -= 1;
        stdstore.target(address(lender)).sig("nonces(address)").with_key(owner).depth(0).checked_write(nonce);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey + 1,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    lender.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, amount, nonce, block.timestamp))
                )
            )
        );

        vm.expectRevert(bytes("INVALID_SIGNER"));
        lender.permit(owner, spender, amount, block.timestamp, v, r, s);
    }
}
