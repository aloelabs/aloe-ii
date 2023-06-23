// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Clones} from "clones-with-immutable-args/Clones.sol";
import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {DEFAULT_ANTE, DEFAULT_N_SIGMA} from "./libraries/constants/Constants.sol";

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
        uint248 ante;
        uint8 nSigma;
    }

    VolatilityOracle public immutable ORACLE;

    IRateModel public immutable RATE_MODEL;

    ERC20 public immutable REWARDS_TOKEN;

    address public immutable lenderImplementation;

    /*//////////////////////////////////////////////////////////////
                             WORLD STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(IUniswapV3Pool => Market) public getMarket;

    mapping(IUniswapV3Pool => Parameters) public getParameters;

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

    constructor(VolatilityOracle oracle, IRateModel rateModel, ERC20 rewardsToken) {
        ORACLE = oracle;
        RATE_MODEL = rateModel;
        REWARDS_TOKEN = rewardsToken;

        lenderImplementation = address(new Lender(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                             WORLD CREATION
    //////////////////////////////////////////////////////////////*/

    function createMarket(IUniswapV3Pool pool) external {
        ORACLE.prepare(pool);

        address asset0 = pool.token0();
        address asset1 = pool.token1();

        bytes32 salt = keccak256(abi.encode(pool));
        Lender lender0 = Lender(lenderImplementation.cloneDeterministic({salt: salt, data: abi.encodePacked(asset0)}));
        Lender lender1 = Lender(lenderImplementation.cloneDeterministic({salt: salt, data: abi.encodePacked(asset1)}));

        lender0.initialize(RATE_MODEL, 8);
        lender1.initialize(RATE_MODEL, 8);

        Borrower borrowerImplementation = new Borrower(ORACLE, pool, lender0, lender1);

        getMarket[pool] = Market(lender0, lender1, borrowerImplementation);
        getParameters[pool] = Parameters(DEFAULT_ANTE, DEFAULT_N_SIGMA);
        emit CreateMarket(pool, lender0, lender1);
    }

    function createBorrower(IUniswapV3Pool pool, address owner) external returns (address account) {
        Market memory market = getMarket[pool];

        account = Clones.clone(address(market.borrowerImplementation));
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
        // Couriers cannot claim rewards because the accounting isn't quite correct for them -- we save gas
        // by omitting a `Rewards.updateUserState` call for the courier in `Lender._burn`
        require(!isCourier[msg.sender]);

        unchecked {
            uint256 count = lenders.length;
            for (uint256 i = 0; i < count; i++) {
                earned += lenders[i].claimRewards(msg.sender);
            }
        }

        REWARDS_TOKEN.safeTransfer(beneficiary, earned);
    }
}
