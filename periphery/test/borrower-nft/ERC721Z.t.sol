// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ERC721} from "solmate/tokens/ERC721.sol";

import {ERC721Z, SafeSSTORE2, BytesLib} from "src/borrower-nft/ERC721Z.sol";

contract MockERC721Z is ERC721Z {
    function name() external pure override returns (string memory) {
        return "Mock NFT";
    }

    function symbol() external pure override returns (string memory) {
        return "MOCK";
    }

    function tokenURI(uint256) external pure override returns (string memory) {
        return "";
    }

    /// @inheritdoc ERC721Z
    function _INDEX_SIZE() internal pure override returns (uint256) {
        return 2;
    }

    /// @inheritdoc ERC721Z
    function _ATTRIBUTES_SIZE() internal pure override returns (uint256) {
        return 20;
    }

    function hasToken(address owner, uint256 tokenId) external view returns (bool) {
        return BytesLib.includes(SafeSSTORE2.read(_pointers[owner]), tokenId, _TOKEN_SIZE());
    }

    function mint(address to, uint256 qty, uint256[] calldata attributes) external {
        _mint(to, qty, attributes);
    }
}

contract ERC721Baseline is ERC721 {
    uint256 public totalSupply;

    mapping(address => mapping(uint256 => bool)) public hasToken;

    constructor() ERC721("Baseline", "BASE") {}

    function tokenURI(uint256) public view virtual override returns (string memory) {
        return "";
    }

    function transferFrom(address from, address to, uint256 id) public override {
        hasToken[from][id] = false;
        hasToken[to][id] = true;

        super.transferFrom(from, to, id);
    }

    function mint(address to, uint256 qty, uint256[] calldata attributes) external {
        require(qty > 0 && qty == attributes.length, "BAD_QUANTITY");

        for (uint256 i; i < qty; i++) {
            uint256 tokenId = (attributes[i] << 16) + ((totalSupply + i) % (1 << 16));

            hasToken[to][tokenId] = true;
            super._mint(to, tokenId);
        }
        totalSupply += qty;
    }
}

contract Harness {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    MockERC721Z immutable MOCK;

    ERC721Baseline immutable BASELINE;

    mapping(address => bool) internal _isOwner;

    address[] public owners;

    mapping(uint256 => bool) public isTokenId;

    uint256[] public tokenIds;

    constructor(MockERC721Z mock, ERC721Baseline baseline) {
        MOCK = mock;
        BASELINE = baseline;
    }

    function approve(address caller, address spender, uint256 id) public {
        if (!isTokenId[id]) {
            vm.expectRevert(bytes("NOT_MINTED"));
            MOCK.approve(spender, id);

            if (tokenIds.length == 0) return;
            id = tokenIds[id % tokenIds.length];
        }

        vm.startPrank(caller);
        address owner = BASELINE.ownerOf(id);
        if (!(caller == owner || BASELINE.isApprovedForAll(owner, caller))) {
            vm.expectRevert(bytes("NOT_AUTHORIZED"));
            MOCK.approve(spender, id);
            vm.expectRevert(bytes("NOT_AUTHORIZED"));
            BASELINE.approve(spender, id);

            vm.stopPrank();
            caller = owner;
            vm.startPrank(caller);
        }

        MOCK.approve(spender, id);
        BASELINE.approve(spender, id);
        vm.stopPrank();
    }

    function setApprovalForAll(address caller, address operator, bool approved) public {
        vm.prank(caller);
        MOCK.setApprovalForAll(operator, approved);
        vm.prank(caller);
        BASELINE.setApprovalForAll(operator, approved);
    }

    function mint(address to, uint256 qty) external {
        if (to == address(0)) to = address(1);
        qty = (qty % 16) + 1;

        uint256[] memory attributes = new uint256[](qty);
        uint256 balance = BASELINE.balanceOf(to);
        uint256 totalSupply = BASELINE.totalSupply();
        for (uint256 i; i < qty; i++) {
            // `uint160` assumes that `_ATTRIBUTE_SIZE` is 20!
            attributes[i] = uint160(uint256(keccak256(abi.encodePacked(to, totalSupply + balance + i))));
        }

        if (to == address(0)) {
            vm.expectRevert(bytes("INVALID_RECIPIENT"));
            MOCK.mint(to, qty, attributes);
            vm.expectRevert(bytes("INVALID_RECIPIENT"));
            BASELINE.mint(to, qty, attributes);
            to = address(12345);
        }

        // SSTORE2 can only handle up to 24,576 bytes
        if (balance + qty >= uint256(24476) / 22) {
            vm.expectRevert(0x30116425);
            MOCK.mint(to, qty, attributes);
            return;
        }

        // Expected events
        for (uint256 i; i < qty; i++) {
            uint256 tokenId = (attributes[i] << 16) + (totalSupply + i);
            isTokenId[tokenId] = true;
            tokenIds.push(tokenId);

            vm.expectEmit(true, true, true, false, address(MOCK));
            emit Transfer(address(0), to, tokenId);
        }

        // ERC721Z
        MOCK.mint(to, qty, attributes);

        // Ghost
        BASELINE.mint(to, qty, attributes);

        // {harness bookkeeping}
        if (!_isOwner[to]) {
            _isOwner[to] = true;
            owners.push(to);
        }
    }

    function transferFrom(address caller, address from, address to, uint256 tokenId) external {
        if (to == address(0)) {
            vm.expectRevert(bytes("INVALID_RECIPIENT"));
            MOCK.transferFrom(from, to, tokenId);

            if (owners.length == 0) return;
            to = owners[tokenId % owners.length];
        }

        if (!isTokenId[tokenId]) {
            vm.prank(from);
            vm.expectRevert(BytesLib.RemovalFailed.selector);
            MOCK.transferFrom(from, to, tokenId);

            if (tokenIds.length == 0) return;
            tokenId = tokenIds[tokenId % tokenIds.length];
        }

        if (BASELINE.ownerOf(tokenId) != from) {
            vm.prank(from);
            vm.expectRevert(BytesLib.RemovalFailed.selector);
            MOCK.transferFrom(from, to, tokenId);
            vm.expectRevert(bytes("WRONG_FROM"));
            BASELINE.transferFrom(from, to, tokenId);

            from = BASELINE.ownerOf(tokenId);
        }

        if (!(caller == from || BASELINE.isApprovedForAll(from, caller) || caller == BASELINE.getApproved(tokenId))) {
            vm.prank(caller);
            vm.expectRevert(bytes("NOT_AUTHORIZED"));
            MOCK.transferFrom(from, to, tokenId);
            vm.prank(caller);
            vm.expectRevert(bytes("NOT_AUTHORIZED"));
            BASELINE.transferFrom(from, to, tokenId);

            caller = from;
        }

        // SSTORE2 can only handle up to 24,576 bytes
        if (BASELINE.balanceOf(to) + 1 >= uint256(24476) / 20) {
            vm.expectRevert(0x30116425);
            vm.prank(caller);
            MOCK.transferFrom(from, to, tokenId);
            return;
        }

        vm.prank(caller);
        vm.expectEmit(true, true, true, false, address(MOCK));
        emit Transfer(from, to, tokenId);
        MOCK.transferFrom(from, to, tokenId);

        vm.prank(caller);
        BASELINE.transferFrom(from, to, tokenId);

        // {harness bookkeeping}
        if (!_isOwner[to]) {
            _isOwner[to] = true;
            owners.push(to);
        }
    }

    function getNumOwners() external view returns (uint256) {
        return owners.length;
    }

    function getNumTokenIds() external view returns (uint256) {
        return tokenIds.length;
    }
}

contract ERC721ZTest is Test {
    MockERC721Z mock;

    ERC721Baseline baseline;

    Harness harness;

    function setUp() public {
        mock = new MockERC721Z();
        baseline = new ERC721Baseline();
        harness = new Harness(mock, baseline);

        targetContract(address(harness));

        excludeSender(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D)); // vm
        excludeSender(address(0x4e59b44847b379578588920cA78FbF26c0B4956C)); // built-in create2 deployer
        excludeSender(address(this));
        excludeSender(address(mock));
        excludeSender(address(baseline));
        excludeSender(address(harness));
    }

    function invariant_totalSupply() public {
        assertEq(mock.totalSupply(), baseline.totalSupply());
    }

    function invariant_ownerOf() public {
        uint256 numTokens = harness.getNumTokenIds();
        for (uint256 i; i < numTokens; i++) {
            uint256 tokenId = harness.tokenIds(i);
            assertEq(mock.ownerOf(tokenId), baseline.ownerOf(tokenId));
        }
    }

    function invariant_balanceOf() public {
        uint256 numOwners = harness.getNumOwners();
        for (uint256 i; i < numOwners; i++) {
            address owner = harness.owners(i);
            assertEq(mock.balanceOf(owner), baseline.balanceOf(owner));
        }
    }

    function invariant_tokenByIndex() public {
        uint256 numTokens = harness.getNumTokenIds();
        for (uint256 i; i < numTokens; i++) {
            uint256 tokenId = harness.tokenIds(i);
            assertEq(mock.tokenByIndex(i), tokenId);
        }

        vm.expectRevert();
        mock.tokenByIndex(numTokens);
    }

    function invariant_tokenOfOwnerByIndex() public {
        uint256 numOwners = harness.getNumOwners();
        for (uint256 i; i < numOwners; i++) {
            address owner = harness.owners(i);
            uint256 balance = baseline.balanceOf(owner);

            for (uint256 j; j < balance; j++) {
                uint256 tokenId = mock.tokenOfOwnerByIndex(owner, j);
                assertTrue(harness.isTokenId(tokenId));
            }

            vm.expectRevert();
            mock.tokenOfOwnerByIndex(owner, balance);
        }

        for (uint256 i; i < 20; i++) {
            vm.expectRevert();
            mock.tokenOfOwnerByIndex(address(0), i);
        }
    }

    function invariant_hasAttributes() public {
        uint256 numOwners = harness.getNumOwners();
        uint256 numTokens = harness.getNumTokenIds();
        for (uint256 i; i < numOwners; i++) {
            address owner = harness.owners(i);

            for (uint256 j; j < numTokens; j++) {
                uint256 tokenId = harness.tokenIds(j);

                assertEq(mock.hasToken(owner, tokenId), baseline.hasToken(owner, tokenId));
            }
        }
    }

    function test_gas_mint1(uint128 a) public {
        uint256[] memory arr = new uint256[](1);
        arr[0] = a;
        mock.mint(address(1), 1, arr);
    }

    function test_gas_mint2(uint128 a, uint128 b) public {
        uint256[] memory arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
        mock.mint(address(1), 2, arr);
    }

    function test_gas_mint4(uint128 a, uint128 b, uint128 c, uint128 d) public {
        uint256[] memory arr = new uint256[](4);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        mock.mint(address(1), 4, arr);
    }

    function test_gas_reuseImpossible(uint128 a, uint128 b, uint128 c, uint128 d, uint128 e) public {
        vm.pauseGasMetering();
        uint256[] memory arr = new uint256[](4);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        mock.mint(address(1), 4, arr);

        arr = new uint256[](1);
        arr[0] = e;
        mock.mint(address(2), 1, arr);

        uint256 id = (uint256(a) << 16) + uint256(0);
        vm.prank(address(1));
        mock.transferFrom(address(1), address(2), id);

        id = (uint256(e) << 16) + uint256(4);
        vm.resumeGasMetering();
        vm.prank(address(2));
        mock.transferFrom(address(2), address(1), id);
    }

    function test_gas_reusePossible(uint128 a, uint128 b, uint128 c, uint128 d, uint128 e) public {
        vm.pauseGasMetering();
        uint256[] memory arr = new uint256[](4);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        mock.mint(address(1), 4, arr);

        arr = new uint256[](1);
        arr[0] = e;
        mock.mint(address(2), 1, arr);

        uint256 id = (uint256(a) << 16) + uint256(0);
        vm.prank(address(1));
        mock.transferFrom(address(1), address(2), id);

        id = (uint256(a) << 16) + uint256(0);
        vm.resumeGasMetering();
        vm.prank(address(2));
        mock.transferFrom(address(2), address(1), id);
    }
}
