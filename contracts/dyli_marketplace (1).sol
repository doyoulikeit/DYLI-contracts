// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Marketplace is AccessControl, Ownable, ReentrancyGuard {
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    IERC20 public usdc;
    IERC1155 public erc1155;

    uint256 public royaltyPercentage = 5;
    address public royaltyRecipient = 0xa69B6935B0F38506b81224B4612d7Ea49A4B0aCC;
    address public usdcAddress = 0x75Bf8F439d205B8eE0DE9d3622342eb05985859B;
    address public erc1155Address = 0xEd98897E58E61fFB8a4Cf802C6FCc03977975461;

    uint256 public fixedFee = 2 * 10**6;

    IERC20 public paymentToken;

    struct ListingOrBid {
        uint64 quantity;
        uint128 pricePerItem;
        uint64 expirationTime;
    }

    uint256 public listingCount = 0;
    uint256 public offerCount = 0;

    mapping(address => mapping(uint256 => ListingOrBid)) public listings;
    mapping(address => mapping(uint256 => ListingOrBid)) public tokenBids;

    event ListingCreated(
        uint256 listingId,
        address seller,
        uint128 price,
        uint256 tokenId,
        uint256 timestamp,
        uint64 expiration
    );
    event ListingBought(
        uint256 tokenId,
        address buyer,
        uint128 pricePerItem,
        uint64 amount,
        address seller
    );
    event ListingEdited(address seller, uint256 tokenId, uint128 newPricePerItem, uint64 newExpirationTime);
    event ListingCancelled(address seller, uint256 tokenId);

    event BidCreated(
        uint256 tokenId,
        address buyer,
        uint64 amount,
        uint256 timestamp,
        uint64 expiration,
        uint128 pricePerItem
    );
    event BidEdited(
        uint256 tokenId,
        address bidder,
        uint64 newAmount,
        uint64 newExpiration,
        uint128 newPricePerItem
    );

    event BidCancelled(uint256 tokenId, address bidder);

    event BidAccepted(
        uint256 tokenId,
        address seller,
        address buyer,
        uint256 amount
    );

    constructor() {
        _grantRole(MODERATOR_ROLE, _msgSender());
    }

    function setUSDCContract(address _address) public onlyOwner {
        usdc = IERC20(_address);
    }

    function setERC1155Contract(address _address) public onlyOwner {
        erc1155 = IERC1155(_address);
    }

    function createListing(
        uint256 tokenId,
        uint128 price,
        uint64 expiration,
        uint64 amount
    ) public nonReentrant {
        require(listings[msg.sender][tokenId].expirationTime == 0, "Listing already exists");
        require(expiration > block.timestamp, "Expiration time must be in the future");
        require(erc1155.balanceOf(msg.sender, tokenId) >= amount, "Does not own enough tokens to list");
        require(erc1155.isApprovedForAll(msg.sender, address(this)), "Has not approved marketplace to transfer tokens");

        listings[msg.sender][tokenId] = ListingOrBid({
            quantity: amount,
            pricePerItem: price,
            expirationTime: expiration
        });

        emit ListingCreated(tokenId, msg.sender, price, tokenId, block.timestamp, expiration);
    }

    function editListing(uint256 tokenId, uint128 newPrice, uint64 newExpiration) public nonReentrant {
        ListingOrBid storage listing = listings[msg.sender][tokenId];
        require(listing.expirationTime > block.timestamp, "Listing is no longer active");
        require(newExpiration > block.timestamp, "New expiration time must be in the future");

        listing.pricePerItem = newPrice;
        listing.expirationTime = newExpiration;
        emit ListingEdited(msg.sender, tokenId, newPrice, newExpiration);
    }

    function cancelListing(uint256 tokenId) public nonReentrant {
        ListingOrBid storage listing = listings[msg.sender][tokenId];
        require(listing.expirationTime > block.timestamp, "Listing is no longer active");

        listing.expirationTime = 0;
        emit ListingCancelled(msg.sender, tokenId);
    }

    function buyListing(uint256 tokenId, address seller, uint64 amount, uint128 pricePerItem) public nonReentrant {
        ListingOrBid storage listing = listings[seller][tokenId];
        require(listing.expirationTime > block.timestamp, "Listing is no longer active");
        require(amount > 0, "Amount must be greater than 0");
        require(pricePerItem == listing.pricePerItem, "Price per item does not match");

        uint256 totalPrice = pricePerItem * amount;
        uint256 royaltyAmount = (totalPrice * royaltyPercentage) / 100;

        require(usdc.transferFrom(msg.sender, seller, totalPrice - royaltyAmount), "Payment failed");
        require(usdc.transferFrom(msg.sender, royaltyRecipient, royaltyAmount), "Royalty payment failed");
        require(usdc.transferFrom(msg.sender, royaltyRecipient, fixedFee), "$2 fee payment failed");

        if(listing.quantity == amount)
            listing.expirationTime = 0;

        erc1155.safeTransferFrom(seller, msg.sender, tokenId, amount, "");

        emit ListingBought(tokenId, msg.sender, pricePerItem, amount, seller);
    }

    function createBid(uint256 tokenId, uint64 amount, uint64 expiration, uint128 pricePerItem) public nonReentrant {
        uint256 cost = pricePerItem * amount;
        require(usdc.balanceOf(msg.sender) >= cost, "Insufficient balance");
        require(amount > 0, "Amount must be greater than 0");

        tokenBids[msg.sender][tokenId] = ListingOrBid({
            quantity: amount,
            pricePerItem: pricePerItem,
            expirationTime: expiration
        });

        emit BidCreated(tokenId, msg.sender, amount, block.timestamp, expiration, pricePerItem);
    }

    function editBid(uint256 tokenId, uint64 newAmount, uint64 newExpiration) public nonReentrant {
        ListingOrBid storage bid = tokenBids[msg.sender][tokenId];
        require(bid.expirationTime > block.timestamp, "Bid is no longer active");

        bid.quantity = newAmount;
        bid.expirationTime = newExpiration;

        emit BidEdited(tokenId, msg.sender, newAmount, newExpiration, bid.pricePerItem);
    }

    function cancelBid(uint256 tokenId) public nonReentrant {
        ListingOrBid storage bid = tokenBids[msg.sender][tokenId];
        require(bid.expirationTime > block.timestamp, "Bid is no longer active");

        bid.expirationTime = 0;

        emit BidCancelled(tokenId, msg.sender);
    }

    function acceptBid(uint256 tokenId, address buyer) public nonReentrant {
        ListingOrBid storage bid = tokenBids[buyer][tokenId];
        require(bid.expirationTime > block.timestamp, "Bid is no longer active");

        uint256 totalPrice = bid.pricePerItem * bid.quantity;
        uint256 royaltyAmount = (totalPrice * royaltyPercentage) / 100;

        bid.expirationTime = 0;


        require(usdc.transfer(msg.sender, totalPrice - royaltyAmount), "Payment to token owner failed");
        require(usdc.transfer(royaltyRecipient, royaltyAmount), "Royalty payment failed");
        require(usdc.transfer(royaltyRecipient, fixedFee), "$2 fee payment failed");

        erc1155.safeTransferFrom(msg.sender, buyer, tokenId, bid.quantity, "");

        emit BidAccepted(tokenId, msg.sender, buyer, bid.quantity);
    }

    function setRoyaltyRecipient(address newRecipient) public onlyOwner {
        royaltyRecipient = newRecipient;
    }

    function setRoyaltyPercentage(uint256 newPercentage) public onlyOwner {
        require(newPercentage <= 100, "Royalty percentage cannot exceed 100%");
        royaltyPercentage = newPercentage;
    }

    function setFixedFee(uint256 newFee) public onlyOwner {
        fixedFee = newFee;
    }

    function getBid(uint256 tokenId) public view returns (ListingOrBid memory) {
        return tokenBids[msg.sender][tokenId];
    }
}