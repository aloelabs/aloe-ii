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
    using FullMath for uint256;
    using FullMath for uint144;
    using FullMath for uint80;

    uint256 public constant INTERNAL_PRECISION = 1e12;

    uint256 public constant INITIAL_EXCHANGE_RATE = 367879441171;

    uint256 public constant BORROWS_SCALER = 5192296858534827628530496329220096000000000232;

    Factory public immutable FACTORY;

    ERC20 public immutable ASSET;

    InterestModel public immutable INTEREST_MODEL;

    address public immutable TREASURY;

    struct PackedSlot {
        // The total amount of `ASSET` that has been borrowed
        uint144 totalBorrows;
        // The amount of growth experienced by a hypothetical loan taken out at Kitty creation
        uint80 borrowIndex;
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
        ASSET = _asset;
        INTEREST_MODEL = _interestModel;
        TREASURY = _treasury;

        packedSlot = PackedSlot({
            totalBorrows: 0,
            borrowIndex: uint80(INTERNAL_PRECISION),
            borrowIndexTimestamp: uint32(block.timestamp)
        });
    }

    modifier onlyMarginAccount() {
        require(FACTORY.isMarginAccountAllowed(this, msg.sender), "Aloe: bad account");
        _;
    }

    // TODO prevent new deposits after 2100
    function deposit(uint256 amount) external returns (uint256 shares) {
        // Poke (includes reentrancy guard)
        (PackedSlot memory _packedSlot, uint256 _totalSupply, uint256 _inventory) = accrueInterest();

        shares = _computeShares(_totalSupply, _inventory, amount);
        require(shares != 0, "Aloe: 0 shares"); // TODO use real Error

        // Pull in tokens from sender
        ASSET.safeTransferFrom(msg.sender, address(this), amount); // TODO use callback with before/after balance checks to support permit

        // Mint shares (emits event that can be interpreted as a deposit)
        _mint(msg.sender, shares);

        packedSlot = _packedSlot;
    }

    function withdraw(uint256 shares) external returns (uint256 amount) {
        // Poke (includes reentrancy guard)
        (PackedSlot memory _packedSlot, uint256 _totalSupply, uint256 _inventory) = accrueInterest();

        amount = shares.mulDiv(_inventory, _totalSupply * INTERNAL_PRECISION);
        require(amount != 0, "Aloe: amount too low"); // TODO use real Error

        // Transfer tokens
        ASSET.safeTransfer(msg.sender, amount);

        // Burn shares (emits event that can be interpreted as a withdrawal)
        _burn(msg.sender, shares);

        packedSlot = _packedSlot;
    }

    // amount must be <= type(uint144).max / INTERNAL_PRECISION
    // TODO prevent new borrows after 2100
    function borrow(uint256 amount) external onlyMarginAccount {
        // Poke (includes reentrancy guard)
        (PackedSlot memory _packedSlot, , ) = accrueInterest();

        borrows[msg.sender] += amount.mulDivRoundingUp(BORROWS_SCALER, _packedSlot.borrowIndex);
        _packedSlot.totalBorrows += uint144(amount * INTERNAL_PRECISION);

        ASSET.safeTransfer(msg.sender, amount);
        packedSlot = _packedSlot;
    }

    // amount must be <= type(uint144).max / INTERNAL_PRECISION
    function repay(uint256 amount) external onlyMarginAccount {
        // Poke (includes reentrancy guard)
        (PackedSlot memory _packedSlot, , ) = accrueInterest();

        borrows[msg.sender] -= amount.mulDiv(BORROWS_SCALER, _packedSlot.borrowIndex);
        _packedSlot.totalBorrows -= uint144(amount * INTERNAL_PRECISION);

        ASSET.safeTransferFrom(msg.sender, address(this), amount);
        packedSlot = _packedSlot;
    }

    function accrueInterest() public returns (PackedSlot memory, uint256, uint256) {
        PackedSlot memory _packedSlot = packedSlot;

        // Reentrancy guard
        require(_packedSlot.borrowIndexTimestamp != 0);
        packedSlot.borrowIndexTimestamp = 0;

        uint256 _totalSupply = totalSupply;
        uint256 _inventory = _getInventory(_packedSlot.totalBorrows);
        if (_packedSlot.borrowIndexTimestamp == block.timestamp || _inventory == 0 || _packedSlot.totalBorrows == 0) {
            return (_packedSlot, _totalSupply, _inventory);
        }

        uint256 accrualFactor = INTEREST_MODEL.getAccrualFactor(
            block.timestamp - _packedSlot.borrowIndexTimestamp,
            uint256(1e18).mulDiv(_packedSlot.totalBorrows, _inventory)
        );
        uint256 accruedInterest = _packedSlot.totalBorrows.mulDiv(accrualFactor, INTERNAL_PRECISION);

        _inventory += accruedInterest;
        _packedSlot.totalBorrows += uint144(accruedInterest);
        _packedSlot.borrowIndex = uint80(_packedSlot.borrowIndex.mulDiv(INTERNAL_PRECISION + accrualFactor, INTERNAL_PRECISION));
        _packedSlot.borrowIndexTimestamp = uint32(block.timestamp); // fails in February 2106

        // TODO can we reformulate newTotalSupply to rely on borrowIndex (known resolution) instead of inventory and accruedInterest (potentially low resolution)
        uint256 newTotalSupply = FullMath.mulDiv(
            totalSupply,
            _inventory,
            _inventory - accruedInterest / 8 // `8` indicates a 1/8=12.5% reserve factor
        );
        if (newTotalSupply != totalSupply) _mint(TREASURY, newTotalSupply - totalSupply);

        return (_packedSlot, newTotalSupply, _inventory);
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    // TODO use ERC4626-style function names
    function balanceOfUnderlying(address account) external view returns (uint256) {
        // TODO this should probably accrueInterest
        return balanceOf[account].mulDiv(_getInventory(packedSlot.totalBorrows), totalSupply) / INTERNAL_PRECISION; // TODO fails when totalSupply = 0
    }

    // TODO this is really borrowBalanceStored, not Current (in Compound lingo)
    function borrowBalanceCurrent(address account) external view returns (uint256) {
        return FullMath.mulDiv(borrows[account], packedSlot.borrowIndex, 1e18);
    }

    // TODO exchangeRateCurrent and stored

    // TODO utilizationCurrent and stored

    // TODO inventoryCurrent and stored

    function _getInventory(uint256 _totalBorrows) private view returns (uint256) {
        unchecked {
            return ASSET.balanceOf(address(this)) * INTERNAL_PRECISION + _totalBorrows;
        }
    }

    // ⬆️⬆️⬆️⬆️ VIEW FUNCTIONS ⬆️⬆️⬆️⬆️  ------------------------------------------------------------------------------
    // ⬇️⬇️⬇️⬇️ PURE FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    function _computeShares(
        uint256 _totalSupply,
        uint256 _inventory,
        uint256 _amount
    ) private pure returns (uint256) {
        _amount *= INTERNAL_PRECISION;
        return (_totalSupply == 0) ? _amount * INITIAL_EXCHANGE_RATE : FullMath.mulDiv(_amount, _totalSupply, _inventory);
    }
}
