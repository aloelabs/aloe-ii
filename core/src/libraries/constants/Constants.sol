// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

/// @dev The initial value of `Lender`'s `borrowIndex`
uint256 constant ONE = 1e12;

/// @dev An additional scaling factor applied to borrowed amounts before dividing by `borrowIndex` and storing.
/// uint72 matches the type of `borrowIndex` in `Ledger` to guarantee that the stored borrow units fit in uint256.
uint256 constant BORROWS_SCALER = type(uint72).max * ONE;

/// @dev The maximum percentage yield per second, scaled up by 1e12. The current value is equivalent to
/// (1 + 706354 / 1e12) ^ (24 * 60 * 60) - 1 ⇒ +6.3% per day or +53% per week. If the rate is consistently at this
/// maximum value, the `Lender` will function for 1 year before `borrowIndex` overflows.
/// @custom:math
/// > 📘 Useful Math
/// >
/// > - T: number of years before overflow, assuming maximum rate
/// > - borrowIndexInit: `ONE`
/// > - borrowIndexMax: 2^72 - 1
/// >
/// > - maxAPR: ln(borrowIndexMax / borrowIndexInit) / T
/// > - maxAPY: exp(maxAPR) - 1
/// > - MAX_RATE: (exp(maxAPR / secondsPerYear) - 1) * 1e12
uint256 constant MAX_RATE = 706354;

/// @dev The default amount of Ether required to take on debt in a `Borrower`. The `Factory` can override this value
/// on a per-market basis.
uint216 constant DEFAULT_ANTE = 0.1 ether;

/// @dev The default number of standard deviations of price movement used to determine probe prices for `Borrower`
/// solvency. The `Factory` can override this value on a per-market basis.
uint8 constant DEFAULT_N_SIGMA = 5;

/// @dev The minimum implied volatility. Clamped to this **before** multiplying by `DEFAULT_N_SIGMA`
uint256 constant MIN_SIGMA = 0.01e18;

/// @dev The maximum implied volatility. Clamped to this **before** multiplying by `DEFAULT_N_SIGMA`
/// To avoid underflow in `BalanceSheet.computeProbePrices`, ensure that `MAX_SIGMA * DEFAULT_N_SIGMA <= 1e18`
uint256 constant MAX_SIGMA = 0.18e18;

/// @dev The lower bound on what any `Lender`'s reserve factor can be. Expressed as reciprocal, e.g. 4 → 25%
uint256 constant MIN_RESERVE_FACTOR = 4;

/// @dev The upper bound on what any `Lender`'s reserve factor can be. Expressed as reciprocal, e.g. 20 → 5%
uint256 constant MAX_RESERVE_FACTOR = 20;

/// @dev \\( 1 + \frac{1}{\text{MAX_LEVERAGE}} \\) should correspond to the maximum feasible single-block
/// `accrualFactor` so that liquidators have time to respond to interest updates
uint256 constant MAX_LEVERAGE = 200;

uint256 constant LIQUIDATION_INCENTIVE = 20; // Expressed as reciprocal, e.g. 20 --> 5%

uint256 constant LIQUIDATION_GRACE_PERIOD = 2 minutes;

uint256 constant IV_SCALE = 24 hours;

uint256 constant IV_CHANGE_PER_SECOND = 5e12;

/// @dev To estimate volume, we need 2 samples. One is always at the current block, the other is from
/// `FEE_GROWTH_AVG_WINDOW` seconds ago, +/- `3 * FEE_GROWTH_SAMPLE_PERIOD`. Larger values make the resulting volume
/// estimate more robust, but may cause the oracle to miss brief spikes in activity.
uint256 constant FEE_GROWTH_AVG_WINDOW = 6 hours;

/// @dev The length of the circular buffer that stores feeGrowthGlobals samples.
/// Must be in interval
/// \\( \left[ \frac{\text{FEE_GROWTH_AVG_WINDOW}}{\text{FEE_GROWTH_SAMPLE_PERIOD}}, 256 \right) \\)
uint256 constant FEE_GROWTH_ARRAY_LENGTH = 72;

/// @dev The minimum number of seconds that must elapse before a new feeGrowthGlobals sample will be stored. This also
/// controls how often the oracle can update IV.
uint256 constant FEE_GROWTH_SAMPLE_PERIOD = 5 minutes;

/// @dev To compute Uniswap mean price & liquidity, we need 2 samples. One is always at the current block, the other is
/// from `UNISWAP_AVG_WINDOW` seconds ago. Larger values make the resulting price/liquidity values harder to
/// manipulate, but also make the oracle slower to respond to changes.
uint32 constant UNISWAP_AVG_WINDOW = 30 minutes;

/// @dev Assume someone is manipulating the Uniswap TWAP oracle. To steal money from the protocol and create bad debt,
/// they would need to change the TWAP by a factor of (1 / collateralFactor), where the collateralFactor is a function
/// of volatility. We have a manipulation metric that increases as an attacker tries to change the TWAP. If this metric
/// rises above a certain threshold, certain functionality will be paused, e.g. no new debt can be created. The
/// threshold is calculated as follows:
///
/// \\( \text{manipulationThreshold} =
/// 2 \cdot \frac{log_{1.0001}\left( \frac{1}{\text{collateralFactor}} \right)}{\text{MANIPULATION_THRESHOLD_DIVISOR}} \\)
uint24 constant MANIPULATION_THRESHOLD_DIVISOR = 24;
