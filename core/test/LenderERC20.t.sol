// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "src/Lender.sol";
import "src/RateModel.sol";

import {FactoryForLenderTests} from "./Utils.sol";

contract LenderERC20Test is Test {
    using stdStorage for StdStorage;

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    event Transfer(address indexed from, address indexed to, uint256 amount);

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    ERC20 asset;

    Lender lender;

    function setUp() public {
        FactoryForLenderTests factory = new FactoryForLenderTests(new RateModel(), ERC20(address(0)));

        asset = new MockERC20("Test Token", "TKN", 18);
        lender = factory.deploySingleLender(asset);
    }

    function test_symbol() public {
        assertEq(lender.symbol(), "TKN+");
    }

    function test_decimals() public {
        assertEq(lender.decimals(), asset.decimals());
    }

    function test_transfer(address from, address to, uint256 shares, uint112 balance) public {
        deal(address(lender), from, balance);

        // SHOULD throw if `msg.sender` does not have enough tokens to spend
        if (shares > balance) {
            vm.prank(from);
            vm.expectRevert(bytes(""));
            lender.transfer(to, shares);

            shares = shares % (uint256(balance) + 1);
        }

        // Transfers amount of tokens to address `to` and MUST fire the `Transfer` event
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

    function test_transferFrom(
        address spender,
        address from,
        address to,
        uint256 shares,
        uint112 balance,
        uint256 allowance
    ) public {
        deal(address(lender), from, balance);

        vm.prank(from);
        lender.approve(spender, allowance);

        // SHOULD throw unless `from` has deliberately authorized the `spender`
        if (shares > balance || shares > allowance) {
            vm.prank(spender);
            vm.expectRevert();
            lender.transferFrom(from, to, shares);

            if (shares > balance) shares = shares % (uint256(balance) + 1);
            if (shares > allowance) shares = shares % (allowance + 1);
        }

        // Transfers amount of tokens from address `from` and to address `to` and MUST fire the `Transfer` event
        vm.prank(spender);
        vm.expectEmit(true, true, false, true, address(lender));
        emit Transfer(from, to, shares);
        assertTrue(lender.transferFrom(from, to, shares));

        if (from == to) {
            assertEq(lender.balanceOf(from), balance);
        } else {
            assertEq(lender.balanceOf(from), balance - shares);
            assertEq(lender.balanceOf(to), shares);
        }

        if (allowance == type(uint256).max) {
            assertEq(lender.allowance(from, spender), type(uint256).max);
        } else {
            assertEq(lender.allowance(from, spender), allowance - shares);
        }
    }

    function test_approve(address from, address spender, uint256 amount) public {
        vm.prank(from);
        vm.expectEmit(true, true, false, true, address(lender));
        emit Approval(from, spender, amount);
        assertTrue(lender.approve(spender, amount));

        assertEq(lender.allowance(from, spender), amount);
    }

    function test_permit(uint248 key, address spender, uint256 shares, uint256 nonce) public {
        vm.assume(key != 0);
        vm.assume(nonce != type(uint256).max);

        address owner = vm.addr(key);
        stdstore.target(address(lender)).sig("nonces(address)").with_key(owner).depth(0).checked_write(nonce);

        (uint8 v, bytes32 r, bytes32 s) = _sign(key, owner, spender, shares, nonce, block.timestamp);

        lender.permit(owner, spender, shares, block.timestamp, v, r, s);
        assertEq(lender.allowance(owner, spender), shares);
        assertEq(lender.nonces(owner), nonce + 1);
    }

    function test_permitChecksDeadline(
        uint248 key,
        address spender,
        uint256 shares,
        uint256 nonce,
        uint256 deadline
    ) public {
        vm.assume(key != 0);
        vm.assume(nonce != type(uint256).max);
        deadline = deadline % block.timestamp;

        address owner = vm.addr(key);
        stdstore.target(address(lender)).sig("nonces(address)").with_key(owner).depth(0).checked_write(nonce);

        (uint8 v, bytes32 r, bytes32 s) = _sign(key, owner, spender, shares, nonce, deadline);

        vm.expectRevert(bytes("Aloe: permit expired"));
        lender.permit(owner, spender, shares, deadline, v, r, s);
    }

    function test_permitChecksSignature(uint248 key, address spender, uint256 shares, uint256 nonce) public {
        vm.assume(key != 0);
        vm.assume(nonce != type(uint256).max);

        address owner = vm.addr(key);
        stdstore.target(address(lender)).sig("nonces(address)").with_key(owner).depth(0).checked_write(nonce);

        (uint8 v, bytes32 r, bytes32 s) = _sign(uint256(key) + 1, owner, spender, shares, nonce, block.timestamp);

        vm.expectRevert(bytes("Aloe: permit invalid"));
        lender.permit(owner, spender, shares, block.timestamp, v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
                            HELP THE FUZZER
    //////////////////////////////////////////////////////////////*/

    function test_transfer0(address from, address to, uint112 balance) public {
        // Transfers of 0 values MUST be treated as normal transfers and fire the `Transfer` event
        test_transfer(from, to, 0, balance);
    }

    function test_transferFrom0(address spender, address from, address to, uint112 balance, uint256 allowance) public {
        // Transfers of 0 values MUST be treated as normal transfers and fire the `Transfer` event
        test_transferFrom(spender, from, to, 0, balance, allowance);
    }

    function test_transferFromIsConstrainedByBalance(
        address spender,
        address from,
        address to,
        uint256 shares,
        uint112 balance
    ) public {
        test_transferFrom(spender, from, to, shares, balance, type(uint256).max);
    }

    function test_transferFromIsConstrainedByAllowance(
        address spender,
        address from,
        address to,
        uint256 shares,
        uint112 allowance
    ) public {
        test_transferFrom(spender, from, to, shares, type(uint112).max, allowance);
    }

    /*//////////////////////////////////////////////////////////////
                             SPECIAL CASES
    //////////////////////////////////////////////////////////////*/

    function test_cannotTransferIfSenderHasCourier(address from, address to, uint112 shares, uint32 id) public {
        vm.assume(id != 0);

        uint256 value = (uint256(id) << 224) + shares;
        stdstore.target(address(lender)).sig("balances(address)").with_key(from).depth(0).checked_write(value);

        vm.prank(from);
        vm.expectRevert(bytes(""));
        lender.transfer(to, shares);
    }

    function test_cannotTransferIfRecipientHasCourier(address from, address to, uint112 shares, uint32 id) public {
        vm.assume(id != 0);

        stdstore.target(address(lender)).sig("balances(address)").with_key(from).depth(0).checked_write(shares);
        stdstore.target(address(lender)).sig("balances(address)").with_key(to).depth(0).checked_write(
            uint256(id) << 224
        );

        vm.prank(from);
        vm.expectRevert(bytes(""));
        lender.transfer(to, shares);
    }

    /// @dev Yes, I'm aware this is a silly test. It's fine.
    function test_transferReliesOnSender(address from, address to, uint112 shares) public {
        vm.assume(from != address(this));
        vm.assume(shares != 0);

        deal(address(lender), from, shares);

        vm.expectRevert(bytes("")); // because we didn't `vm.prank(from)`
        lender.transfer(to, shares);
    }

    function _sign(
        uint256 key,
        address owner,
        address spender,
        uint256 shares,
        uint256 nonce,
        uint256 deadline
    ) private view returns (uint8 v, bytes32 r, bytes32 s) {
        return
            vm.sign(
                key,
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        lender.DOMAIN_SEPARATOR(),
                        keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, shares, nonce, deadline))
                    )
                )
            );
    }
}
