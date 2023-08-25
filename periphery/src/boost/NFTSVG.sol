// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {LibString} from "solady/utils/LibString.sol";

/// @title NFTSVG
/// @notice Generates SVG for a boosted Uniswap position
library NFTSVG {
    using LibString for uint256;
    using LibString for int256;

    struct SVGParams {
        string tokenId;
        string token0;
        string token1;
        string symbol0;
        string symbol1;
        string feeTier;
        int24 lower;
        int24 upper;
        bool inRange;
        bool isGeneralized;
        string color0;
        string color1;
        string color2;
        string color3;
    }

    function generateSVG(SVGParams memory params) internal pure returns (string memory svg) {
        return
            string.concat(
                _generateSVGDefs(),
                // card effects wrappers
                '<g filter="url(#shadow)"><g clip-path="url(#card)" filter="url(#rough-paper)">',
                // card background
                '<rect width="350" height="475" x="30" y="30" fill="white" />',
                _generateSVGHeaderText(params.symbol0, params.symbol1, params.feeTier),
                '<g clip-path="url(#square330)" style="transform:translate(40px,165px)"',
                params.inRange ? ">" : ' filter="url(#grayscale)">',
                _generate3X3Quilt(params.color0, "rgb(242,245,238)", params.color1, params.color2, params.color3),
                _generateAnimatedText(params.token0, params.token1, params.symbol0, params.symbol1),
                "</g>",
                _generatePositionDataText(params.tokenId, params.lower, params.upper, params.isGeneralized),
                "</g></g></svg>"
            );
    }

    function _generateSVGDefs() private pure returns (string memory) {
        return
            string.concat(
                '<svg width="410" height="535" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">',
                "<defs>",
                // card drop shadow
                '<filter id="shadow"><feDropShadow dx="0" dy="0" stdDeviation="12" flood-color="black" flood-opacity="25%" /></filter>',
                // gradient + mask so that tickers don't bleed over the edge of the card
                '<linearGradient id="grad-symbol"><stop offset="0.70" stop-color="white" stop-opacity="1" /><stop offset="0.95" stop-color="white" stop-opacity="0" /></linearGradient>',
                '<mask id="fade-symbol" maskContentUnits="userSpaceOnUse"><rect width="350px" height="131px" fill="url(#grad-symbol)" /></mask>',
                // card clipping
                '<clipPath id="card"><rect width="350" height="475" x="30" y="30" rx="35" /></clipPath>',
                // pattern clipping
                '<clipPath id="square110"><rect x="0" y="0" width="110" height="110" /></clipPath>',
                // quilt clipping
                '<clipPath id="square330"><rect x="0" y="0" width="330" height="330" rx="24" /></clipPath>',
                // paper texture (noise)
                '<filter id="rough-paper" x="0%" y="0%" width="100%" height="100%">',
                '<feTurbulence type="fractalNoise" baseFrequency="1" numOctaves="3" result="noise" />',
                '<feDiffuseLighting in="noise" lighting-color="white" surfaceScale="1.4" result="lit-noise"><feDistantLight azimuth="0" elevation="90" /></feDiffuseLighting>',
                '<feBlend in="SourceGraphic" in2="lit-noise" mode="multiply" />',
                "</filter>",
                // grayscale
                '<filter id="grayscale"><feColorMatrix type="saturate" values="0" /></filter>',
                // animated text path
                '<path id="text-path-a" d="M5,0 a1,1,0,0,0,210,0 a1,1,0,0,0,-210,0" />',
                "</defs>"
            );
    }

    function _generateSVGHeaderText(
        string memory quoteTokenSymbol,
        string memory baseTokenSymbol,
        string memory feeTier
    ) private pure returns (string memory) {
        return
            string.concat(
                '<g mask="url(#fade-symbol)" style="transform:translate(30px,30px)">',
                '<text y="56px" x="20px" fill="black" font-family="\'Courier New\', monospace" font-weight="200" font-size="36px">',
                quoteTokenSymbol,
                "/",
                baseTokenSymbol,
                '</text><text y="101px" x="20px" fill="black" font-family="\'Courier New\', monospace" font-weight="200" font-size="36px">',
                feeTier,
                "</text></g>"
            );
    }

    function _generate3X3Quilt(
        string memory color0,
        string memory color1,
        string memory color2,
        string memory color3,
        string memory color4
    ) private pure returns (string memory) {
        return
            string.concat(
                // pattern A
                '<g clip-path="url(#square110)"><rect fill="',
                color0,
                '" x="0" y="0" width="110" height="110" /><circle fill="',
                color1,
                '" cx="110" cy="0" r="110" /><circle fill="',
                color2,
                '" cx="110" cy="0" r="55" /></g>',
                // pattern B
                '<g clip-path="url(#square110)" style="transform:translate(110px,0px)"><rect fill="',
                color2,
                '" x="0" y="0" width="110" height="110" /><circle fill="',
                color0,
                '" cx="0" cy="0" r="110" /><circle fill="',
                color3,
                '" cx="0" cy="0" r="55" /></g>',
                // pattern C
                '<g clip-path="url(#square110)" style="transform:translate(220px,0px)"><rect fill="',
                color4,
                '" x="0" y="0" width="55" height="55" /><rect fill="',
                color2,
                '" x="55" y="0" width="55" height="55" /><rect fill="',
                color1,
                '" x="0" y="55" width="55" height="55" /><rect fill="',
                color3,
                '" x="55" y="55" width="55" height="55" /><polygon fill="',
                color0,
                '" points="12.57,55 55,12.57 97.43,55 55,97.43" /></g>',
                // pattern C.2
                '<g clip-path="url(#square110)" style="transform:translate(0px,110px)"><rect fill="',
                color3,
                '" x="0" y="0" width="55" height="55" /><rect fill="',
                color1,
                '" x="55" y="0" width="55" height="55" /><rect fill="',
                color2,
                '" x="0" y="55" width="55" height="55" /><rect fill="',
                color4,
                '" x="55" y="55" width="55" height="55" /><polygon fill="',
                color0,
                '" points="12.57,55 55,12.57 97.43,55 55,97.43" /></g>',
                // pattern B.2
                '<g clip-path="url(#square110)" style="transform:translate(110px,110px)"><rect fill="',
                color2,
                '" x="0" y="0" width="110" height="110" /><circle fill="',
                color0,
                '" cx="110" cy="110" r="110" /><circle fill="',
                color3,
                '" cx="110" cy="110" r="55" /></g>',
                // pattern A.2
                '<g clip-path="url(#square110)" style="transform:translate(220px,110px)"><rect fill="',
                color0,
                '" x="0" y="0" width="110" height="110" /><circle fill="',
                color1,
                '" cx="0" cy="110" r="110" /><circle fill="',
                color2,
                '" cx="0" cy="110" r="55" /></g>',
                // pattern D
                '<g clip-path="url(#square110)" style="transform:translate(0px,220px)"><polygon fill="',
                color0,
                '" points="0,0 110,110 0,110" /><polygon fill="',
                color2,
                '" points="0,0 110,110 110,0" /><path d="M35.35,35.35 a1,1 0 0,0 42.42,42.42" fill="',
                color3,
                '" /><path d="M35.35,35.35 a1,1 0 0,1 42.42,42.42" fill="',
                color1,
                '" /></g>',
                // pattern E
                '<g clip-path="url(#square110)" style="transform:translate(110px,220px)"><rect fill="',
                color3,
                '" x="55" y="0" width="55" height="110" /><circle fill="',
                color1,
                '" cx="55" cy="55" r="55" /><rect fill="',
                color4,
                '" x="0" y="0" width="55" height="110" /></g>',
                // pattern F
                '<g clip-path="url(#square110)" style="transform:translate(220px,220px)"><polygon fill="',
                color0,
                '" points="0,0 55,55 55,110 0,110" /><polygon fill="',
                color4,
                '" points="0,0 55,0 55,55" /><polygon fill="',
                color2,
                '" points="55,0 55,55 110,0" /><polygon fill="',
                color3,
                '" points="110,0 55,55, 110,110" /><polygon fill="',
                color2,
                '" points="55,55 55,110 110,110" /></g>'
            );
    }

    function _generateAnimatedText(
        string memory quoteToken,
        string memory baseToken,
        string memory quoteTokenSymbol,
        string memory baseTokenSymbol
    ) private pure returns (string memory) {
        return
            string.concat(
                '<text text-rendering="optimizeSpeed" style="fill: white; mix-blend-mode: difference;">',
                '<textPath startOffset="-100%" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                baseToken,
                unicode" • ",
                baseTokenSymbol,
                '<animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="10s" repeatCount="indefinite" /></textPath>',
                '<textPath startOffset="0%" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                baseToken,
                unicode" • ",
                baseTokenSymbol,
                '<animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="10s" repeatCount="indefinite" /></textPath>',
                '<textPath startOffset="-50%" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                quoteToken,
                unicode" • ",
                quoteTokenSymbol,
                '<animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="10s" repeatCount="indefinite" /></textPath>',
                '<textPath startOffset="50%" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                quoteToken,
                unicode" • ",
                quoteTokenSymbol,
                '<animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="10s" repeatCount="indefinite" /></textPath></text>'
            );
    }

    function _generatePositionDataText(
        string memory tokenId,
        int24 tickLower,
        int24 tickUpper,
        bool isGeneralized
    ) private pure returns (string memory) {
        if (isGeneralized) {
            return
                string.concat(
                    '<g style="transform:translate(50px, 458px)">',
                    '<rect width="',
                    uint256(7 * (bytes(tokenId).length + 8)).toString(),
                    'px" height="26px" rx="8px" ry="8px" fill="white" />',
                    '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="black"><tspan fill="rgba(0,0,0,0.6)">ID: </tspan>',
                    tokenId,
                    "</text></g>"
                );
        }

        string memory tickLowerStr = int256(tickLower).toString();
        string memory tickUpperStr = int256(tickUpper).toString();

        return
            string.concat(
                '<g style="transform:translate(50px, 398px)">',
                '<rect width="',
                uint256(7 * (bytes(tokenId).length + 8)).toString(),
                'px" height="26px" rx="8px" ry="8px" fill="white" />',
                '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="black"><tspan fill="rgba(0,0,0,0.6)">ID: </tspan>',
                tokenId,
                "</text></g>",
                ' <g style="transform:translate(50px, 428px)">',
                '<rect width="',
                uint256(7 * (bytes(tickLowerStr).length + 14)).toString(),
                'px" height="26px" rx="8px" ry="8px" fill="white" />',
                '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="black"><tspan fill="rgba(0,0,0,0.6)">Min Tick: </tspan>',
                tickLowerStr,
                "</text></g>",
                '<g style="transform:translate(50px, 458px)">',
                '<rect width="',
                uint256(7 * (bytes(tickUpperStr).length + 14)).toString(),
                'px" height="26px" rx="8px" ry="8px" fill="white" />',
                '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="black"><tspan fill="rgba(0,0,0,0.6)">Max Tick: </tspan>',
                tickUpperStr,
                "</text></g>"
            );
    }
}
