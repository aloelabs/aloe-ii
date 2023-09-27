// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";

import {NFTSVG} from "./NFTSVG.sol";

library NFTDescriptor {
    using LibString for string;
    using LibString for uint256;

    struct ConstructTokenURIParams {
        uint256 tokenId;
        address token0;
        address token1;
        string symbol0;
        string symbol1;
        int24 tickLower;
        int24 tickUpper;
        int24 tickCurrent;
        uint24 fee;
        address poolAddress;
        address borrowerAddress;
        bool isGeneralized;
    }

    function constructTokenURI(ConstructTokenURIParams memory params) internal pure returns (string memory) {
        params.symbol0 = params.symbol0.escapeJSON();
        params.symbol1 = params.symbol1.escapeJSON();

        string memory tokenId = params.tokenId.toString();
        string memory token0 = _addressToString(params.token0);
        string memory token1 = _addressToString(params.token1);
        string memory feeString = _feeToString(params.fee);
        string memory poolString = _addressToString(params.poolAddress);
        string memory borrowerString = _addressToString(params.borrowerAddress);

        string memory name = _generateName(params, feeString);
        string memory description = _generateDescription(
            tokenId,
            params.symbol0,
            params.symbol1,
            token0,
            token1,
            feeString,
            poolString,
            borrowerString
        );
        string memory image = Base64.encode(bytes(_generateSVGImage(params, tokenId, token0, token1, feeString)));

        return
            string.concat(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        string.concat(
                            '{"name":"',
                            name,
                            '", "description":"',
                            description,
                            '", "image": "',
                            "data:image/svg+xml;base64,",
                            image,
                            '"}'
                        )
                    )
                )
            );
    }

    function _generateName(
        ConstructTokenURIParams memory params,
        string memory feeString
    ) private pure returns (string memory) {
        return string.concat("Uniswap V3 (Aloe) - ", feeString, " - ", params.symbol0, "/", params.symbol1);
    }

    function _generateDescription(
        string memory tokenId,
        string memory symbol0,
        string memory symbol1,
        string memory token0,
        string memory token1,
        string memory feeString,
        string memory poolString,
        string memory borrowerString
    ) private pure returns (string memory) {
        return
            string.concat(
                "This NFT grants the owner control of an Aloe II Boosted Position in the ",
                symbol0,
                "-",
                symbol1,
                " Uniswap V3 pool.\\n",
                "\\nPool: ",
                poolString,
                "\\n\\nBorrower: ",
                borrowerString,
                "\\n\\n",
                symbol0,
                ": ",
                token0,
                "\\n\\n",
                symbol1,
                ": ",
                token1,
                "\\n\\nFee Tier: ",
                feeString,
                "\\n\\nToken ID: ",
                tokenId,
                "\\n\\n",
                unicode"⚠️ DISCLAIMER: Due diligence is imperative when assessing this NFT. Make sure token addresses match the expected tokens, as token symbols may be imitated."
            );
    }

    function _generateSVGImage(
        ConstructTokenURIParams memory params,
        string memory tokenId,
        string memory token0,
        string memory token1,
        string memory feeString
    ) private pure returns (string memory) {
        NFTSVG.SVGParams memory svgParams = NFTSVG.SVGParams(
            tokenId.slice(0, 16),
            token0,
            token1,
            params.symbol0,
            params.symbol1,
            feeString,
            params.tickLower,
            params.tickUpper,
            params.tickLower <= params.tickCurrent && params.tickCurrent < params.tickUpper,
            params.isGeneralized,
            _tokenToColor(params.token0, 60),
            _tokenToColor(params.token1, 32),
            _tokenToColor(params.token0, 80),
            _tokenToColor(params.token1, 36)
        );

        return NFTSVG.generateSVG(svgParams);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _addressToString(address addr) private pure returns (string memory) {
        return LibString.toHexStringChecksummed(addr);
    }

    function _feeToString(uint24 fee) private pure returns (string memory) {
        if (fee == 100) return "0.01%";
        if (fee == 500) return "0.05%";
        if (fee == 3000) return "0.3%";
        if (fee == 10000) return "1.0%";
        return "";
    }

    function _tokenToColor(address token, uint256 offset) private pure returns (string memory) {
        return string.concat("#", uint256((uint160(token) >> offset) % (1 << 24)).toHexStringNoPrefix(3));
    }
}
