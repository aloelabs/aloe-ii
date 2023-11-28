// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";

/// @title Rewards
/// @notice Implements logic for staking rewards
/// @author Aloe Labs, Inc.
/// @author Inspired by [Yield Protocol](https://github.com/yieldprotocol/yield-utils-v2/blob/main/src/token/ERC20Rewards.sol)
library Rewards {
    event RewardsRateSet(uint64 rate);

    event RewardsClaimed(address indexed user, uint96 amount);

    struct PoolState {
        // Accumulated rewards per token, scaled up by 1e18
        uint160 accumulated;
        // Last time `accumulated` was updated
        uint32 lastUpdated;
        // The rewards rate, specified as [token units per second]
        uint64 rate;
    }

    struct UserState {
        // Rewards earned by the user up until the checkpoint
        uint96 earned;
        // `poolState.accumulated` the last time `userState` was updated
        uint160 checkpoint;
    }

    struct Storage {
        PoolState poolState;
        mapping(address => UserState) userStates;
    }

    bytes32 private constant _REWARDS_SLOT = keccak256("aloe.ii.rewards");

    /**
     * @notice Sets the pool's rewards rate. May be 0.
     * @param rate The rewards rate, specified as [token units per second]. Keep between 10^17 and 10^28
     * token units per year for smooth operation -- between 0.1 and 10 billion tokens, assuming 18 decimals.
     */
    function setRate(Storage storage store, uint160 accumulated, uint64 rate) internal {
        PoolState memory poolState = store.poolState;

        poolState.accumulated = accumulated;
        poolState.lastUpdated = uint32(block.timestamp);
        poolState.rate = rate;

        store.poolState = poolState;
        emit RewardsRateSet(rate);
    }

    function claim(
        Storage storage store,
        uint160 accumulated,
        address user,
        uint256 balance
    ) internal returns (uint96 earned) {
        UserState memory userState = previewUserState(store, accumulated, user, balance);

        earned = userState.earned;
        userState.earned = 0;

        store.userStates[user] = userState;
        emit RewardsClaimed(user, earned);
    }

    /**
     * @notice Ensures that changes in the pool's `totalSupply` don't mess up rewards accounting. Should
     * be called anytime `totalSupply` changes.
     * @dev Use `Rewards.load()` to easily obtain the first two arguments
     * @param store The rewards storage pointer
     * @param accumulated Up-to-date `poolState.accumulated`, i.e. the output of `_accumulate`
     */
    function updatePoolState(Storage storage store, uint160 accumulated) internal {
        PoolState memory poolState = store.poolState;

        poolState.accumulated = accumulated;
        poolState.lastUpdated = uint32(block.timestamp);
        // poolState.rate is unchanged

        store.poolState = poolState;
    }

    /**
     * @notice Tracks how much reward a `user` earned while holding a particular `balance`. Should be
     * called anytime their balance changes.
     * @dev Use `Rewards.load()` to easily obtain the first two arguments
     * @param store The rewards storage pointer
     * @param accumulated Up-to-date `poolState.accumulated`, i.e. the output of `_accumulate`
     * @param user The user whose balance (# of shares) is about to change
     * @param balance The user's balance (# of shares) -- before it changes
     */
    function updateUserState(Storage storage store, uint160 accumulated, address user, uint256 balance) internal {
        store.userStates[user] = previewUserState(store, accumulated, user, balance);
    }

    function previewUserState(
        Storage storage store,
        uint160 accumulated,
        address user,
        uint256 balance
    ) internal view returns (UserState memory userState) {
        unchecked {
            userState = store.userStates[user];

            userState.earned += uint96((balance * (accumulated - userState.checkpoint)) / 1e18);
            userState.checkpoint = accumulated;
        }
    }

    function getRate() internal view returns (uint64) {
        return _getStorage().poolState.rate;
    }

    /// @dev Returns arguments to be used in `updatePoolState` and `updateUserState`. No good semantic
    /// meaning here, just a coincidence that both functions need this information.
    function load(uint256 totalSupply) internal view returns (Storage storage store, uint160 accumulator) {
        store = _getStorage();
        accumulator = _accumulate(store.poolState, totalSupply);
    }

    /// @dev Accumulates rewards based on the current `rate` and time elapsed since last update
    function _accumulate(PoolState memory poolState, uint256 totalSupply) private view returns (uint160) {
        unchecked {
            uint256 deltaT = block.timestamp - poolState.lastUpdated;
            return poolState.accumulated + uint160(SoladyMath.rawDiv(1e18 * deltaT * poolState.rate, totalSupply));
        }
    }

    /// @dev Diamond-pattern-style storage getter
    function _getStorage() private pure returns (Storage storage store) {
        bytes32 position = _REWARDS_SLOT;
        assembly ("memory-safe") {
            store.slot := position
        }
    }
}
