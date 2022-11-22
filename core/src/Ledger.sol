// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ImmutableArgs} from "clones-with-immutable-args/ImmutableArgs.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {FullMath} from "./libraries/FullMath.sol";

import {InterestModel} from "./InterestModel.sol";
import {Factory} from "./Factory.sol";

contract Ledger {
    using FullMath for uint256;

    uint256 public constant ONE = 1e12;

    uint256 public constant BORROWS_SCALER = type(uint72).max * ONE; // uint72 is from borrowIndex type

    Factory public immutable FACTORY;

    address public immutable TREASURY;

    InterestModel public immutable INTEREST_MODEL;

    constructor(address treasury, InterestModel interestModel) {
        FACTORY = Factory(msg.sender);
        TREASURY = treasury;
        INTEREST_MODEL = interestModel;
    }

    struct Cache {
        uint256 totalSupply;
        uint256 lastBalance;
        uint256 lastAccrualTime;
        uint256 borrowBase;
        uint256 borrowIndex;
    }

    uint112 public totalSupply;

    uint112 public lastBalance;

    uint32 public lastAccrualTime;

    uint184 public borrowBase;

    uint72 public borrowIndex;

    mapping(address => uint256) public balanceOf;

    mapping(address => uint256) public borrows;

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    uint8 public decimals;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    bytes32 internal lastDomainSeparator;

    uint256 internal lastChainId;

    mapping(address => uint256) public nonces;
    
    function balanceOfUnderlying(address account) external view returns (uint256) {
        // TODO this should probably accrueInterest
        return _convertToAssets({
            shares: balanceOf[account],
            inventory: lastBalance + FullMath.mulDiv(borrowBase, borrowIndex, BORROWS_SCALER),
            totalSupply_: totalSupply
        });
    }

    // TODO this is really borrowBalanceStored, not Current (in Compound lingo)
    function borrowBalanceCurrent(address account) external view returns (uint256) {
        return borrows[account].mulDiv(borrowIndex, BORROWS_SCALER);
    }

    // TODO exchangeRateCurrent and stored

    // TODO utilizationCurrent and stored

    // TODO inventoryCurrent and stored

    function _accrueInterestView(Cache memory cache) internal view returns (Cache memory, uint256, uint256) {
        (uint256 borrowsOld, uint256 accrualFactor) = _getAccrualFactor(cache);
        if (accrualFactor == 0 || borrowsOld == 0) return (cache, cache.lastBalance, cache.totalSupply);

        // TODO sane constraints on accrualFactor WITH TESTS for when accrualFactor is reported to be massive
        cache.borrowIndex = cache.borrowIndex.mulDiv(ONE + accrualFactor, ONE);
        cache.lastAccrualTime = 0; // 0 in storage means locked to reentrancy; 0 in `cache` means `borrowIndex` was updated

        // re-compute borrows and inventory
        uint256 borrowsNew = cache.borrowBase.mulDiv(cache.borrowIndex, BORROWS_SCALER);
        uint256 inventory;
        unchecked {
            inventory = cache.lastBalance + borrowsNew;
        }

        uint256 newTotalSupply = cache.totalSupply.mulDiv(
            inventory,
            inventory - (borrowsNew - borrowsOld) / 8 // `8` indicates a 1/8=12.5% reserve factor
        );
        return (cache, inventory, newTotalSupply);
    }

    function _getAccrualFactor(Cache memory cache) private view returns (uint256 totalBorrows, uint256 accrualFactor) {
        if (cache.lastAccrualTime != block.timestamp && cache.borrowBase != 0) {
            // compute `totalBorrows`
            totalBorrows = cache.borrowBase.mulDiv(cache.borrowIndex, BORROWS_SCALER);
            // get `accrualFactor`
            accrualFactor = INTEREST_MODEL.getAccrualFactor({
                elapsedTime: block.timestamp - cache.lastAccrualTime,
                utilization: uint256(1e18).mulDiv(totalBorrows, totalBorrows + cache.lastBalance)
            });
        }
    }

    function computeDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(name)),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function asset() public pure returns (ERC20) {
        return ERC20(ImmutableArgs.addr());
    }

    function _convertToShares(
        uint256 assets,
        uint256 inventory,
        uint256 totalSupply_
    ) internal pure returns (uint256 shares) {
        shares = (totalSupply_ == 0) ? assets : assets.mulDiv(totalSupply_, inventory);
    }

    function _convertToAssets(
        uint256 shares,
        uint256 inventory,
        uint256 totalSupply_
    ) internal pure returns (uint256 assets) {
        assets = (totalSupply_ == 0) ? shares : shares.mulDiv(inventory, totalSupply_);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view returns (uint256) {
        (, uint256 inventory, ) = _accrueInterestView(Cache(
            totalSupply,
            lastBalance,
            lastAccrualTime,
            borrowBase,
            borrowIndex
        ));
        return inventory;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(Cache(
            totalSupply,
            lastBalance,
            lastAccrualTime,
            borrowBase,
            borrowIndex
        ));
        return _convertToShares(assets, inventory, newTotalSupply);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(Cache(
            totalSupply,
            lastBalance,
            lastAccrualTime,
            borrowBase,
            borrowIndex
        ));
        return _convertToAssets(shares, inventory, newTotalSupply);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(Cache(
            totalSupply,
            lastBalance,
            lastAccrualTime,
            borrowBase,
            borrowIndex
        ));
        return (newTotalSupply == 0) ? shares : shares.mulDivRoundingUp(inventory, newTotalSupply);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(Cache(
            totalSupply,
            lastBalance,
            lastAccrualTime,
            borrowBase,
            borrowIndex
        ));
        return (newTotalSupply == 0) ? assets : assets.mulDivRoundingUp(newTotalSupply, inventory);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns a conservative estimate of the maximum amount of `asset()` that can be deposited into the
     * Vault for `receiver`, through a deposit call.
     * @return The maximum amount of `asset()` that can be deposited
     *
     * @dev Should return the *precise* maximum. In this case that'd be on the order of 2**112 with weird constraints
     * coming from both `lastBalance` and `totalSupply`, which changes during interest accrual. Instead of doing
     * complicated math, we provide a constant conservative estimate of 2**96.
     *
     * - MUST return a limited value if receiver is subject to some deposit limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of assets that may be deposited.
     * - MUST NOT revert.
     */
    function maxDeposit(address) external pure returns (uint256) {
        return 1 << 96;
    }

    /**
     * @notice Returns a conservative estimate of the maximum number of Vault shares that can be minted for `receiver`,
     * through a mint call.
     * @return The maximum number of Vault shares that can be minted
     *
     * @dev Should return the *precise* maximum. In this case that'd be on the order of 2**112 with weird constraints
     * coming from both `lastBalance` and `totalSupply`, which changes during interest accrual. Instead of doing
     * complicated math, we provide a constant conservative estimate of 2**96.
     * 
     * - MUST return a limited value if receiver is subject to some mint limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum number of shares that may be minted.
     * - MUST NOT revert.
     */
    function maxMint(address) external pure returns (uint256) {
        return 1 << 96;
    }

    /**
     * @notice Returns the maximum amount of `asset()` that can be withdrawn from the Vault by `owner`, through a
     * withdraw call.
     * @param owner The address that would burn Vault shares when withdrawing
     * @return The maximum amount of `asset()` that can be withdrawn
     *
     * @dev
     * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
     * - MUST NOT revert.
     */
    function maxWithdraw(address owner) external view returns (uint256) {
        uint256 a = convertToAssets(balanceOf[owner]);
        uint256 b = asset().balanceOf(address(this));
        return a < b ? a : b;
    }

    /**
     * @notice Returns the maximum number of Vault shares that can be redeemed in the Vault by `owner`, through a
     * redeem call.
     * @param owner The address that would burn Vault shares when redeeming
     * @return The maximum number of Vault shares that can be redeemed
     *
     * @dev
     * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
     * - MUST return balanceOf(owner) if owner is not subject to any withdrawal limit or timelock.
     * - MUST NOT revert.
     */
    function maxRedeem(address owner) external view returns (uint256) {
        uint256 a = balanceOf[owner];
        uint256 b = convertToShares(asset().balanceOf(address(this)));
        return a < b ? a : b;
    }
}
