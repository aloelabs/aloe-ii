// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IUniswapV3MintCallback} from "v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {LIQUIDATION_GRACE_PERIOD} from "./libraries/constants/Constants.sol";
import {Q128} from "./libraries/constants/Q.sol";
import {BalanceSheet, Assets, Prices} from "./libraries/BalanceSheet.sol";
import {LiquidityAmounts} from "./libraries/LiquidityAmounts.sol";
import {mulDiv128} from "./libraries/MulDiv.sol";
import {Positions} from "./libraries/Positions.sol";
import {TickMath} from "./libraries/TickMath.sol";

import {Factory} from "./Factory.sol";
import {Lender} from "./Lender.sol";

interface ILiquidator {
    receive() external payable;

    function swap1For0(bytes calldata data, uint256 received1, uint256 expected0) external;

    function swap0For1(bytes calldata data, uint256 received0, uint256 expected1) external;
}

interface IManager {
    function callback(bytes calldata data, address owner) external returns (uint144 positions);
}

/// @title Borrower
/// @author Aloe Labs, Inc.
/// @dev "Test everything; hold fast what is good." - 1 Thessalonians 5:21
contract Borrower is IUniswapV3MintCallback {
    using SafeTransferLib for ERC20;
    using Positions for int24[6];

    /**
     * @notice Most liquidations involve swapping one asset for another. To incentivize such swaps (even in
     * volatile markets) liquidators are rewarded with a 5% bonus. To avoid paying that bonus to liquidators,
     * the account owner can listen for this event. Once it's emitted, they have 2 minutes to bring the
     * account back to health. If they fail, the liquidation will proceed.
     * @dev Fortuitous price movements and/or direct `Lender.repay` can bring the account back to health and
     * nullify the immediate liquidation threat, but they will not clear the warning. This means that next
     * time the account is unhealthy, liquidators might skip `warn` and `liquidate` right away. To clear the
     * warning and return to a "clean" state, make sure to call `modify` -- even if the callback is a no-op.
     * @dev The deadline for regaining health (avoiding liquidation) is given by `slot0.unleashLiquidationTime`.
     * If this value is 0, the account is in the aforementioned "clean" state.
     */
    event Warn();

    /**
     * @notice Emitted when the account gets `liquidate`d
     * @param repay0 The amount of `TOKEN0` that was repaid
     * @param repay1 The amount of `TOKEN1` that was repaid
     * @param incentive1 The value of the swap bonus given to the liquidator, expressed in terms of `TOKEN1`
     * @param priceX128 The price at which the liquidation took place
     */
    event Liquidate(uint256 repay0, uint256 repay1, uint256 incentive1, uint256 priceX128);

    /// @notice The factory that created this contract
    Factory public immutable FACTORY;

    /// @notice The Uniswap pair in which the vault will manage positions
    IUniswapV3Pool public immutable UNISWAP_POOL;

    /// @notice The first token of the Uniswap pair
    ERC20 public immutable TOKEN0;

    /// @notice The second token of the Uniswap pair
    ERC20 public immutable TOKEN1;

    /// @notice The lender of `TOKEN0`
    Lender public immutable LENDER0;

    /// @notice The lender of `TOKEN1`
    Lender public immutable LENDER1;

    enum State {
        Ready,
        Locked,
        InModifyCallback
    }

    struct Slot0 {
        address owner;
        uint88 unleashLiquidationTime;
        State state;
    }

    Slot0 public slot0;

    int24[6] public positions;

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR & INITIALIZER
    //////////////////////////////////////////////////////////////*/

    constructor(IUniswapV3Pool pool, Lender lender0, Lender lender1) {
        FACTORY = Factory(msg.sender);
        UNISWAP_POOL = pool;
        LENDER0 = lender0;
        LENDER1 = lender1;

        TOKEN0 = lender0.asset();
        TOKEN1 = lender1.asset();

        require(pool.token0() == address(TOKEN0));
        require(pool.token1() == address(TOKEN1));
    }

    receive() external payable {}

    function initialize(address owner) external {
        require(slot0.owner == address(0));
        slot0.owner = owner;
    }

    function rescue(ERC20 token) external {
        require(token != TOKEN0 && token != TOKEN1);
        token.safeTransfer(slot0.owner, token.balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                           MAIN ENTRY POINTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Warns the borrower that they're about to be liquidated. NOTE: Liquidators are only
     * forced to call this in cases where the 5% swap bonus is up for grabs.
     * @param oracleSeed The indices of `UNISWAP_POOL.observations` where we start our search for
     * the 30-minute-old (lowest 16 bits) and 60-minute-old (next 16 bits) observations when getting
     * TWAPs. If any of the highest 8 bits are set, we fallback to binary search.
     */
    function warn(uint40 oracleSeed) external {
        // Load `slot0` from storage. We don't use `_loadSlot0` here because the `require` is different
        uint256 slot0_;
        assembly ("memory-safe") {
            slot0_ := sload(slot0.slot)
        }
        // Equivalent to `slot0.state == State.Ready && slot0.unleashLiquidationTime == 0`
        require(slot0_ >> 160 == 0);

        {
            // Fetch prices from oracle
            Prices memory prices = FACTORY.getPrices(UNISWAP_POOL, oracleSeed);
            // Tally assets without actually withdrawing Uniswap positions
            Assets memory assets = _getAssets(positions.read(), prices, false);
            // Fetch liabilities from lenders
            (uint256 liabilities0, uint256 liabilities1) = _getLiabilities();
            // Ensure only unhealthy accounts get warned
            require(!BalanceSheet.isHealthy(prices, assets, liabilities0, liabilities1), "Aloe: healthy");
        }

        unchecked {
            _saveSlot0(slot0_, (block.timestamp + LIQUIDATION_GRACE_PERIOD) << 160);
        }
        emit Warn();
    }

    /**
     * @notice Liquidates the borrower, using all available assets to pay down liabilities. If
     * some or all of the payment cannot be made in-kind, `callee` is expected to swap one asset
     * for the other at a venue of their choosing. NOTE: Branches involving callbacks will fail
     * until the borrower has been `warn`ed and the grace period has expired.
     * @dev As a baseline, `callee` receives `address(this).balance / strain` ETH. This amount is
     * intended to cover transaction fees. If the liquidation involves a swap callback, `callee`
     * receives a 5% bonus denominated in the surplus token. In other words, if the two numeric
     * callback arguments were denominated in the same asset, the first argument would be 5% larger.
     * @param callee A smart contract capable of swapping `TOKEN0` for `TOKEN1` and vice versa
     * @param data Encoded parameters that get forwarded to `callee` callbacks
     * @param strain Almost always set to `1` to pay off all debt and receive maximum reward. If
     * liquidity is thin and swap price impact would be too large, you can use higher values to
     * reduce swap size and make it easier for `callee` to do its job. `2` would be half swap size,
     * `3` one third, and so on.
     * @param oracleSeed The indices of `UNISWAP_POOL.observations` where we start our search for
     * the 30-minute-old (lowest 16 bits) and 60-minute-old (next 16 bits) observations when getting
     * TWAPs. If any of the highest 8 bits are set, we fallback to binary search.
     */
    function liquidate(ILiquidator callee, bytes calldata data, uint256 strain, uint40 oracleSeed) external {
        uint256 slot0_ = _loadSlot0();
        _saveSlot0(slot0_, _formatted(State.Locked));

        // Fetch prices from oracle
        Prices memory prices = FACTORY.getPrices(UNISWAP_POOL, oracleSeed);

        uint256 liabilities0;
        uint256 liabilities1;

        uint256 incentive1;
        uint256 priceX128;

        {
            // Withdraw Uniswap positions while tallying assets
            Assets memory assets = _getAssets(positions.read(), prices, true);
            // Fetch liabilities from lenders
            (liabilities0, liabilities1) = _getLiabilities();
            // Calculate liquidation incentive
            (incentive1, priceX128) = BalanceSheet.computeLiquidationIncentive(
                assets.fixed0 + assets.fluid0C, // total assets0 at `prices.c` (the TWAP)
                assets.fixed1 + assets.fluid1C, // total assets1 at `prices.c` (the TWAP)
                liabilities0,
                liabilities1,
                prices.c
            );
            // Ensure only unhealthy accounts can be liquidated
            require(!BalanceSheet.isHealthy(prices, assets, liabilities0, liabilities1, incentive1), "Aloe: healthy");
        }

        // NOTE: The health check values assets at the TWAP and is difficult to manipulate. However,
        // the instantaneous price does impact what tokens we receive when burning Uniswap positions.
        // As such, additional calls to `TOKEN0.balanceOf` and `TOKEN1.balanceOf` are required for
        // precise inventory, and we take care not to increase `incentive1`.

        unchecked {
            // Figure out what portion of liabilities can be repaid using existing assets
            uint256 repayable0 = Math.min(liabilities0, TOKEN0.balanceOf(address(this)));
            uint256 repayable1 = Math.min(liabilities1, TOKEN1.balanceOf(address(this)));

            // See what remains (similar to "shortfall" in BalanceSheet)
            liabilities0 -= repayable0;
            liabilities1 -= repayable1;

            // Decide whether to swap or not
            bool shouldSwap;
            assembly ("memory-safe") {
                // If both are zero or neither is zero, there's nothing more to do
                shouldSwap := xor(gt(liabilities0, 0), gt(liabilities1, 0))
                // Divide by `strain` and check again. This second check can generate false positives in cases
                // where one division (not both) floors to 0, which is why we `and()` with the check above.
                liabilities0 := div(liabilities0, strain)
                liabilities1 := div(liabilities1, strain)
                shouldSwap := and(shouldSwap, xor(gt(liabilities0, 0), gt(liabilities1, 0)))
                // If not swapping, set `incentive1 = 0`
                incentive1 := mul(shouldSwap, incentive1)
            }

            if (shouldSwap) {
                uint256 unleashTime = slot0_ >> 160;
                require(0 < unleashTime && unleashTime < block.timestamp, "Aloe: grace");

                incentive1 /= strain;
                if (liabilities0 > 0) {
                    // NOTE: This value is not constrained to `TOKEN1.balanceOf(address(this))`, so liquidators
                    // are responsible for setting `strain` such that the transfer doesn't revert. This shouldn't
                    // be an issue unless the borrower has already started accruing bad debt.
                    uint256 available1 = mulDiv128(liabilities0, priceX128) + incentive1;

                    TOKEN1.safeTransfer(address(callee), available1);
                    callee.swap1For0(data, available1, liabilities0);

                    repayable0 += liabilities0;
                } else {
                    // NOTE: This value is not constrained to `TOKEN0.balanceOf(address(this))`, so liquidators
                    // are responsible for setting `strain` such that the transfer doesn't revert. This shouldn't
                    // be an issue unless the borrower has already started accruing bad debt.
                    uint256 available0 = Math.mulDiv(liabilities1 + incentive1, Q128, priceX128);

                    TOKEN0.safeTransfer(address(callee), available0);
                    callee.swap0For1(data, available0, liabilities1);

                    repayable1 += liabilities1;
                }
            }

            _repay(repayable0, repayable1);
            _saveSlot0(slot0_ % (1 << 160), _formatted(State.Ready));

            payable(callee).transfer(address(this).balance / strain);
            emit Liquidate(repayable0, repayable1, incentive1, priceX128);
        }
    }

    /**
     * @notice Allows the owner to manage their account by handing control to some `callee`. Inside the
     * callback `callee` has access to all sub-commands (`uniswapDeposit`, `uniswapWithdraw`, `transfer`,
     * `borrow`, `repay`, and `withdrawAnte`). Whatever `callee` does, the account MUST be healthy
     * after the callback.
     * @param callee The smart contract that will get temporary control of this account
     * @param data Encoded parameters that get forwarded to `callee`
     * @param oracleSeed The indices of `UNISWAP_POOL.observations` where we start our search for
     * the 30-minute-old (lowest 16 bits) and 60-minute-old (next 16 bits) observations when getting
     * TWAPs. If any of the highest 8 bits are set, we fallback to binary search.
     */
    function modify(IManager callee, bytes calldata data, uint40 oracleSeed) external payable {
        require(_loadSlot0() % (1 << 160) == uint160(msg.sender), "Aloe: only owner");

        _saveSlot0(uint160(msg.sender), _formatted(State.InModifyCallback));
        int24[] memory positions_ = positions.write(callee.callback(data, msg.sender));
        _saveSlot0(uint160(msg.sender), _formatted(State.Ready));

        (uint256 liabilities0, uint256 liabilities1) = _getLiabilities();
        unchecked {
            if (liabilities0 + liabilities1 > 0) {
                // (Prices memory prices, bool isAllowedToBorrow) = FACTORY.getBorrowerPacket(UNISWAP_POOL, oracleSeed);
                // require(isAllowedToBorrow, "Aloe: missing ante / sus price");
                Prices memory prices = FACTORY.getBorrowerPacket(UNISWAP_POOL, oracleSeed);

                Assets memory assets = _getAssets(positions_, prices, false); // TODO: make sure I wasn't relying on _getAssets logic to check stuff, for example, that Uniswap positions are formatted correctly
                require(BalanceSheet.isHealthy(prices, assets, liabilities0, liabilities1), "Aloe: unhealthy");
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              SUB-COMMANDS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Callback for Uniswap V3 pool; necessary for `uniswapDeposit` to work
     * @param amount0 The amount of `TOKEN0` owed to the `UNISWAP_POOL`
     * @param amount1 The amount of `TOKEN1` owed to the `UNISWAP_POOL`
     */
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == address(UNISWAP_POOL));

        if (amount0 > 0) TOKEN0.safeTransfer(msg.sender, amount0);
        if (amount1 > 0) TOKEN1.safeTransfer(msg.sender, amount1);
    }

    /**
     * @notice Allows the account owner to add liquidity to a Uniswap position (or create a new one).
     * Only works within the `modify` callback.
     * @dev The `LiquidityAmounts` library can help convert underlying amounts to units of `liquidity`.
     * NOTE: Depending on your use-case, it may be more gas-efficient to call `UNISWAP_POOL.mint` in your
     * own contract, instead of doing `uniswapDeposit` inside of `modify`'s callback. As long as you set
     * this `Borrower` as the recipient in `UNISWAP_POOL.mint`, the result is the same.
     * @param lower The tick at the position's lower bound
     * @param upper The tick at the position's upper bound
     * @param liquidity The amount of liquidity to add, in Uniswap's internal units
     * @return amount0 The precise amount of `TOKEN0` that went into the Uniswap position
     * @return amount1 The precise amount of `TOKEN1` that went into the Uniswap position
     */
    function uniswapDeposit(
        int24 lower,
        int24 upper,
        uint128 liquidity
    ) external returns (uint256 amount0, uint256 amount1) {
        require(slot0.state == State.InModifyCallback);

        (amount0, amount1) = UNISWAP_POOL.mint(address(this), lower, upper, liquidity, "");
    }

    /**
     * @notice Allows the account owner to withdraw liquidity from one of their Uniswap positions. Only
     * works within the `modify` callback.
     * @dev The `LiquidityAmounts` library can help convert underlying amounts to units of `liquidity`
     * @param lower The tick at the position's lower bound
     * @param upper The tick at the position's upper bound
     * @param liquidity The amount of liquidity to remove, in Uniswap's internal units. Pass 0 to collect
     * fees without burning any liquidity.
     * @param recipient Receives the tokens from Uniswap. Usually the address of this `Borrower` account.
     * @return burned0 The amount of `TOKEN0` that was removed from the Uniswap position
     * @return burned1 The amount of `TOKEN1` that was removed from the Uniswap position
     * @return collected0 Equal to `burned0` plus any earned `TOKEN0` fees that hadn't yet been claimed
     * @return collected1 Equal to `burned1` plus any earned `TOKEN1` fees that hadn't yet been claimed
     */
    function uniswapWithdraw(
        int24 lower,
        int24 upper,
        uint128 liquidity,
        address recipient
    ) external returns (uint256 burned0, uint256 burned1, uint256 collected0, uint256 collected1) {
        require(slot0.state == State.InModifyCallback);

        (burned0, burned1, collected0, collected1) = _uniswapWithdraw(lower, upper, liquidity, recipient);
    }

    /**
     * @notice The most flexible sub-command. Allows the account owner to transfer amounts of `TOKEN0` and
     * `TOKEN1` to any `recipient` they want. Only works within the `modify` callback.
     * @param amount0 The amount of `TOKEN0` to transfer
     * @param amount1 The amount of `TOKEN1` to transfer
     * @param recipient Receives the transferred tokens
     */
    function transfer(uint256 amount0, uint256 amount1, address recipient) external {
        require(slot0.state == State.InModifyCallback);

        if (amount0 > 0) TOKEN0.safeTransfer(recipient, amount0);
        if (amount1 > 0) TOKEN1.safeTransfer(recipient, amount1);
    }

    /**
     * @notice Allows the account owner to borrow funds from `LENDER0` and `LENDER1`. Only works within
     * the `modify` callback.
     * @dev If `amount0 > 0` and interest hasn't yet accrued in this block for `LENDER0`, it will accrue
     * prior to processing your new borrow. Same goes for `amount1 > 0` and `LENDER1`.
     * @param amount0 The amount of `TOKEN0` to borrow
     * @param amount1 The amount of `TOKEN1` to borrow
     * @param recipient Receives the borrowed tokens. Usually the address of this `Borrower` account.
     */
    function borrow(uint256 amount0, uint256 amount1, address recipient) external {
        require(slot0.state == State.InModifyCallback);

        if (amount0 > 0) LENDER0.borrow(amount0, recipient);
        if (amount1 > 0) LENDER1.borrow(amount1, recipient);
    }

    /**
     * @notice Allows the account owner to repay debts to `LENDER0` and `LENDER1`. Only works within the
     * `modify` callback.
     * @dev This is technically unnecessary since you could call `Lender.repay` directly, specifying this
     * contract as the `beneficiary` and using the `transfer` sub-command to make payments. We include it
     * because it's convenient and gas-efficient for common use-cases.
     * @param amount0 The amount of `TOKEN0` to repay
     * @param amount1 The amount of `TOKEN1` to repay
     */
    function repay(uint256 amount0, uint256 amount1) external {
        require(slot0.state == State.InModifyCallback);

        _repay(amount0, amount1);
    }

    /**
     * @notice Allows the account owner to withdraw their ante. Only works within the `modify` callback.
     * @param recipient Receives the ante (as Ether)
     */
    function withdrawAnte(address payable recipient) external {
        require(slot0.state == State.InModifyCallback);

        recipient.transfer(address(this).balance);
    }

    /*//////////////////////////////////////////////////////////////
                             BALANCE SHEET
    //////////////////////////////////////////////////////////////*/

    function getUniswapPositions() external view returns (int24[] memory) {
        return positions.read();
    }

    function _getAssets(
        int24[] memory positions_,
        Prices memory prices,
        bool withdraw
    ) private returns (Assets memory assets) {
        assets.fixed0 = TOKEN0.balanceOf(address(this));
        assets.fixed1 = TOKEN1.balanceOf(address(this));

        uint256 count = positions_.length;
        unchecked {
            for (uint256 i; i < count; i += 2) {
                // Load lower and upper ticks from the `positions_` array
                int24 l = positions_[i];
                int24 u = positions_[i + 1];
                // Fetch amount of `liquidity` in the position
                (uint128 liquidity, , , , ) = UNISWAP_POOL.positions(keccak256(abi.encodePacked(address(this), l, u)));

                if (liquidity == 0) continue;

                // Compute lower and upper sqrt ratios
                uint160 L = TickMath.getSqrtRatioAtTick(l);
                uint160 U = TickMath.getSqrtRatioAtTick(u);

                // Compute the value of `liquidity` (in terms of token1) at both probe prices
                assets.fluid1A += LiquidityAmounts.getValueOfLiquidity(prices.a, L, U, liquidity);
                assets.fluid1B += LiquidityAmounts.getValueOfLiquidity(prices.b, L, U, liquidity);

                // Compute what amounts underlie `liquidity` at the current TWAP
                (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(prices.c, L, U, liquidity);
                assets.fluid0C += amount0;
                assets.fluid1C += amount1;

                if (!withdraw) continue;

                // Withdraw all `liquidity` from the position
                _uniswapWithdraw(l, u, liquidity, address(this));
            }
        }
    }

    function _getLiabilities() private view returns (uint256 amount0, uint256 amount1) {
        amount0 = LENDER0.borrowBalanceStored(address(this));
        amount1 = LENDER1.borrowBalanceStored(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _uniswapWithdraw(
        int24 lower,
        int24 upper,
        uint128 liquidity,
        address recipient
    ) private returns (uint256 burned0, uint256 burned1, uint256 collected0, uint256 collected1) {
        (burned0, burned1) = UNISWAP_POOL.burn(lower, upper, liquidity);
        (collected0, collected1) = UNISWAP_POOL.collect(recipient, lower, upper, type(uint128).max, type(uint128).max);
    }

    function _repay(uint256 amount0, uint256 amount1) private {
        if (amount0 > 0) {
            TOKEN0.safeTransfer(address(LENDER0), amount0);
            LENDER0.repay(amount0, address(this));
        }
        if (amount1 > 0) {
            TOKEN1.safeTransfer(address(LENDER1), amount1);
            LENDER1.repay(amount1, address(this));
        }
    }

    function _saveSlot0(uint256 slot0_, uint256 addend) private {
        assembly ("memory-safe") {
            sstore(slot0.slot, add(slot0_, addend))
        }
    }

    function _loadSlot0() private view returns (uint256 slot0_) {
        assembly ("memory-safe") {
            slot0_ := sload(slot0.slot)
        }
        // Equivalent to `slot0.state == State.Ready`
        require(slot0_ >> 248 == uint256(State.Ready));
    }

    function _formatted(State state) private pure returns (uint256) {
        return uint256(state) << 248;
    }
}
