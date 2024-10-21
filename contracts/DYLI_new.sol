// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract dyli_new is ERC1155, Ownable {

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

<<<<<<< HEAD
    mapping(address => bool) public admin;

=======
>>>>>>> a9cec7a29fb89b8f43e5a050ab089d1b3ba2be19
    mapping(uint256 => TokenData) public tokenData;
    mapping(uint256 => bool) private tokenDisabled;

    mapping(uint256 => uint256) public totalMinted;
    mapping(uint256 => uint256) public totalRefunded;
    mapping(uint256 => uint256) public totalRedeemed;

    mapping(address => uint256) public nonces;
    mapping(address => mapping(uint256 => bool)) public nonceUsed;

    uint256 public currentTokenId = 0;

    address feeRecipient = 0x2f2A13462f6d4aF64954ee84641D265932849b64;
    address public signer = 0x2f2A13462f6d4aF64954ee84641D265932849b64;
    uint256 public fee = 2000000;
    uint256 public createFee = 3000000;

    address public marketplace;

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
        address creator;
        bool isOE;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 minMint;
    }

    constructor(
        string memory _uri
    )
        ERC1155(_uri)
    {}

    function verify(
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        return ECDSA.recover(hash, signature) == signer;
    }

    function name() external pure returns (string memory) {
        return "test";
    }

    function symbol() external pure returns (string memory) {
        return "test";
    }

    function setURI(string memory _uri) public onlyAdmin {
        _setURI(_uri);
    }

    function setFeeRecipient(address _newFeeRecipient) public onlyAdmin {
        feeRecipient = _newFeeRecipient;
    }

    function setUsdc(address _usdc) public onlyAdmin {
        usdc = IERC20(_usdc);
    }

    function setFee(uint256 _newFee) public onlyAdmin {
        fee = _newFee;
    }

    function setCreateFee(uint256 _newCreateFee) public onlyAdmin {
        createFee = _newCreateFee;
    }

    function setSigner(address _newSigner) public onlyAdmin {
        signer = _newSigner;
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
            _isOE ? type(uint256).max : maxMint,
            price,
            creator,
            _isOE,
            startTimestamp,
            endTimestamp,
            minMint
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

        TokenData memory data = tokenData[tokenId];

        if (data.endTimestamp != 0) {
            require(block.timestamp >= data.startTimestamp, "Sale has not started");
            require(block.timestamp <= data.endTimestamp, "Sale has ended");
        }

        if (!isStripe) {
            require(usdc.transferFrom(msg.sender, address(this), data.price), "Payment for product failed");
            require(usdc.transferFrom(msg.sender, feeRecipient, fee), "Payment of fee failed");
        }

        _mintToken(msg.sender, tokenId, data);
    }

    function _mintToken(
        address user,
        uint256 tokenId,
        TokenData memory data
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
        TokenData memory data = tokenData[tokenId];

        require(usdc.transfer(msg.sender, data.price * amount), "Refund failed");

        require(!tokenDisabled[tokenId], "Token minting is disabled");

        _burn(msg.sender, tokenId, amount);
        totalRefunded[tokenId] += amount;
        emit TokenRefunded(tokenId, msg.sender, data.price * amount);
    }

    function disableToken(uint256 tokenId, bool disabled) public onlyAdmin {
        tokenDisabled[tokenId] = disabled;
    }

    function uri(uint256 tokenId) public view virtual override returns (string memory) {
        return string(abi.encodePacked(super.uri(tokenId), Strings.toString(tokenId)));
    }

    function withdraw() public onlyOwner {
        uint256 usdcBalance = usdc.balanceOf(address(this));
        if (usdcBalance > 0) {
            require(usdc.transfer(feeRecipient, usdcBalance), "USDC transfer failed");
        }
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

}
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC1155C, ERC2981, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
