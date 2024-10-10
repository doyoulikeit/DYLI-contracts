// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1155C, ERC1155OpenZeppelin} from "@limitbreak/creator-token-contracts/contracts/erc1155c/ERC1155C.sol";
import {ERC2981, BasicRoyalties} from "@limitbreak/creator-token-contracts/contracts/programmable-royalties/BasicRoyalties.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract DYLI is ERC1155C, AccessControl, BasicRoyalties {
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    IERC20 public usdc = IERC20(0x75Bf8F439d205B8eE0DE9d3622342eb05985859B);

    event DropCreated(uint256 tokenId, address creator, uint256 price);
    event TokenMinted(
        uint256 tokenId,
        address minter,
        uint256 price,
        uint256 fee
    );

    event TokenRefunded(uint256 tokenId, address minter, uint256 price);
    event TokenRedeemed(uint256 tokenId, address redeemer);

    mapping(uint256 => TokenData) private tokenData;
    mapping(uint256 => uint256) private _totalMinted;
    mapping(uint256 => uint256) private _totalRefunded;
    mapping(uint256 => uint256) private _totalRedeemed;
    mapping(uint256 => bool) private tokenDisabled;

    address feeRecipient = 0x2f2A13462f6d4aF64954ee84641D265932849b64;
    uint256 public fee = 2000000;
    uint256 public createFee = 3000000;

    struct TokenData {
        uint256 maxMint;
        uint256 price;
        address creator;
        bool isOE;
    }

    constructor() ERC1155OpenZeppelin("https://demo.dyli.io/api/metadata?tokenid=") BasicRoyalties(0x2f2A13462f6d4aF64954ee84641D265932849b64, 500) {
        initializeRoles();
    }

    function initializeRoles() internal {
        _grantRole(MODERATOR_ROLE, _msgSender());
    }

    function name() external pure returns (string memory) {
        return "test";
    }

    function symbol() external pure returns (string memory) {
        return "test";
    }

    function setURI(string memory _uri) public onlyRole(MODERATOR_ROLE) {
        _setURI(_uri);
    }

    function setFeeRecipient(address _newFeeRecipient)
        public
        onlyRole(MODERATOR_ROLE)
    {
        feeRecipient = _newFeeRecipient;
    }

    function setFee(uint256 _newFee) public onlyRole(MODERATOR_ROLE) {
        fee = _newFee;
    }

    function setCreateFee(uint256 _newCreateFee)
        public
        onlyRole(MODERATOR_ROLE)
    {
        createFee = _newCreateFee;
    }

    function createDropStripe(
        address creator,
        uint256 maxMint,
        uint256 price,
        bool _isOE
    ) public onlyRole(MODERATOR_ROLE) returns (uint256) {
        _tokenIdCounter.increment();
        uint256 newTokenId = _tokenIdCounter.current();
        tokenData[newTokenId] = TokenData(
            _isOE ? type(uint256).max : maxMint,
            price,
            creator,
            _isOE
        );
        emit DropCreated(newTokenId, creator, price);
        return newTokenId;
    }

    function createDrop(
        address creator,
        uint256 maxMint,
        uint256 price,
        bool _isOE
    ) public onlyRole(MODERATOR_ROLE) returns (uint256) {
        require(
            usdc.transferFrom(creator, feeRecipient, createFee),
            "Payment of fee failed"
        );

        _tokenIdCounter.increment();
        uint256 newTokenId = _tokenIdCounter.current();
        tokenData[newTokenId] = TokenData(
            _isOE ? type(uint256).max : maxMint,
            price,
            creator,
            _isOE
        );
        emit DropCreated(newTokenId, creator, price);
        return newTokenId;
    }

    function mintToken(address user, uint256 tokenId) public {
        require(!tokenDisabled[tokenId], "Token minting is disabled");
        TokenData memory data = tokenData[tokenId];

        if (!data.isOE) {
            require(
                _totalMinted[tokenId] < data.maxMint,
                "Exceeds maximum quantity"
            );
        }

        require(
            usdc.transferFrom(user, address(this), data.price),
            "Payment for product failed"
        );

        require(
            usdc.transferFrom(user, feeRecipient, fee),
            "Payment of fee failed"
        );

        _mint(user, tokenId, 1, "");
        _totalMinted[tokenId] += 1;
        emit TokenMinted(tokenId, user, data.price, fee);
    }

    function mintTokenStripe(address user, uint256 tokenId)
        public
        onlyRole(MODERATOR_ROLE)
    {
        require(!tokenDisabled[tokenId], "Token minting is disabled");
        TokenData memory data = tokenData[tokenId];

        if (!data.isOE) {
            require(
                _totalMinted[tokenId] < data.maxMint,
                "Exceeds maximum quantity"
            );
        }

        _mint(user, tokenId, 1, "");
        _totalMinted[tokenId] += 1;
        emit TokenMinted(tokenId, user, data.price, fee);
    }

    function redeem(address user, uint256 tokenId)
        public
        onlyRole(MODERATOR_ROLE)
    {
        _burn(user, tokenId, 1);
        _totalRedeemed[tokenId] += 1;
        emit TokenRedeemed(tokenId, user);
    }

    function refund(address user, uint256 tokenId)
        public
        onlyRole(MODERATOR_ROLE)
    {
        TokenData memory data = tokenData[tokenId];

        if (!data.isOE) {
            require(
                _totalMinted[tokenId] < data.maxMint,
                "All tokens minted, refund not allowed"
            );
        }

        _burn(user, tokenId, 1);
        _totalRefunded[tokenId] += 1;

        require(usdc.transfer(user, data.price), "Refund failed");

        emit TokenRefunded(tokenId, user, data.price);
    }

    function batchRedeem(address user, uint256[] memory tokenIds)
        public
        onlyRole(MODERATOR_ROLE)
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _burn(user, tokenIds[i], 1);
            _totalRedeemed[tokenIds[i]] += 1;
            emit TokenRedeemed(tokenIds[i], user);
        }
    }

    function batchRefund(address user, uint256[] memory tokenIds)
        public
        onlyRole(MODERATOR_ROLE)
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            TokenData memory data = tokenData[tokenIds[i]];

            if (!data.isOE) {
                require(
                    _totalMinted[tokenIds[i]] < data.maxMint,
                    "All tokens minted, refund not allowed"
                );
            }

            _burn(user, tokenIds[i], 1);
            _totalRefunded[tokenIds[i]] += 1;

            require(usdc.transfer(user, data.price), "Refund failed");

            emit TokenRefunded(tokenIds[i], user, data.price);
        }
    }

    function refundMintToken(address user, uint256 tokenId)
        public
        onlyRole(MODERATOR_ROLE)
    {
        require(!tokenDisabled[tokenId], "Token minting is disabled");
        TokenData memory data = tokenData[tokenId];

        if (!data.isOE) {
            uint256 totalSupply = _totalMinted[tokenId] -
                _totalRedeemed[tokenId];
            require(totalSupply < data.maxMint, "Exceeds maximum quantity");
        }

        _mint(user, tokenId, 1, "");
        _totalMinted[tokenId] += 1;
        emit TokenMinted(tokenId, user, data.price, fee);
    }

    function sendUSDC(
        address from,
        address to,
        uint256 amount
    ) public onlyRole(MODERATOR_ROLE) {
        require(usdc.transferFrom(from, to, amount), "USDC transfer failed");
    }

    function setMetadata(string memory newMetadata)
        public
        onlyRole(MODERATOR_ROLE)
    {
        _setURI(newMetadata);
    }

    function disableToken(uint256 tokenId, bool disabled)
        public
        onlyRole(MODERATOR_ROLE)
    {
        tokenDisabled[tokenId] = disabled;
    }

    function totalMinted(uint256 tokenId) public view returns (uint256) {
        return _totalMinted[tokenId];
    }

    function totalRefunded(uint256 tokenId) public view returns (uint256) {
        return _totalRefunded[tokenId];
    }

    function totalRedeemed(uint256 tokenId) public view returns (uint256) {
        return _totalRedeemed[tokenId];
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator)
        public
        onlyRole(MODERATOR_ROLE)
    {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) public onlyRole(MODERATOR_ROLE) {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function _requireCallerIsContractOwner() internal view virtual override {
        _checkRole(MODERATOR_ROLE);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155C, ERC2981, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}