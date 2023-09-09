// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Clones} from "clones-with-immutable-args/Clones.sol";
import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {
    DEFAULT_ANTE,
    DEFAULT_N_SIGMA,
    DEFAULT_RESERVE_FACTOR,
    CONSTRAINT_N_SIGMA_MIN,
    CONSTRAINT_N_SIGMA_MAX,
    CONSTRAINT_RESERVE_FACTOR_MIN,
    CONSTRAINT_RESERVE_FACTOR_MAX,
    CONSTRAINT_ANTE_MAX,
    CONSTRAINT_PAUSE_INTERVAL_MAX,
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

    event CreateBorrower(IUniswapV3Pool indexed pool, address indexed owner, address account);

    event EnrollCourier(uint32 indexed id, address indexed wallet, uint16 cut);

    struct Market {
        Lender lender0;
        Lender lender1;
        Borrower borrowerImplementation;
    }

    struct Parameters {
        uint216 ante;
        uint8 nSigma;
        uint32 pausedUntilTime;
    }

    struct MarketConfig {
        Parameters parameters;
        IRateModel rateModel0;
        IRateModel rateModel1;
        uint8 reserveFactor0;
        uint8 reserveFactor1;
    }

    address public immutable GOVERNOR;

    VolatilityOracle public immutable ORACLE;

    address public immutable LENDER_IMPLEMENTATION;

    IRateModel public immutable DEFAULT_RATE_MODEL;

    ERC20 public rewardsToken;

    /*//////////////////////////////////////////////////////////////
                             WORLD STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(IUniswapV3Pool => Market) public getMarket;

    mapping(IUniswapV3Pool => Parameters) public getParameters;

    mapping(address => bool) public isLender;

    mapping(address => bool) public isBorrower;

    /*//////////////////////////////////////////////////////////////
                           INCENTIVE STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Courier {
        address wallet;
        uint16 cut;
    }

    mapping(uint32 => Courier) public couriers;

    mapping(address => bool) public isCourier;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address governor, address reserve, VolatilityOracle oracle, IRateModel defaultRateModel) {
        GOVERNOR = governor;
        ORACLE = oracle;
        LENDER_IMPLEMENTATION = address(new Lender(reserve));
        DEFAULT_RATE_MODEL = defaultRateModel;
    }

    function pause(IUniswapV3Pool pool) external {
        require(isBorrower[msg.sender]);
        unchecked {
            getParameters[pool].pausedUntilTime = uint32(block.timestamp) + UNISWAP_AVG_WINDOW;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            WORLD MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function createMarket(IUniswapV3Pool pool) external {
        ORACLE.prepare(pool);

        address asset0 = pool.token0();
        address asset1 = pool.token1();

        // Deploy market-specific components
        bytes32 salt = keccak256(abi.encodePacked(pool));
        Lender lender0 = Lender(LENDER_IMPLEMENTATION.cloneDeterministic({salt: salt, data: abi.encodePacked(asset0)}));
        Lender lender1 = Lender(LENDER_IMPLEMENTATION.cloneDeterministic({salt: salt, data: abi.encodePacked(asset1)}));
        Borrower borrowerImplementation = new Borrower(ORACLE, pool, lender0, lender1);

        // Store deployment addresses
        getMarket[pool] = Market(lender0, lender1, borrowerImplementation);
        isLender[address(lender0)] = true;
        isLender[address(lender1)] = true;

        // Initialize lenders and set default market config
        lender0.initialize();
        lender1.initialize();
        _setMarketConfig(
            pool,
            MarketConfig(
                Parameters(DEFAULT_ANTE, DEFAULT_N_SIGMA, 0),
                DEFAULT_RATE_MODEL,
                DEFAULT_RATE_MODEL,
                DEFAULT_RESERVE_FACTOR,
                DEFAULT_RESERVE_FACTOR
            )
        );

        emit CreateMarket(pool, lender0, lender1);
    }

    function createBorrower(IUniswapV3Pool pool, address owner) external returns (address payable account) {
        Market memory market = getMarket[pool];

        account = payable(Clones.clone(address(market.borrowerImplementation)));
        Borrower(account).initialize(owner);
        isBorrower[account] = true;

        market.lender0.whitelist(account);
        market.lender1.whitelist(account);

        emit CreateBorrower(pool, owner, account);
    }

    /*//////////////////////////////////////////////////////////////
                               REFERRALS
    //////////////////////////////////////////////////////////////*/

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
                                REWARDS
    //////////////////////////////////////////////////////////////*/

    function claimRewards(Lender[] calldata lenders, address beneficiary) external returns (uint256 earned) {
        // Couriers cannot claim rewards because the accounting isn't quite correct for them. Specifically, we
        // save gas by omitting a `Rewards.updateUserState` call for the courier in `Lender._burn`
        require(!isCourier[msg.sender]);

        unchecked {
            uint256 count = lenders.length;
            for (uint256 i = 0; i < count; i++) {
                assert(isLender[address(lenders[i])]);
                earned += lenders[i].claimRewards(msg.sender);
            }
        }

        rewardsToken.safeTransfer(beneficiary, earned);
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

    function governMarketConfig(IUniswapV3Pool pool, MarketConfig memory marketConfig) external {
        require(msg.sender == GOVERNOR);

        require(
            // nSigma: min, max
            (CONSTRAINT_N_SIGMA_MIN <= marketConfig.parameters.nSigma &&
                marketConfig.parameters.nSigma <= CONSTRAINT_N_SIGMA_MAX) &&
                // ante: max
                (marketConfig.parameters.ante <= CONSTRAINT_ANTE_MAX) &&
                // pauseUntilTime: max
                (marketConfig.parameters.pausedUntilTime <= block.timestamp + CONSTRAINT_PAUSE_INTERVAL_MAX) &&
                // reserveFactor0: min, max
                (CONSTRAINT_RESERVE_FACTOR_MIN <= marketConfig.reserveFactor0 &&
                    marketConfig.reserveFactor0 <= CONSTRAINT_RESERVE_FACTOR_MAX) &&
                // reserveFactor1: min, max
                (CONSTRAINT_RESERVE_FACTOR_MIN <= marketConfig.reserveFactor1 &&
                    marketConfig.reserveFactor1 <= CONSTRAINT_RESERVE_FACTOR_MAX),
            "Aloe: constraints"
        );

        _setMarketConfig(pool, marketConfig);
    }

    function _setMarketConfig(IUniswapV3Pool pool, MarketConfig memory marketConfig) private {
        getParameters[pool] = marketConfig.parameters;

        Market memory market = getMarket[pool];
        market.lender0.setRateModelAndReserveFactor(marketConfig.rateModel0, marketConfig.reserveFactor0);
        market.lender1.setRateModelAndReserveFactor(marketConfig.rateModel1, marketConfig.reserveFactor1);
    }
}
