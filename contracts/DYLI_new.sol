// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1155C, ERC1155OpenZeppelin} from "@limitbreak/creator-token-contracts/contracts/erc1155c/ERC1155C.sol";
import {ERC2981, BasicRoyalties} from "@limitbreak/creator-token-contracts/contracts/programmable-royalties/BasicRoyalties.sol";

contract DYLI_new is ERC1155C, Ownable, BasicRoyalties {

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

    mapping(address => bool) public admin;

    mapping(uint256 => TokenData) public tokenData;
    mapping(uint256 => bool) private tokenDisabled;

    mapping(uint256 => uint256) public totalMinted;
    mapping(uint256 => uint256) public totalRefunded;
    mapping(uint256 => uint256) public totalRedeemed;

    mapping(address => uint256) public nonces;
    mapping(address => mapping(uint256 => bool)) public nonceUsed;

    uint256 public currentTokenId = 0;

    address feeRecipient = 0x2f2A13462f6d4aF64954ee84641D265932849b64;
    address public signerAddress = 0x2f2A13462f6d4aF64954ee84641D265932849b64;
    uint256 public fee = 2000000;
    uint256 public createFee = 3000000;

    address public marketplace;
    string public BASE_URI;

    uint256 public reservedTokens = 0;

    modifier checkNonce(address user, uint256 nonce) {
        require(!nonceUsed[user][nonce], "Invalid nonce");
        nonceUsed[user][nonce] = true;
        nonces[user]++;
        _;
    }

    modifier onlyAdmin() {
        require(admin[msg.sender] || msg.sender == owner(), "Only admins can call this function");
        _;
    }

    struct TokenData {
        uint256 maxMint;
        uint256 price;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 minMint;
        uint256 tokensReserved;
        address creator;
        bool reserveFreed;
        bool isOE;
    }

    constructor(
        string memory _BASE_URI,
        address usdc_,
        address signerAddress_,
        address feeRecipient_,
        uint96 royaltyFeeNumerator_
    )
        ERC1155OpenZeppelin(_BASE_URI)
        BasicRoyalties(feeRecipient_, royaltyFeeNumerator_)
    {
        usdc = IERC20(usdc_);
        BASE_URI = _BASE_URI;
     	signerAddress = signerAddress_;
        feeRecipient = feeRecipient_;
    }

    function verify(
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        return ECDSA.recover(hash, signature) == signerAddress;
    }

    function name() external pure returns (string memory) {
        return "test";
    }

    function symbol() external pure returns (string memory) {
        return "test";
    }

    function setURI(string memory _URI) public onlyAdmin {
        BASE_URI = _URI;
    }

    function setFeeRecipient(address _newFeeRecipient) public onlyAdmin {
        feeRecipient = _newFeeRecipient;
    }

    function setFee(uint256 _newFee) public onlyAdmin {
        fee = _newFee;
    }

    function setCreateFee(uint256 _newCreateFee) public onlyAdmin {
        createFee = _newCreateFee;
    }

    function setSigner(address _newSigner) public onlyAdmin {
        signerAddress = _newSigner;
    }

    function createDrop(
        uint256 maxMint,
        uint256 price,
        bool _isOE,
        bool isStripe,
        bytes memory signature,
        uint256 nonce,
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 minMint
    ) public checkNonce(msg.sender, nonce) returns (uint256) {
        bytes32 hash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    msg.sender,
                    maxMint,
                    price,
                    _isOE,
                    isStripe,
                    nonce,
                    startTimestamp,
                    endTimestamp,
                    minMint
                )
            )
        );

        require(verify(hash, signature), "Invalid signature");

        if (!isStripe) {
            require(usdc.transferFrom(msg.sender, feeRecipient, createFee), "Payment of fee failed");
        }

        return _createDrop(msg.sender, maxMint, price, _isOE, startTimestamp, endTimestamp, minMint);
    }

    function _createDrop(
        address creator,
        uint256 maxMint,
        uint256 price,
        bool _isOE,
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 minMint
    ) internal returns (uint256) {
        currentTokenId++;

        tokenData[currentTokenId] = TokenData(
            maxMint,
            price,
            startTimestamp,
            endTimestamp,
            minMint,
            0,
            creator,
            false,
            _isOE
        );

        emit DropCreated(currentTokenId, creator, price);

        return currentTokenId;
    }

    function mintToken(
        uint256 tokenId,
        bytes memory signature,
        uint256 nonce,
        bool isStripe
    ) public checkNonce(msg.sender, nonce) {
        bytes32 hash = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(msg.sender, tokenId, nonce, isStripe))
        );

        require(verify(hash, signature), "Invalid signature");

        TokenData storage data = tokenData[tokenId];

        if (data.endTimestamp != 0) {
            require(block.timestamp >= data.startTimestamp, "Sale has not started");
            require(block.timestamp <= data.endTimestamp, "Sale has ended");
        }

        if (!isStripe) {
            require(usdc.transferFrom(msg.sender, address(this), data.price), "Payment for product failed");
            require(usdc.transferFrom(msg.sender, feeRecipient, fee), "Payment for fee failed");
        }

        

        _mintToken(msg.sender, tokenId, data);

        if(!data.isOE && !data.reserveFreed) {

            reservedTokens += data.price;
            data.tokensReserved += data.price;

            _updateClaimableTokens(tokenId); 
        }
    }

    function _mintToken(
        address user,
        uint256 tokenId,
        TokenData storage data
    ) internal {
        require(!tokenDisabled[tokenId], "Token minting is disabled");

        if (!data.isOE) {
            require(totalMinted[tokenId] < data.maxMint, "Exceeds maximum quantity");
        }

        _mint(user, tokenId, 1, "");
        totalMinted[tokenId] += 1;
        emit TokenMinted(tokenId, user, data.price, fee);
    }

    function batchRedeem(
        uint256[] memory tokenIds,
        uint256 nonce,
        bytes memory signature
    ) public checkNonce(msg.sender, nonce) {
        bytes32 hash = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(msg.sender, tokenIds, nonce))
        );

        require(verify(hash, signature), "Invalid signature");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _burn(msg.sender, tokenIds[i], 1);
            totalRedeemed[tokenIds[i]] += 1;
            emit TokenRedeemed(tokenIds[i], msg.sender);
        }
    }

    function refundToken(
        uint256 tokenId,
        uint256 amount,
        bytes memory signature,
        uint256 nonce
    ) public checkNonce(msg.sender, nonce) {
        bytes32 hash = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(msg.sender, tokenId, amount, nonce))
        );

        require(verify(hash, signature), "Invalid signature");
        TokenData storage data = tokenData[tokenId];

        require(!data.isOE, "Token is not refundable");
        require(data.minMint > totalMinted[tokenId], "Token has already hit min mint so refunds are disabled");

        require(usdc.transfer(msg.sender, data.price * amount), "Refund failed");

        require(!tokenDisabled[tokenId], "Token minting is disabled");

        reservedTokens -= data.price * amount;
        data.tokensReserved -= data.price * amount;

        _burn(msg.sender, tokenId, amount);
        totalRefunded[tokenId] += amount;
        emit TokenRefunded(tokenId, msg.sender, data.price * amount);
    }

    function disableToken(uint256 tokenId, bool disabled) public onlyAdmin {
        tokenDisabled[tokenId] = disabled;
    }

    function setAdmin(address _admin, bool _isAdmin) public onlyOwner {
        admin[_admin] = _isAdmin;
    }

    function setMarketplace(address _marketplace) public onlyOwner {
        marketplace = _marketplace;
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) public override {
        require(msg.sender == from || msg.sender == marketplace, "Only token owner or marketplace can transfer");

        super.safeTransferFrom(from, to, id, amount, data);
    }

    function _updateClaimableTokens(uint256 tokenId) internal {
        if(tokenData[tokenId].minMint < totalMinted[tokenId] && tokenData[tokenId].endTimestamp < block.timestamp) {
            reservedTokens -= tokenData[tokenId].tokensReserved;
            tokenData[tokenId].tokensReserved = 0;
            tokenData[tokenId].reserveFreed = true;
        }
    }

    function updateClaimableTokens(uint256 tokenId) public onlyAdmin {
        _updateClaimableTokens(tokenId);
    }

    function reserveSafeWithdraw() public onlyOwner {
        usdc.transfer(msg.sender, usdc.balanceOf(address(this)) - reservedTokens);
    }

    function fullWithdraw() public onlyOwner {
        usdc.transfer(msg.sender, usdc.balanceOf(address(this)));
    }

    function setReservedTokens(uint256 amount) public onlyOwner {
        reservedTokens = amount;
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(BASE_URI, Strings.toString(tokenId)));
    }

    function _requireCallerIsContractOwner() internal view virtual override {
        require(msg.sender == owner(), "Only contract owner can call this function");
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC1155C, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // These functions are intended for testnet use only and will be deleted before deployment to mainnet.

    function ownerCreateDrop(
        uint256 maxMint,
        uint256 price,
        bool _isOE,
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 minMint
    ) public onlyOwner returns (uint256) {
        return _createDrop(msg.sender, maxMint, price, _isOE, startTimestamp, endTimestamp, minMint);
    }

    function ownerMintToken(
        uint256 tokenId,
        address recipient,
        uint256 amount
    ) public onlyOwner {
        TokenData memory data = tokenData[tokenId];

        _mint(recipient, tokenId, amount, "");
        totalMinted[tokenId] += amount;
        emit TokenMinted(tokenId, recipient, data.price, fee);
    }

    function ownerRedeem(
        uint256 tokenId,
        address recipient,
        uint256 amount
    ) public onlyOwner {
        require(balanceOf(recipient, tokenId) >= amount, "Insufficient tokens to redeem");
        _burn(recipient, tokenId, amount);
        totalRedeemed[tokenId] += amount;
        emit TokenRedeemed(tokenId, recipient);
    }

    function ownerRefund(
        uint256 tokenId,
        address recipient,
        uint256 amount
    ) public onlyOwner {
        TokenData memory data = tokenData[tokenId];
        require(balanceOf(recipient, tokenId) >= amount, "Insufficient tokens to refund");

        _burn(recipient, tokenId, amount);
        totalRefunded[tokenId] += amount;

        emit TokenRefunded(tokenId, recipient, data.price * amount);
    }

}