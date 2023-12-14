// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @dev Returns \\( 10^{12} \cdot e^{\frac{x}{10^{12}}} \\) or `type(int256).max`, whichever is smaller
/// @custom:author Modified from [Solady](https://github.com/Vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol#L113)
function exp1e12(int256 x) pure returns (int256 r) {
    unchecked {
        // When the result is < 0.5 we return zero. This happens when
        // x <= floor(ln(0.5 / 1e12) * 1e12) ~ -28e12
        if (x <= -28324168296488) return r;
        // When the result is > (2**255 - 1) we cannot represent it as an int.
        // This happens when x >= floor(ln((2**255 - 1) / 1e12) * 1e12) ~ 149e12.
        if (x >= 149121509926857) return type(int256).max;

        // x is now in the range (-29, 150) * 1e12. Convert to (-29, 150) * 2**96
        // for more intermediate precision and a binary basis. This base conversion
        // is a multiplication by 2**96 / 1e12 = 2**84 / 5**12.
        x = (x << 84) / 5 ** 12;

        // Reduce range of x to (-½ ln 2, ½ ln 2) * 2**96 by factoring out powers
        // of two such that exp(x) = exp(x') * 2**k, where k is an integer.
        // Solving this gives k = round(x / log(2)) and x' = x - k * log(2).
        int256 k = ((x << 96) / 54916777467707473351141471128 + 2 ** 95) >> 96;
        x = x - k * 54916777467707473351141471128;

        // k is in the range [-41, 215].

        // Evaluate using a (6, 7)-term rational approximation.
        // p is made monic, we'll multiply by a scale factor later.
        int256 y = x + 1346386616545796478920950773328;
        y = ((y * x) >> 96) + 57155421227552351082224309758442;
        int256 p = y + x - 94201549194550492254356042504812;
        p = ((p * y) >> 96) + 28719021644029726153956944680412240;
        p = p * x + (4385272521454847904659076985693276 << 96);

        // We leave p in 2**192 basis so we don't need to scale it back up for the division.
        int256 q = x - 2855989394907223263936484059900;
        q = ((q * x) >> 96) + 50020603652535783019961831881945;
        q = ((q * x) >> 96) - 533845033583426703283633433725380;
        q = ((q * x) >> 96) + 3604857256930695427073651918091429;
        q = ((q * x) >> 96) - 14423608567350463180887372962807573;
        q = ((q * x) >> 96) + 26449188498355588339934803723976023;

        /// @solidity memory-safe-assembly
        assembly {
            // Div in assembly because solidity adds a zero check despite the unchecked.
            // The q polynomial won't have zeros in the domain as all its roots are complex.
            // No scaling is necessary because p is already 2**96 too large.
            r := sdiv(p, q)
        }

        // r should be in the range (0.09, 0.25) * 2**96.

        // We now need to multiply r by:
        // * the scale factor s = ~6.031367120.
        // * the 2**k factor from the range reduction.
        // * the 1e12 / 2**96 factor for base conversion.
        r = int256((uint256(r) * 4008531014412650626985742312566589230316694133190) >> uint256(215 - k));
    }
}
