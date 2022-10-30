// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {FullMath} from "./libraries/FullMath.sol";

import {InterestModel} from "./InterestModel.sol";
import {Factory} from "./Factory.sol";

/**
 * TODO: enable flash loans
 */
contract Kitty is ERC20 {
    using SafeTransferLib for ERC20;

    Factory public immutable FACTORY;

    ERC20 public immutable asset;

    InterestModel public immutable interestModel;

    address public immutable treasury;

    struct PackedSlot {
        // The total amount of `asset` that has been borrowed
        uint128 totalBorrows;
        // The amount of growth experienced by a hypothetical loan, taken out at Kitty creation
        uint96 borrowIndex;
        // The `block.timestamp` from the last time `borrowIndex` was updated
        // If zero, the Kitty is currently locked to reentrancy
        uint32 borrowIndexTimestamp;
    }

    PackedSlot public packedSlot;

    mapping(address => uint256) public borrows;

    constructor(ERC20 _asset, InterestModel _interestModel, address _treasury)
        ERC20(
            string.concat("Aloe II ", _asset.name()),
            string.concat(_asset.symbol(), "+"),
            18 // TODO decide magnitude of internal bookkeeping
        )
    {
        FACTORY = Factory(msg.sender);
        asset = _asset;
        interestModel = _interestModel;
        treasury = _treasury;

        packedSlot = PackedSlot({
            totalBorrows: 0,
            borrowIndex: 1e18,
            borrowIndexTimestamp: uint32(block.timestamp)
        });
    }

    modifier onlyMarginAccount() {
        require(FACTORY.isMarginAccountAllowed(this, msg.sender), "Aloe: bad account");
        _;
    }

    function deposit(uint256 amount) external returns (uint256 shares) {
        // Poke (includes reentrancy guard)
        (PackedSlot memory _packedSlot, uint256 _totalSupply, uint256 _inventory) = accrueInterest();

        shares = _computeShares(_totalSupply, _inventory, amount);
        require(shares != 0, "Aloe: 0 shares"); // TODO use real Error

        // Pull in tokens from sender
        asset.safeTransferFrom(msg.sender, address(this), amount); // TODO use callback with before/after balance checks to support permit

        // Mint shares (emits event that can be interpreted as a deposit)
        _mint(msg.sender, shares);

        packedSlot = _packedSlot;
    }

    function withdraw(uint256 shares) external returns (uint256 amount) {
        // Poke (includes reentrancy guard)
        (PackedSlot memory _packedSlot, uint256 _totalSupply, uint256 _inventory) = accrueInterest();

        amount = FullMath.mulDiv(_inventory, shares, _totalSupply);
        require(amount != 0, "Aloe: amount too low"); // TODO use real Error

        // Transfer tokens
        asset.safeTransfer(msg.sender, amount);

        // Burn shares (emits event that can be interpreted as a withdrawal)
        _burn(msg.sender, shares);

        packedSlot = _packedSlot;
    }

    function borrow(uint128 amount) external onlyMarginAccount {
        // Poke (includes reentrancy guard)
        (PackedSlot memory _packedSlot, , ) = accrueInterest();

        borrows[msg.sender] += FullMath.mulDiv(1e18, amount, _packedSlot.borrowIndex);
        _packedSlot.totalBorrows += amount;

        asset.safeTransfer(msg.sender, amount);
        packedSlot = _packedSlot;
    }

    function repay(uint128 amount) external onlyMarginAccount {
        // Poke (includes reentrancy guard)
        (PackedSlot memory _packedSlot, , ) = accrueInterest();

        borrows[msg.sender] -= FullMath.mulDiv(1e18, amount, _packedSlot.borrowIndex); // will fail if `amount / borrowIndex > borrows[msg.sender`
        _packedSlot.totalBorrows -= amount;

        asset.safeTransferFrom(msg.sender, address(this), amount);
        packedSlot = _packedSlot;
    }

    function accrueInterest() public returns (PackedSlot memory, uint256, uint256) {
        PackedSlot memory _packedSlot = packedSlot;

        // Reentrancy guard
        require(_packedSlot.borrowIndexTimestamp != 0);
        packedSlot.borrowIndexTimestamp = 0;

        uint256 _totalSupply = totalSupply;
        uint256 _inventory = _getInventory(_packedSlot.totalBorrows);
        if (_packedSlot.borrowIndexTimestamp == block.timestamp || _inventory == 0) {
            return (_packedSlot, _totalSupply, _inventory);
        }

        uint256 accrualFactor = interestModel.getAccrualFactor(
            block.timestamp - _packedSlot.borrowIndexTimestamp,
            FullMath.mulDiv(1e18, _packedSlot.totalBorrows, _inventory)
        );
        uint256 accruedInterest = FullMath.mulDiv(_packedSlot.totalBorrows, accrualFactor, 1e18);

        _inventory += accruedInterest;
        _packedSlot.totalBorrows += uint128(accruedInterest);
        _packedSlot.borrowIndex = uint96(FullMath.mulDiv(_packedSlot.borrowIndex, 1e18 + accrualFactor, 1e18));
        _packedSlot.borrowIndexTimestamp = uint32(block.timestamp); // fails after Feb 07 2106 06:28:15

        uint256 newTotalSupply = FullMath.mulDiv(
            totalSupply,
            _inventory,
            _inventory - accruedInterest / 8 // `8` indicates a 12.5% reserve factor
        );
        _mint(treasury, newTotalSupply - totalSupply);

        return (_packedSlot, newTotalSupply, _inventory);
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    // TODO use ERC4626-style function names
    function balanceOfUnderlying(address account) external view returns (uint256) {
        // TODO this should probably accrueInterest
        return FullMath.mulDiv(_getInventory(packedSlot.totalBorrows), balanceOf[account], totalSupply); // TODO fails when totalSupply = 0
    }

    // TODO this is really borrowBalanceStored, not Current (in Compound lingo)
    function borrowBalanceCurrent(address account) external view returns (uint256) {
        return FullMath.mulDiv(borrows[account], packedSlot.borrowIndex, 1e18);
    }

    // TODO exchangeRateCurrent

    // TODO utilizationCurrent

    function getInventory() external view returns (uint256) {
        return _getInventory(packedSlot.totalBorrows);
    }

    function _getInventory(uint256 _totalBorrows) private view returns (uint256) {
        return asset.balanceOf(address(this)) + _totalBorrows;
    }

    // ⬆️⬆️⬆️⬆️ VIEW FUNCTIONS ⬆️⬆️⬆️⬆️  ------------------------------------------------------------------------------
    // ⬇️⬇️⬇️⬇️ PURE FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    function _computeShares(
        uint256 _totalSupply,
        uint256 _inventory,
        uint256 _amount
    ) private pure returns (uint256) {
        // TODO When _totalSupply == 0, require that _amount > someValue to avoid math errors
        return (_totalSupply == 0) ? _amount : FullMath.mulDiv(_amount, _totalSupply, _inventory);
    }
}
