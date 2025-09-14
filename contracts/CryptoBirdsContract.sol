// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * CryptoBirds — hand-rolled ERC-721 (no OpenZeppelin)
 * - ERC165 (supportsInterface)
 * - ERC721 Core (transfer/approve/safeTransfer)
 * - ERC721 Metadata (name, symbol, tokenURI)
 * - Safe receiver check (IERC721Receiver)
 * - Owner-only mint; owner/approved burn
 * - Per-token and baseURI metadata
 * - totalSupply + auto-increment token IDs
 * - Strong input validation and approval clearing
 */

/// ===== Interfaces =====
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC721 is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);

    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address);

    function setApprovalForAll(address operator, bool _approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

interface IERC721Metadata is IERC721 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface IERC721Receiver {
    /**
     * MUST return this selector to accept the token:
     * bytes4(keccak256("onERC721Received(address,address,uint256,bytes)")) == 0x150b7a02
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

/// ===== Contract =====
contract CryptoBirdsContract is IERC721Metadata {
    // ---- ERC165 IDs ----
    bytes4 private constant _INTERFACE_ID_ERC165          = 0x01ffc9a7;
    bytes4 private constant _INTERFACE_ID_ERC721          = 0x80ac58cd;
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;
    bytes4 private constant _ERC721_RECEIVED              = 0x150b7a02;

    // ---- Admin ----
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not contract owner");
        _;
    }

    // ---- Metadata ----
    string private _name;
    string private _symbol;
    string private _baseTokenURI; // optional prefix

    // ---- Storage ----
    mapping(uint256 => address) private _owners;                    // tokenId => owner
    mapping(address => uint256) private _balances;                  // owner => balance
    mapping(uint256 => address) private _tokenApprovals;            // tokenId => approved address
    mapping(address => mapping(address => bool)) private _operators;// owner => operator => approved
    mapping(uint256 => string) private _tokenURIs;                  // optional full URI per token

    uint256 private _nextId = 1;
    uint256 private _supply;

    // ---- Constructor ----
    constructor() {
        owner = msg.sender;
        _name = "CryptoBirds";
        _symbol = "CBIRD";
        _baseTokenURI = ""; // set later with setBaseURI() if you want
    }

    // ============================================================
    //                        ERC165
    // ============================================================
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == _INTERFACE_ID_ERC165
            || interfaceId == _INTERFACE_ID_ERC721
            || interfaceId == _INTERFACE_ID_ERC721_METADATA;
    }

    // ============================================================
    //                    ERC721: Views
    // ============================================================
    function name() external view override returns (string memory) { return _name; }
    function symbol() external view override returns (string memory) { return _symbol; }

    function balanceOf(address owner_) public view override returns (uint256) {
        require(owner_ != address(0), "Zero address");
        return _balances[owner_];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "Nonexistent token");
        return o;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Nonexistent token");
        string memory stored = _tokenURIs[tokenId];
        if (bytes(stored).length != 0) return stored;
        return string(abi.encodePacked(_baseTokenURI, _toString(tokenId)));
    }

    function totalSupply() external view returns (uint256) { return _supply; }
    function nextTokenId() external view returns (uint256) { return _nextId; }

    // ============================================================
    //            ERC721: Approvals & Operator Approvals
    // ============================================================
    function approve(address to, uint256 tokenId) external override {
        address o = ownerOf(tokenId);
        require(to != o, "Approve to current owner");
        require(msg.sender == o || isApprovedForAll(o, msg.sender), "Not owner nor approved for all");
        _approve(to, tokenId);
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        require(_exists(tokenId), "Nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external override {
        require(operator != msg.sender, "Approve to caller");
        _operators[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner_, address operator) public view override returns (bool) {
        return _operators[owner_][operator];
    }

    // ============================================================
    //                     ERC721: Transfers
    // ============================================================
    function transferFrom(address from, address to, uint256 tokenId) public override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not owner nor approved");
        require(ownerOf(tokenId) == from, "From is not owner");
        require(to != address(0), "Transfer to zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear single-token approval
        _approve(address(0), tokenId);

        // Move balances and ownership
        _balances[from] -= 1;
        _balances[to]   += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
        transferFrom(from, to, tokenId);
        require(_checkOnERC721Received(msg.sender, from, to, tokenId, data), "Receiver rejected NFT");
    }

    // ============================================================
    //                     Minting & Burning
    // ============================================================
    /// @notice Owner-only mint. If `fullTokenURI` empty, tokenURI = baseURI + tokenId.
    function safeMint(address to, string memory fullTokenURI) external onlyOwner returns (uint256 tokenId) {
        require(to != address(0), "Mint to zero address");

        tokenId = _nextId++;
        require(!_exists(tokenId), "Already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _owners[tokenId] = to;
        _balances[to]   += 1;
        _supply         += 1;

        if (bytes(fullTokenURI).length != 0) {
            _tokenURIs[tokenId] = fullTokenURI;
        }

        emit Transfer(address(0), to, tokenId);
        require(_checkOnERC721Received(msg.sender, address(0), to, tokenId, ""), "Receiver rejected NFT");
    }

    /// @notice Burn a token. Caller must be owner or approved.
    function burn(uint256 tokenId) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not owner nor approved");
        address from = ownerOf(tokenId);

        _beforeTokenTransfer(from, address(0), tokenId);

        _approve(address(0), tokenId); // clear approvals

        _balances[from] -= 1;
        delete _owners[tokenId];
        delete _tokenURIs[tokenId];
        _supply -= 1;

        emit Transfer(from, address(0), tokenId);
    }

    // ============================================================
    //                       Admin Utilities
    // ============================================================
    function setBaseURI(string memory newBase) external onlyOwner {
        _baseTokenURI = newBase;
    }

    function transferContractOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    // ============================================================
    //                     Internal utilities
    // ============================================================
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address o = ownerOf(tokenId);
        return (spender == o || getApproved(tokenId) == spender || isApprovedForAll(o, spender));
    }

    function _approve(address to, uint256 tokenId) internal {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    function _checkOnERC721Received(
        address operator,
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal returns (bool) {
        if (to.code.length == 0) return true; // EOA
        try IERC721Receiver(to).onERC721Received(operator, from, tokenId, data) returns (bytes4 retval) {
            return retval == _ERC721_RECEIVED;
        } catch {
            return false;
        }
    }

    /// @dev Hook for future extensions (freeze, royalties, soulbound checks, etc.)
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}

    // Tiny uint256 -> string
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value; uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
