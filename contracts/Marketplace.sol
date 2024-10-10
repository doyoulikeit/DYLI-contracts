// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract Marketplace is AccessControl, Ownable {
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    IERC20 public usdc;
    IERC1155 public erc1155;

    uint256 public royaltyPercentage = 5;
    address public royaltyRecipient = 0xa69B6935B0F38506b81224B4612d7Ea49A4B0aCC;
    address public usdcAddress = 0x75Bf8F439d205B8eE0DE9d3622342eb05985859B;
    address public erc1155Address = 0xEd98897E58E61fFB8a4Cf802C6FCc03977975461;

    uint256 public fixedFee = 2 * 10**6;

    struct Listing {
        address seller;
        uint256 price;
        uint256 tokenId;
        uint256 timestamp;
        uint256 expiration;
        bool isActive;
    }

    struct Offer {
        address buyer;
        uint256 amount;
        uint256 timestamp;
        uint256 expiration;
        bool isActive;
    }

    uint256 public listingCount = 0;
    uint256 public offerCount = 0;

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Offer) public offers;

    event ListingCreated(
        uint256 listingId,
        address seller,
        uint256 price,
        uint256 tokenId,
        uint256 timestamp,
        uint256 expiration
    );
    event ListingBought(
        uint256 listingId,
        address buyer,
        uint256 price,
        uint256 tokenId
    );
    event ListingEdited(uint256 listingId, uint256 newPrice, uint256 newExpiration);
    event ListingCancelled(uint256 listingId);

    event OfferCreated(
        uint256 offerId,
        uint256 tokenId,
        address buyer,
        uint256 amount,
        uint256 timestamp,
        uint256 expiration
    );
    event OfferEdited(
        uint256 offerId,
        uint256 newAmount,
        uint256 newExpiration
    );
    event OfferCancelled(uint256 offerId);
    event OfferAccepted(
        uint256 offerId,
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
        uint256 price,
        uint256 expiration
    ) public returns (uint256) {
        require(expiration > block.timestamp, "Expiration time must be in the future");
        require(erc1155.balanceOf(msg.sender, tokenId) >= 1, "Must own at least 1 token to list");

        listingCount++;
        listings[listingCount] = Listing({
            seller: msg.sender,
            price: price,
            tokenId: tokenId,
            timestamp: block.timestamp,
            expiration: expiration,
            isActive: true
        });

        emit ListingCreated(listingCount, msg.sender, price, tokenId, block.timestamp, expiration);
        return listingCount;
    }

    function editListing(uint256 listingId, uint256 newPrice, uint256 newExpiration) public {
        Listing storage listing = listings[listingId];
        require(msg.sender == listing.seller, "Only seller can edit the listing");
        require(listing.isActive, "Listing is no longer active");
        require(newExpiration > block.timestamp, "New expiration time must be in the future");

        listing.price = newPrice;
        listing.expiration = newExpiration;
        emit ListingEdited(listingId, newPrice, newExpiration);
    }

    function cancelListing(uint256 listingId) public {
        Listing storage listing = listings[listingId];
        require(msg.sender == listing.seller, "Only seller can cancel the listing");
        require(listing.isActive, "Listing is no longer active");

        listing.isActive = false;
        emit ListingCancelled(listingId);
    }

    function buyListing(uint256 listingId) public {
        Listing storage listing = listings[listingId];
        require(listing.isActive, "Listing is no longer active");
        require(block.timestamp <= listing.expiration, "Listing has expired");
        require(erc1155.balanceOf(listing.seller, listing.tokenId) >= 1, "Seller doesn't have enough tokens");

        uint256 totalPrice = listing.price;
        uint256 royaltyAmount = (totalPrice * royaltyPercentage) / 100;

        require(usdc.transferFrom(msg.sender, listing.seller, totalPrice - royaltyAmount), "Payment failed");
        require(usdc.transferFrom(msg.sender, royaltyRecipient, royaltyAmount), "Royalty payment failed");
        require(usdc.transferFrom(msg.sender, royaltyRecipient, fixedFee), "$2 fee payment failed");

        listing.isActive = false;

        erc1155.safeTransferFrom(listing.seller, msg.sender, listing.tokenId, 1, "");

        emit ListingBought(listingId, msg.sender, listing.price, listing.tokenId);
    }

    function createOffer(uint256 tokenId, uint256 amount, uint256 expiration) public returns (uint256) {
        offerCount++;
        offers[offerCount] = Offer({
            buyer: msg.sender,
            amount: amount,
            timestamp: block.timestamp,
            expiration: expiration,
            isActive: true
        });

        require(usdc.transferFrom(msg.sender, address(this), amount), "Payment for offer failed");
        require(usdc.transferFrom(msg.sender, address(this), fixedFee), "$2 fee payment failed");

        emit OfferCreated(offerCount, tokenId, msg.sender, amount, block.timestamp, expiration);
        return offerCount;
    }

    function editOffer(uint256 offerId, uint256 newAmount, uint256 newExpiration) public {
        Offer storage offer = offers[offerId];
        require(msg.sender == offer.buyer, "Only offer creator can edit");
        require(offer.isActive, "Offer is no longer active");

        uint256 currentAmount = offer.amount;
        offer.amount = newAmount;
        offer.expiration = newExpiration;

        if (newAmount > currentAmount) {
            uint256 additionalAmount = newAmount - currentAmount;
            require(usdc.transferFrom(msg.sender, address(this), additionalAmount), "Additional payment failed");
        } else {
            uint256 refundAmount = currentAmount - newAmount;
            require(usdc.transfer(msg.sender, refundAmount), "Refund failed");
        }

        emit OfferEdited(offerId, newAmount, newExpiration);
    }

    function cancelOffer(uint256 offerId) public {
        Offer storage offer = offers[offerId];
        require(msg.sender == offer.buyer, "Only offer creator can cancel");
        require(offer.isActive, "Offer is no longer active");

        offer.isActive = false;
        require(usdc.transfer(offer.buyer, offer.amount), "Refund failed");

        emit OfferCancelled(offerId);
    }

    function acceptOffer(uint256 tokenId, uint256 offerId) public {
        Offer storage offer = offers[offerId];
        require(offer.isActive, "Offer is no longer active");
        require(erc1155.balanceOf(msg.sender, tokenId) >= 1, "You don't own the token");

        uint256 royaltyAmount = (offer.amount * royaltyPercentage) / 100;

        offer.isActive = false;

        require(usdc.transfer(msg.sender, offer.amount - royaltyAmount), "Payment to token owner failed");
        require(usdc.transfer(royaltyRecipient, royaltyAmount), "Royalty payment failed");
        require(usdc.transfer(royaltyRecipient, fixedFee), "$2 fee payment failed");

        erc1155.safeTransferFrom(msg.sender, offer.buyer, tokenId, 1, "");

        emit OfferAccepted(offerId, tokenId, msg.sender, offer.buyer, offer.amount);
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

    function getOffer(uint256 offerId) public view returns (Offer memory) {
        return offers[offerId];
    }
}
