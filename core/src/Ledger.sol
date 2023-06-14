// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ImmutableArgs} from "clones-with-immutable-args/ImmutableArgs.sol";
import {IERC165} from "openzeppelin-contracts/interfaces/IERC165.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {BORROWS_SCALER, ONE} from "./libraries/constants/Constants.sol";
import {Q112} from "./libraries/constants/Q.sol";
import {Rewards} from "./libraries/Rewards.sol";

import {RateModel} from "./RateModel.sol";

contract Ledger {
    using FixedPointMathLib for uint256;

    address public immutable FACTORY;

    address public immutable RESERVE;

    ERC20 public immutable REWARDS_TOKEN;

    struct Cache {
        uint256 totalSupply;
        uint256 lastBalance;
        uint256 lastAccrualTime;
        uint256 borrowBase;
        uint256 borrowIndex;
    }

    /*//////////////////////////////////////////////////////////////
                             LENDER STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Doesn't include reserve inflation. If you want that, use `stats()`
    uint112 public totalSupply;

    uint112 public lastBalance;

    uint32 public lastAccrualTime;

    uint184 public borrowBase;

    uint72 public borrowIndex;

    mapping(address => uint256) public borrows;

    /*//////////////////////////////////////////////////////////////
                             ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Highest 32 bits are the referral code, next 112 are the principle, lowest 112 are the shares.
    mapping(address => uint256) public balances;

    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                            ERC2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    bytes32 internal initialDomainSeparator;

    uint256 internal initialChainId;

    mapping(address => uint256) public nonces;

    /*//////////////////////////////////////////////////////////////
                           INCENTIVE STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Courier {
        address wallet;
        uint16 cut;
    }

    mapping(uint32 => Courier) public couriers;

    /*//////////////////////////////////////////////////////////////
                         GOVERNABLE PARAMETERS
    //////////////////////////////////////////////////////////////*/

    RateModel public rateModel;

    uint8 public reserveFactor;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address reserve, ERC20 rewardsToken) {
        FACTORY = msg.sender;
        RESERVE = reserve;
        REWARDS_TOKEN = rewardsToken;
    }

    /// @notice Returns true if this contract implements the interface defined by `interfaceId`
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC4626).interfaceId;
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

    /// @notice The address of the underlying token.
    function asset() public pure returns (ERC20) {
        return ERC20(ImmutableArgs.addr());
    }

    /// @notice The domain separator for EIP-2612
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == initialChainId ? initialDomainSeparator : _computeDomainSeparator();
    }

    /**
     * @notice Gets basic lending statistics as if `accrueInterest` were just called.
     * @return The updated `borrowIndex`
     * @return The sum of all banknote balances, in underlying units (i.e. `totalAssets`)
     * @return The sum of all outstanding debts, in underlying units
     * @return The sum of all banknote balances. Will differ from `totalSupply` due to reserves inflation
     */
    function stats() external view returns (uint72, uint256, uint256, uint256) {
        (Cache memory cache, uint256 inventory, uint256 newTotalSupply) = _previewInterest(_getCache());

        unchecked {
            return (
                uint72(cache.borrowIndex),
                inventory,
                (cache.borrowBase * cache.borrowIndex) / BORROWS_SCALER,
                newTotalSupply
            );
        }
    }

    function rewardsRate() external view returns (uint112 rate) {
        (Rewards.Storage storage s, ) = Rewards.load();
        rate = s.poolState.rate;
    }

    function rewardsOf(address account) external view returns (uint144) {
        (Rewards.Storage storage s, uint144 a) = Rewards.load();
        return Rewards.previewUserState(s, a, account, balanceOf(account)).earned;
    }

    function courierOf(address account) external view returns (uint32) {
        return uint32(balances[account] >> 224);
    }

    function principleOf(address account) external view returns (uint256) {
        return (balances[account] >> 112) % Q112;
    }

    /// @notice The number of shares held by `account`
    function balanceOf(address account) public view returns (uint256) {
        return balances[account] % Q112;
    }

    /**
     * @notice The amount of `asset` owed to `account` after accruing the latest interest, i.e.
     * the value that `maxWithdraw` would return if outstanding borrows weren't a constraint.
     * Fees owed to couriers are automatically subtracted from this value in real-time, but couriers
     * themselves won't receive earnings until users `redeem` or `withdraw`.
     * @dev Because of the fees, ∑underlyingBalances != totalAssets
     */
    function underlyingBalance(address account) external view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _previewInterest(_getCache());
        return _convertToAssets(_nominalShares(account, inventory, newTotalSupply), inventory, newTotalSupply, false);
    }

    /**
     * @notice The amount of `asset` owed to `account` before accruing the latest interest.
     * See `underlyingBalance` for details.
     * @dev An underestimate; more gas efficient than `underlyingBalance`
     */
    function underlyingBalanceStored(address account) external view returns (uint256) {
        unchecked {
            uint256 inventory = lastBalance + (uint256(borrowBase) * borrowIndex) / BORROWS_SCALER;
            uint256 totalSupply_ = totalSupply;

            return _convertToAssets(_nominalShares(account, inventory, totalSupply_), inventory, totalSupply_, false);
        }
    }

    function borrowBalance(address account) external view returns (uint256) {
        uint256 b = borrows[account];
        if (b == 0) return 0;

        (Cache memory cache, , ) = _previewInterest(_getCache());
        unchecked {
            return ((b - 1) * cache.borrowIndex) / BORROWS_SCALER;
        }
    }

    function borrowBalanceStored(address account) external view returns (uint256) {
        uint256 b = borrows[account];
        if (b == 0) return 0;

        unchecked {
            return ((b - 1) * borrowIndex) / BORROWS_SCALER;
        }
    }

    /*//////////////////////////////////////////////////////////////
                           ERC4626 ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The total amount of `asset` under management
     * @dev `convertToShares(totalAssets()) != totalSupply()` due to reserves inflation. If you need
     * the up-to-date supply, use `stats()`
     */
    function totalAssets() external view returns (uint256) {
        (, uint256 inventory, ) = _previewInterest(_getCache());
        return inventory;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _previewInterest(_getCache());
        return _convertToShares(assets, inventory, newTotalSupply, /* roundUp: */ false);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _previewInterest(_getCache());
        return _convertToAssets(shares, inventory, newTotalSupply, /* roundUp: */ false);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _previewInterest(_getCache());
        return _convertToAssets(shares, inventory, newTotalSupply, /* roundUp: */ true);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        (, uint256 inventory, uint256 newTotalSupply) = _previewInterest(_getCache());
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
        return convertToAssets(this.maxRedeem(owner));
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
        (Cache memory cache, uint256 inventory, uint256 newTotalSupply) = _previewInterest(_getCache());

        uint256 a = _nominalShares(owner, inventory, newTotalSupply);
        uint256 b = _convertToShares(cache.lastBalance, inventory, newTotalSupply, false);

        return a < b ? a : b;
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

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

    function _previewInterest(Cache memory cache) internal view returns (Cache memory, uint256, uint256) {
        unchecked {
            uint256 oldBorrows = (cache.borrowBase * cache.borrowIndex) / BORROWS_SCALER;
            uint256 oldInventory = cache.lastBalance + oldBorrows;

            if (cache.lastAccrualTime == block.timestamp || oldBorrows == 0) {
                return (cache, oldInventory, cache.totalSupply);
            }

            uint8 rf = reserveFactor;
            uint256 accrualFactor = rateModel.getAccrualFactor({
                elapsedTime: block.timestamp - cache.lastAccrualTime,
                utilization: (1e18 * oldBorrows) / oldInventory
            });

            cache.borrowIndex = (cache.borrowIndex * accrualFactor) / ONE;
            cache.lastAccrualTime = 0; // 0 in storage means locked to reentrancy; 0 in `cache` means `borrowIndex` was updated

            uint256 newInventory = cache.lastBalance + (cache.borrowBase * cache.borrowIndex) / BORROWS_SCALER;
            uint256 newTotalSupply = Math.mulDiv(
                cache.totalSupply,
                newInventory,
                newInventory - (newInventory - oldInventory) / rf
            );
            return (cache, newInventory, newTotalSupply);
        }
    }

    function _convertToShares(
        uint256 assets,
        uint256 inventory,
        uint256 totalSupply_,
        bool roundUp
    ) internal pure returns (uint256) {
        if (totalSupply_ == 0) return assets;
        return roundUp ? assets.mulDivUp(totalSupply_, inventory) : assets.mulDivDown(totalSupply_, inventory);
    }

    function _convertToAssets(
        uint256 shares,
        uint256 inventory,
        uint256 totalSupply_,
        bool roundUp
    ) internal pure returns (uint256) {
        if (totalSupply_ == 0) return shares;
        return roundUp ? shares.mulDivUp(inventory, totalSupply_) : shares.mulDivDown(inventory, totalSupply_);
    }

    function _nominalShares(
        address account,
        uint256 inventory,
        uint256 totalSupply_
    ) private view returns (uint256 balance) {
        unchecked {
            uint256 data = balances[account];
            balance = data % Q112;

            uint32 id = uint32(data >> 224);
            if (id != 0) {
                uint256 principleAssets = (data >> 112) % Q112;
                uint256 principleShares = _convertToShares(principleAssets, inventory, totalSupply_, true);

                if (balance > principleShares) {
                    uint256 fee = ((balance - principleShares) * couriers[id].cut) / 10_000;
                    balance -= fee;
                }
            }
        }
    }

    function _getCache() private view returns (Cache memory) {
        return Cache(totalSupply, lastBalance, lastAccrualTime, borrowBase, borrowIndex);
    }
}
