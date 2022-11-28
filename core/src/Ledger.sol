// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ImmutableArgs} from "clones-with-immutable-args/ImmutableArgs.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {FullMath} from "./libraries/FullMath.sol";

import {InterestModel} from "./InterestModel.sol";
import {Factory} from "./Factory.sol";

contract Ledger {
    using FixedPointMathLib for uint256;
    using FullMath for uint256;

    uint256 public constant ONE = 1e12;

    uint256 public constant BORROWS_SCALER = type(uint72).max * ONE; // uint72 is from borrowIndex type

    Factory public immutable FACTORY;

    address public immutable TREASURY;

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

    mapping(address => uint256) public borrows;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => uint256) public balanceOf;

    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    bytes32 internal initialDomainSeparator;

    uint256 internal initialChainId;

    mapping(address => uint256) public nonces;

    /*//////////////////////////////////////////////////////////////
                          GOVERNABLE PARAMETERS
    //////////////////////////////////////////////////////////////*/

    InterestModel public interestModel;

    uint8 public reserveFactor;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address treasury) {
        FACTORY = Factory(msg.sender);
        TREASURY = treasury;
    }

    /// @notice The address of the underlying token.
    function asset() public pure returns (ERC20) {
        return ERC20(ImmutableArgs.addr());
    }

    /// @notice The name of the banknote.
    function name() external view returns (string memory) {
        return string.concat("Aloe II ", asset().name());
    }

    /// @notice The symbol of the banknote.
    function symbol() external view returns (string memory) {
        return string.concat(asset().symbol(), "+");
    }

    /// @notice The number of decimals the banknote uses. Matches the underlying token.
    function decimals() external view returns (uint8) {
        return asset().decimals();
    }

    /**
     * @notice Gets basic lending information.
     * @return The sum of all banknote balances
     * @return The sum of all banknote balances, in underlying units (increases as interest accrues)
     * @return The sum of all outstanding debts, in underlying units (increases as interest accrues)
     */
    function stats() external view returns (uint256, uint256, uint256) {
        (Cache memory cache, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(_getCache());

        unchecked {
            return (newTotalSupply, inventory, (cache.borrowBase * cache.borrowIndex) / BORROWS_SCALER);
        }
    }

    function balanceOfUnderlying(address account) external view returns (uint256) {
        return convertToAssets(balanceOf[account]);
    }

    function balanceOfUnderlyingStored(address account) external view returns (uint256) {
        unchecked {
            return
                _convertToAssets({
                    shares: balanceOf[account],
                    inventory: lastBalance + (borrowBase * borrowIndex) / BORROWS_SCALER,
                    totalSupply_: totalSupply,
                    roundUp: false
                });
        }
    }

    function borrowBalance(address account) external view returns (uint256) {
        (Cache memory cache, , ) = _accrueInterestView(_getCache());
        return borrows[account].mulDivUp(cache.borrowIndex, BORROWS_SCALER);
    }

    function borrowBalanceStored(address account) external view returns (uint256) {
        return borrows[account].mulDivUp(borrowIndex, BORROWS_SCALER);
    }

    /*//////////////////////////////////////////////////////////////
                           ERC4626 ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view returns (uint256) {
        (, uint256 inventory, ) = _accrueInterestView(_getCache());
        return inventory;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(_getCache());
        return _convertToShares(assets, inventory, newTotalSupply, /* roundUp: */ false);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(_getCache());
        return _convertToAssets(shares, inventory, newTotalSupply, /* roundUp: */ false);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(_getCache());
        return _convertToAssets(shares, inventory, newTotalSupply, /* roundUp: */ true);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _accrueInterestView(_getCache());
        return _convertToShares(assets, inventory, newTotalSupply, /* roundUp: */ true);
    }

    /*//////////////////////////////////////////////////////////////
                    ERC4626 DEPOSIT/WITHDRAWAL LIMITS
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
        uint256 b = lastBalance;
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
        uint256 b = convertToShares(lastBalance);
        return a < b ? a : b;
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function DOMAIN_SEPARATOR() public returns (bytes32) {
        return block.chainid == initialChainId ? initialDomainSeparator : _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)"),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    function _accrueInterestView(Cache memory cache) internal view returns (Cache memory, uint256, uint256) {
        (uint256 oldInventory, uint256 accrualFactor, uint8 rf) = _getAccrualFactor(cache);
        if (accrualFactor == 0 || oldInventory == 0) return (cache, oldInventory, cache.totalSupply);

        // TODO sane constraints on accrualFactor WITH TESTS for when accrualFactor is reported to be massive
        unchecked {
            cache.borrowIndex = (cache.borrowIndex * (ONE + accrualFactor)) / ONE;
            cache.lastAccrualTime = 0; // 0 in storage means locked to reentrancy; 0 in `cache` means `borrowIndex` was updated

            uint256 newInventory = cache.lastBalance + (cache.borrowBase * cache.borrowIndex) / BORROWS_SCALER;

            uint256 newTotalSupply = cache.totalSupply.mulDiv(
                newInventory,
                newInventory - (newInventory - oldInventory) / rf
            );
            return (cache, newInventory, newTotalSupply);
        }
    }

    function _getAccrualFactor(
        Cache memory cache
    ) private view returns (uint256 inventory, uint256 accrualFactor, uint8 rf) {
        uint256 borrows;
        unchecked {
            borrows = (cache.borrowBase * cache.borrowIndex) / BORROWS_SCALER;
            inventory = cache.lastBalance + borrows;
        }

        if (cache.lastAccrualTime != block.timestamp && cache.borrowBase != 0) {
            // get `accrualFactor`, and since `interestModel` and `reserveFactor` are in the same slot, load both
            rf = reserveFactor;
            accrualFactor = interestModel.getAccrualFactor({
                elapsedTime: block.timestamp - cache.lastAccrualTime,
                utilization: uint256(1e18).mulDiv(borrows, inventory)
            });
        }
    }

    function _getCache() private view returns (Cache memory) {
        return Cache(totalSupply, lastBalance, lastAccrualTime, borrowBase, borrowIndex);
    }

    function _convertToShares(
        uint256 assets,
        uint256 inventory,
        uint256 totalSupply_,
        bool roundUp
    ) internal pure returns (uint256) {
        if (totalSupply_ == 0) return assets;

        uint256 shares = assets.mulDivDown(totalSupply_, inventory);
        if (roundUp && mulmod(assets, totalSupply_, inventory) > 0) shares++;

        return shares;
    }

    function _convertToAssets(
        uint256 shares,
        uint256 inventory,
        uint256 totalSupply_,
        bool roundUp
    ) internal pure returns (uint256) {
        if (totalSupply_ == 0) return shares;

        uint256 assets = shares.mulDivDown(inventory, totalSupply_);
        if (roundUp && mulmod(shares, inventory, totalSupply_) > 0) assets++;

        return assets;
    }
}
