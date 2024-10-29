// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DYLIMarketplace is Ownable, ReentrancyGuard {
    IERC20 public usdc = IERC20(0x75Bf8F439d205B8eE0DE9d3622342eb05985859B);
    IERC1155 public erc1155 = IERC1155(0x5807171D067ef120C585a5538e0cAc11237Fc335);

    uint256 public royaltyPercentage = 5;
    address public royaltyRecipient = 0xa69B6935B0F38506b81224B4612d7Ea49A4B0aCC;

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
    mapping(uint256 => uint256) public tokenRoyalties;

    event ListingCreated(
        uint256 tokenId,
        address seller,
        uint128 price,
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

    event ListingEdited(
        address seller,
        uint256 tokenId,
        uint128 newPricePerItem,
        uint64 newExpirationTime
    );

    event ListingCancelled(
        address seller,
        uint256 tokenId
    );

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
        uint128 newPricePerItem,
        uint64 newExpiration
    );

    event BidCancelled(
        uint256 tokenId,
        address bidder
    );

    event BidAccepted(
        uint256 tokenId,
        address seller,
        address buyer,
        uint64 amount
    );

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

        emit ListingCreated(tokenId, msg.sender, price, block.timestamp, expiration);
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
        uint256 royalty = tokenRoyalties[tokenId] > 0 ? tokenRoyalties[tokenId] : royaltyPercentage;
        uint256 royaltyAmount = (totalPrice * royalty) / 100;

        require(usdc.transferFrom(msg.sender, seller, totalPrice - royaltyAmount), "Payment failed");
        require(usdc.transferFrom(msg.sender, royaltyRecipient, royaltyAmount), "Royalty payment failed");
        require(usdc.transferFrom(msg.sender, royaltyRecipient, fixedFee), "Flat fee payment failed");

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

    function editBid(uint256 tokenId, uint64 newPrice, uint64 newExpiration) public nonReentrant {
        ListingOrBid storage bid = tokenBids[msg.sender][tokenId];
        require(bid.expirationTime > block.timestamp, "Bid is no longer active");

        bid.pricePerItem = newPrice;
        bid.expirationTime = newExpiration;

        emit BidEdited(tokenId, msg.sender, newPrice, newExpiration);
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
        uint256 royalty = tokenRoyalties[tokenId] > 0 ? tokenRoyalties[tokenId] : royaltyPercentage;
        uint256 royaltyAmount = (totalPrice * royalty) / 100;

        bid.expirationTime = 0;


        require(usdc.transfer(msg.sender, totalPrice - royaltyAmount), "Payment to token owner failed");
        require(usdc.transfer(royaltyRecipient, royaltyAmount), "Royalty payment failed");
        require(usdc.transfer(royaltyRecipient, fixedFee), "Flat fee payment failed");

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

    function setTokenRoyalty(uint256 tokenId, uint256 percentage) public onlyOwner {
        require(percentage <= 100, "Royalty percentage cannot exceed 100%");
        tokenRoyalties[tokenId] = percentage;
    }

    function setFixedFee(uint256 newFee) public onlyOwner {
        fixedFee = newFee;
    }

    function withdrawUSDC(uint256 amount) external onlyOwner {
        require(usdc.balanceOf(address(this)) >= amount, "Insufficient USDC balance");
        require(usdc.transfer(msg.sender, amount), "USDC transfer failed");
    }

    function withdrawETH(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient ETH balance");
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
    }


    function getBid(uint256 tokenId) public view returns (ListingOrBid memory) {
        return tokenBids[msg.sender][tokenId];
    }

    function getListing(uint256 tokenId) public view returns (ListingOrBid memory) {
        return listings[msg.sender][tokenId];
    }
}