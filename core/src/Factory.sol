// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {
    DEFAULT_ANTE,
    DEFAULT_N_SIGMA,
    DEFAULT_MANIPULATION_THRESHOLD_DIVISOR,
    DEFAULT_RESERVE_FACTOR,
    CONSTRAINT_N_SIGMA_MIN,
    CONSTRAINT_N_SIGMA_MAX,
    CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MIN,
    CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MAX,
    CONSTRAINT_RESERVE_FACTOR_MIN,
    CONSTRAINT_RESERVE_FACTOR_MAX,
    CONSTRAINT_ANTE_MAX,
    UNISWAP_AVG_WINDOW
} from "./libraries/constants/Constants.sol";

import {Borrower} from "./Borrower.sol";
import {Lender} from "./Lender.sol";
import {IRateModel} from "./RateModel.sol";
import {VolatilityOracle} from "./VolatilityOracle.sol";

/// @title Factory
/// @author Aloe Labs, Inc.
/// @dev "Test everything; hold fast what is good." - 1 Thessalonians 5:21
contract Factory {
    using ClonesWithImmutableArgs for address;
    using SafeTransferLib for ERC20;

    event CreateMarket(IUniswapV3Pool indexed pool, Lender lender0, Lender lender1);

    event CreateBorrower(IUniswapV3Pool indexed pool, address indexed owner, Borrower account);

    event EnrollCourier(uint32 indexed id, address indexed wallet, uint16 cut);

    event SetMarketConfig(IUniswapV3Pool indexed pool, MarketConfig config);

    // This `Factory` can create a `Market` for any Uniswap V3 pool
    struct Market {
        // The `Lender` of `token0` in the Uniswap pool
        Lender lender0;
        // The `Lender` of `token1` in the Uniswap pool
        Lender lender1;
        // The implementation to which all `Borrower` clones will point
        Borrower borrowerImplementation;
    }

    // Each `Market` has a set of borrowing `Parameters` to help manage risk
    struct Parameters {
        // The amount of Ether a `Borrower` must hold in order to borrow assets
        uint208 ante;
        // To avoid liquidation, a `Borrower` must be solvent at TWAP * e^{± nSigma * IV}
        uint8 nSigma;
        // Borrowing is paused when the manipulation metric > threshold; this scales the threshold up/down
        uint8 manipulationThresholdDivisor;
        // The time at which borrowing can resume
        uint32 pausedUntilTime;
    }

    // The set of all governable `Market` properties
    struct MarketConfig {
        // Described above
        uint208 ante;
        // Described above
        uint8 nSigma;
        // Described above
        uint8 manipulationThresholdDivisor;
        // The reserve factor for `market.lender0`, expressed as a reciprocal
        uint8 reserveFactor0;
        // The reserve factor for `market.lender1`, expressed as a reciprocal
        uint8 reserveFactor1;
        // The rate model for `market.lender0`
        IRateModel rateModel0;
        // The rate model for `market.lender1`
        IRateModel rateModel1;
    }

    // By enrolling as a `Courier`, frontends can earn a portion of their users' interest
    struct Courier {
        // The address that receives earnings whenever users withdraw
        address wallet;
        // The portion of users' interest to take, expressed in basis points
        uint16 cut;
    }

    /// @notice The only address that can propose new `MarketConfig`s and rewards programs
    address public immutable GOVERNOR;

    /// @notice The oracle to use for prices and implied volatility
    VolatilityOracle public immutable ORACLE;

    /// @notice The implementation to which all `Lender` clones will point
    address public immutable LENDER_IMPLEMENTATION;

    /// @notice A simple contract that deploys `Borrower`s to keep `Factory` bytecode size down
    BorrowerDeployer private immutable _BORROWER_DEPLOYER;

    /// @notice The rate model that `Lender`s will use when first created
    IRateModel public immutable DEFAULT_RATE_MODEL;

    /*//////////////////////////////////////////////////////////////
                             WORLD STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the `Market` addresses associated with a Uniswap V3 pool
    mapping(IUniswapV3Pool => Market) public getMarket;

    /// @notice Returns the borrowing `Parameters` associated with a Uniswap V3 pool
    mapping(IUniswapV3Pool => Parameters) public getParameters;

    /// @notice Returns the other `Lender` in the `Market` iff input is itself a `Lender`, otherwise 0
    mapping(address => address) public peer;

    /// @notice Returns whether the given address is a `Borrower` deployed by this `Factory`
    mapping(address => bool) public isBorrower;

    /*//////////////////////////////////////////////////////////////
                           INCENTIVE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The token in which rewards are paid out
    ERC20 public rewardsToken;

    /// @notice Returns the `Courier` for any given ID
    mapping(uint32 => Courier) public couriers;

    /// @notice Returns whether the given address has enrolled as a courier
    mapping(address => bool) public isCourier;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address governor,
        address reserve,
        VolatilityOracle oracle,
        BorrowerDeployer borrowerDeployer,
        IRateModel defaultRateModel
    ) {
        GOVERNOR = governor;
        ORACLE = oracle;
        LENDER_IMPLEMENTATION = address(new Lender(reserve));
        _BORROWER_DEPLOYER = borrowerDeployer;
        DEFAULT_RATE_MODEL = defaultRateModel;
    }

    /*//////////////////////////////////////////////////////////////
                               EMERGENCY
    //////////////////////////////////////////////////////////////*/

    function pause(IUniswapV3Pool pool, uint40 oracleSeed) external {
        (, bool seemsLegit) = getMarket[pool].borrowerImplementation.getPrices(oracleSeed);
        if (seemsLegit) return;

        unchecked {
            getParameters[pool].pausedUntilTime = uint32(block.timestamp) + UNISWAP_AVG_WINDOW;
        }
    }

    /*//////////////////////////////////////////////////////////////
                             WORLD CREATION
    //////////////////////////////////////////////////////////////*/

    function createMarket(IUniswapV3Pool pool) external {
        ORACLE.prepare(pool);

        address asset0 = pool.token0();
        address asset1 = pool.token1();

        // Deploy market-specific components
        bytes32 salt = keccak256(abi.encodePacked(pool));
        Lender lender0 = Lender(LENDER_IMPLEMENTATION.cloneDeterministic({salt: salt, data: abi.encodePacked(asset0)}));
        Lender lender1 = Lender(LENDER_IMPLEMENTATION.cloneDeterministic({salt: salt, data: abi.encodePacked(asset1)}));
        Borrower borrowerImplementation = _newBorrower(pool, lender0, lender1);

        // Store deployment addresses
        getMarket[pool] = Market(lender0, lender1, borrowerImplementation);
        peer[address(lender0)] = address(lender1);
        peer[address(lender1)] = address(lender0);

        // Initialize lenders and set default market config
        lender0.initialize();
        lender1.initialize();
        _setMarketConfig(
            pool,
            MarketConfig(
                DEFAULT_ANTE,
                DEFAULT_N_SIGMA,
                DEFAULT_MANIPULATION_THRESHOLD_DIVISOR,
                DEFAULT_RESERVE_FACTOR,
                DEFAULT_RESERVE_FACTOR,
                DEFAULT_RATE_MODEL,
                DEFAULT_RATE_MODEL
            ),
            0
        );

        emit CreateMarket(pool, lender0, lender1);
    }

    function createBorrower(IUniswapV3Pool pool, address owner, bytes12 salt) external returns (Borrower borrower) {
        Market memory market = getMarket[pool];

        borrower = Borrower(
            address(market.borrowerImplementation).cloneDeterministic({
                salt: bytes32(bytes.concat(bytes20(msg.sender), salt)),
                data: abi.encodePacked(owner)
            })
        );
        isBorrower[address(borrower)] = true;

        market.lender0.whitelist(address(borrower));
        market.lender1.whitelist(address(borrower));

        emit CreateBorrower(pool, owner, borrower);
    }

    /*//////////////////////////////////////////////////////////////
                               INCENTIVES
    //////////////////////////////////////////////////////////////*/

    function claimRewards(Lender[] calldata lenders, address beneficiary) external returns (uint256 earned) {
        // Couriers cannot claim rewards because the accounting isn't quite correct for them. Specifically, we
        // save gas by omitting a `Rewards.updateUserState` call for the courier in `Lender._burn`
        require(!isCourier[msg.sender]);

        unchecked {
            uint256 count = lenders.length;
            for (uint256 i = 0; i < count; i++) {
                // Make sure it is, in fact, a `Lender`
                require(peer[address(lenders[i])] != address(0));
                earned += lenders[i].claimRewards(msg.sender);
            }
        }

        rewardsToken.safeTransfer(beneficiary, earned);
    }

    /**
     * @notice Enrolls `msg.sender` in the referral program. This allows frontends/wallets/apps to
     * credit themselves for a given user's deposit, and receive a portion of their interest. Note
     * that after enrolling, `msg.sender` will not be eligible for `REWARDS_TOKEN` rewards.
     * @dev See `Lender.creditCourier`
     * @param id A unique identifier for the courier
     * @param cut The portion of interest the courier will receive. Should be in the range [0, 10000),
     * with 10000 being 100%.
     */
    function enrollCourier(uint32 id, uint16 cut) external {
        // Requirements:
        // - `id != 0` because 0 is reserved as the no-courier case
        // - `cut != 0 && cut < 10_000` just means between 0 and 100%
        require(id != 0 && cut != 0 && cut < 10_000);
        // Once an `id` has been enrolled, its info can't be changed
        require(couriers[id].cut == 0);

        couriers[id] = Courier(msg.sender, cut);
        isCourier[msg.sender] = true;

        emit EnrollCourier(id, msg.sender, cut);
    }

    /*//////////////////////////////////////////////////////////////
                               GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    function governRewardsToken(ERC20 rewardsToken_) external {
        require(msg.sender == GOVERNOR && address(rewardsToken) == address(0));
        rewardsToken = rewardsToken_;
    }

    function governRewardsRate(Lender lender, uint56 rate) external {
        require(msg.sender == GOVERNOR);
        lender.setRewardsRate(rate);
    }

    function governMarketConfig(IUniswapV3Pool pool, MarketConfig memory config) external {
        require(msg.sender == GOVERNOR);

        require(
            // ante: max
            (config.ante <= CONSTRAINT_ANTE_MAX) &&
                // nSigma: min, max
                (CONSTRAINT_N_SIGMA_MIN <= config.nSigma && config.nSigma <= CONSTRAINT_N_SIGMA_MAX) &&
                // manipulationThresholdDivisor: min, max
                (CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MIN <= config.manipulationThresholdDivisor &&
                    config.manipulationThresholdDivisor <= CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MAX) &&
                // reserveFactor0: min, max
                (CONSTRAINT_RESERVE_FACTOR_MIN <= config.reserveFactor0 &&
                    config.reserveFactor0 <= CONSTRAINT_RESERVE_FACTOR_MAX) &&
                // reserveFactor1: min, max
                (CONSTRAINT_RESERVE_FACTOR_MIN <= config.reserveFactor1 &&
                    config.reserveFactor1 <= CONSTRAINT_RESERVE_FACTOR_MAX),
            "Aloe: constraints"
        );

        _setMarketConfig(pool, config, getParameters[pool].pausedUntilTime);
    }

    function _setMarketConfig(IUniswapV3Pool pool, MarketConfig memory config, uint32 pausedUntilTime) private {
        getParameters[pool] = Parameters({
            ante: config.ante,
            nSigma: config.nSigma,
            manipulationThresholdDivisor: config.manipulationThresholdDivisor,
            pausedUntilTime: pausedUntilTime
        });

        Market memory market = getMarket[pool];
        market.lender0.setRateModelAndReserveFactor(config.rateModel0, config.reserveFactor0);
        market.lender1.setRateModelAndReserveFactor(config.rateModel1, config.reserveFactor1);

        emit SetMarketConfig(pool, config);
    }

    function _newBorrower(IUniswapV3Pool pool, Lender lender0, Lender lender1) private returns (Borrower) {
        (bool success, bytes memory data) = address(_BORROWER_DEPLOYER).delegatecall(
            abi.encodeCall(BorrowerDeployer.deploy, (ORACLE, pool, lender0, lender1))
        );
        require(success);
        return abi.decode(data, (Borrower));
    }
}

contract BorrowerDeployer {
    function deploy(
        VolatilityOracle oracle,
        IUniswapV3Pool pool,
        Lender lender0,
        Lender lender1
    ) external returns (Borrower) {
        return new Borrower(oracle, pool, lender0, lender1);
    }
}
