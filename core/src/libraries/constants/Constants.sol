// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

uint256 constant MIN_SIGMA = 0.02e18;

uint256 constant MAX_SIGMA = 0.15e18;

uint256 constant MIN_RESERVE_FACTOR = 4; // Expressed as reciprocal, e.g. 4 --> 25%

uint256 constant MAX_RESERVE_FACTOR = 20; // Expressed as reciprocal, e.g. 20 --> 5%

uint256 constant MAX_LEVERAGE = 200;

uint256 constant LIQUIDATION_INCENTIVE = 20; // Expressed as reciprocal, e.g. 20 --> 5%
