// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MiniMart
 * @author mulf
 * @notice A lightweight, signature-based ERC721 marketplace.
 */
contract MiniMart is Ownable, Pausable, EIP712, ReentrancyGuard {
    using ERC165Checker for address;

    uint256 private constant MAX_BATCH_SIZE = 25;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new order is successfully listed.
    event OrderListed(
        bytes32 indexed orderId,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );

    /// @notice Emitted when an order is removed from the marketplace.
    event OrderRemoved(bytes32 indexed orderId);

    /// @notice Emitted when an order is successfully fulfilled.
    event OrderFulfilled(bytes32 indexed orderId, address indexed buyer);

    /// @notice Emitted when Admin withdraws fees.
    event FeesWithdrawn();

    /// @notice Emitted when sellers cliam proceeds from sales.
    event ProceedsClaimed(address indexed claimant);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error SignerMustBeSeller();
    error ZeroAddress();
    error AlreadyListed();
    error OrderExpired();
    error NonceIncorrect();
    error OrderPriceTooLow();
    error NonERC721Interface();
    error NotListingCreator();
    error NotTokenOwner();
    error OrderNotFound();
    error InvalidBatchSize();
    error FeeWithdrawlFailed();
    error WithdrawFailed();
    error OrderPriceWrong();
    error MarketplaceNotApproved();
    error RefundFailed();
    error CallNotSupported();
    error OrderFulfillmentFailed();
    error OrderRemovalFailed();
    error DuplicateOrderHash();
    error ClaimFailed();
    error NoProceedsToClaim();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STRUCTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice A struct representing a sell order for an NFT.
    struct Order {
        address seller;
        uint96 price;
        address nftContract;
        uint64 expiration;
        address taker;
        uint64 nonce;
        uint256 tokenId;
    }

    /// @notice A struct representing the result of a batch order operation
    struct OrderResult {
        bytes32 orderHash;
        bool success;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        STATE VARIABLES                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The fee percentage in basis points (e.g., 300 = 3%).
    uint16 public constant FEE_BPS = 300;

    /// @notice Pending fees generated from order sales yet to be withdrawn
    uint256 public pendingFees;

    /// @notice type hash of the order struct for the hashOrder function
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(address seller,uint96 price,address nftContract,uint64 expiration,address taker,uint64 nonce,uint256 tokenId)"
    );

    /// @notice Mapping from an order hash to the corresponding Order struct.
    mapping(bytes32 orderHash => Order) public orders;

    /// @notice Mapping from an NFT (contract -> tokenId) to its active order hash.
    mapping(address => mapping(uint256 => bytes32)) public activeOrderHash;

    /// @notice Mapping from a seller's address to their current nonce.
    mapping(address seller => uint64 nonce) public nonces;

    /// @notice Mapping of proceeds from sales that are claimable.
    mapping(address => uint256) public claimableProceeds;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTRUCTOR                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the contract, setting the owner, and EIP-712 domain.
    /// @param initialOwner The initial owner of the contract.
    /// @param name The EIP-712 domain name.
    /// @param version The EIP-712 domain version.
    constructor(address initialOwner, string memory name, string memory version)
        Ownable(initialOwner)
        EIP712(name, version)
    {
        if (initialOwner == address(0)) revert ZeroAddress();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    EXTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Hashes an order struct according to the EIP-712 standard.
    /// @dev Computes the EIP-712 typed data hash for the given order.
    /// @param order The order to hash.
    /// @return The EIP-712 typed data hash.
    function hashOrder(Order calldata order) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                order.seller,
                order.price,
                order.nftContract,
                order.expiration,
                order.taker,
                order.nonce,
                order.tokenId
            )
        );
        return _hashTypedDataV4(structHash);
    }

    /// @notice Returns the EIP-712 domain separator used by the contract.
    /// @return The domain separator hash.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Adds a new order to the marketplace with signature verification.
    /// @dev Validates the order, signature, and creates a new listing.
    /// @param order The order struct containing all order details.
    /// @param signature The EIP-712 signature from the seller.
    /// @return orderDigest The hash of the created order.
    function addOrder(Order calldata order, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
        returns (bytes32 orderDigest)
    {
        if (activeOrderHash[order.nftContract][order.tokenId] != bytes32(0)) revert AlreadyListed();

        IERC721 token = IERC721(order.nftContract);
        orderDigest = hashOrder(order);
        address signer = ECDSA.recover(orderDigest, signature);
        uint64 currentNonce = nonces[signer];

        if (order.expiration != 0 && order.expiration <= block.timestamp) revert OrderExpired();
        if (signer != order.seller) revert SignerMustBeSeller();
        if (signer == address(0)) revert ZeroAddress();
        if (order.price < 1e13) revert OrderPriceTooLow();
        if (orders[orderDigest].seller != address(0)) revert AlreadyListed();
        if (order.nonce != currentNonce) revert NonceIncorrect();
        if (!order.nftContract.supportsInterface(type(IERC721).interfaceId)) {
            revert NonERC721Interface();
        }
        if (
            token.getApproved(order.tokenId) != address(this)
                && !token.isApprovedForAll(order.seller, address(this))
        ) {
            revert MarketplaceNotApproved();
        }
        if (signer != token.ownerOf(order.tokenId)) revert NotTokenOwner();

        nonces[signer] = currentNonce + 1;
        orders[orderDigest] = order;
        activeOrderHash[order.nftContract][order.tokenId] = orderDigest;

        emit OrderListed(orderDigest, signer, order.nftContract, order.tokenId, order.price);
    }

    /// @notice Fulfills an order by purchasing the NFT at the listed price.
    /// @dev Handles payment, fee calculation, and NFT transfer.
    /// @param orderHash The hash of the order to fulfill.
    function fulfillOrder(bytes32 orderHash) public payable nonReentrant whenNotPaused {
        bool success = _fulfillOrderInternal(orderHash, msg.value);
        if (!success) {
            (bool refunded,) = msg.sender.call{ value: msg.value }("");
            if (!refunded) revert RefundFailed();
            revert OrderFulfillmentFailed();
        }
    }

    /// @notice Retrieves the details of a specific order.
    /// @param orderHash The hash of the order to retrieve.
    /// @return An Order struct containing the order details.
    function getOrder(bytes32 orderHash) public view returns (Order memory) {
        return orders[orderHash];
    }

    /// @notice Removes an order from the marketplace.
    /// @dev Only the order creator can remove their own order.
    /// @param orderHash The hash of the order to remove.
    function removeOrder(bytes32 orderHash) public nonReentrant whenNotPaused {
        bool success = _removeOrderInternal(orderHash);
        if (!success) revert OrderRemovalFailed();
    }

    /// @notice Removes multiple orders in a single transaction.
    /// @dev Batch operation for removing orders, limited to 25 orders per transaction.
    /// @param orderHashes Array of order hashes to remove.
    /// @return results Array of OrderResult structs indicating success/failure for each order.
    function batchRemoveOrder(bytes32[] calldata orderHashes)
        external
        nonReentrant
        whenNotPaused
        returns (OrderResult[] memory results)
    {
        uint256 batchSize = orderHashes.length;
        if (batchSize == 0 || batchSize > MAX_BATCH_SIZE) revert InvalidBatchSize();

        results = new OrderResult[](batchSize);
        for (uint256 i = 0; i < batchSize; ++i) {
            results[i].orderHash = orderHashes[i];
            results[i].success = _removeOrderInternal(orderHashes[i]);
        }
    }

    /// @notice Fulfills multiple orders in a single transaction.
    /// @dev Batch operation for fulfilling orders, limited to MAX_BATCH_SIZE orders per transaction.
    /// @param orderHashes Array of order hashes to fulfill.
    /// @return results Array of OrderResult structs indicating success/failure for each order.
    function batchfulfillOrder(bytes32[] calldata orderHashes)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (OrderResult[] memory results)
    {
        uint256 batchSize = orderHashes.length;
        if (batchSize == 0 || batchSize > MAX_BATCH_SIZE) revert InvalidBatchSize();

        for (uint256 i = 0; i < batchSize; ++i) {
            for (uint256 j = i + 1; j < batchSize; ++j) {
                if (orderHashes[i] == orderHashes[j]) revert DuplicateOrderHash();
            }
        }

        Order[] memory orderCache = new Order[](batchSize);
        uint256 totalRequired = 0;

        for (uint256 i = 0; i < batchSize; ++i) {
            orderCache[i] = getOrder(orderHashes[i]);

            if (orderCache[i].seller != address(0)) {
                totalRequired += orderCache[i].price;
            }
        }

        if (msg.value != totalRequired) revert OrderPriceWrong();

        results = new OrderResult[](batchSize);
        uint256 totalRefund = 0;

        for (uint256 i = 0; i < batchSize; ++i) {
            results[i].orderHash = orderHashes[i];
            results[i].success =
                _fulfillOrderInternal(orderHashes[i], orderCache[i], orderCache[i].price);

            if (!results[i].success) {
                totalRefund += orderCache[i].price;
            }
        }

        if (totalRefund > 0) {
            (bool refunded,) = msg.sender.call{ value: totalRefund }("");
            if (!refunded) revert RefundFailed();
        }
    }

    function claimProceeds() external nonReentrant {
        uint256 amount = claimableProceeds[msg.sender];
        if (amount == 0) revert NoProceedsToClaim();

        claimableProceeds[msg.sender] = 0;

        (bool success,) = msg.sender.call{ value: amount }("");
        if (!success) {
            claimableProceeds[msg.sender] = amount;
            revert ClaimFailed();
        }

        emit ProceedsClaimed(msg.sender);
    }

    /// @notice Allows the owner to withdraw accumulated fees from the contract.
    function withdrawFees() external onlyOwner {
        uint256 amount = pendingFees;
        if (amount == 0) revert FeeWithdrawlFailed();
        pendingFees = 0;
        (bool ok,) = owner().call{ value: amount }("");
        if (!ok) {
            pendingFees = amount;
            revert FeeWithdrawlFailed();
        }

        emit FeesWithdrawn();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    fallback() external {
        revert CallNotSupported();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTERNAL FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Internal function to fulfill an order using pre-loaded order data.
    /// @dev Optimized version for batch operations to avoid redundant storage reads.
    /// @param orderHash The hash of the order to fulfill.
    /// @param order Pre-loaded order data from memory.
    /// @param value The amount of ETH sent with the transaction.
    /// @return success Whether the order fulfillment was successful.
    function _fulfillOrderInternal(bytes32 orderHash, Order memory order, uint256 value)
        internal
        returns (bool)
    {
        IERC721 token = IERC721(order.nftContract);

        if (order.seller == address(0)) return false;
        if (value != order.price) return false;
        if (order.taker != address(0) && order.taker != msg.sender) return false;

        if (order.expiration != 0 && order.expiration <= block.timestamp) {
            delete orders[orderHash];
            delete activeOrderHash[order.nftContract][order.tokenId];
            emit OrderRemoved(orderHash);
            return false;
        } else if (token.ownerOf(order.tokenId) != order.seller) {
            delete orders[orderHash];
            delete activeOrderHash[order.nftContract][order.tokenId];
            emit OrderRemoved(orderHash);
            return false;
        } else if (
            token.getApproved(order.tokenId) != address(this)
                && !token.isApprovedForAll(order.seller, address(this))
        ) {
            delete orders[orderHash];
            delete activeOrderHash[order.nftContract][order.tokenId];
            emit OrderRemoved(orderHash);
            return false;
        } else {
            // [Same fulfillment logic as before]
            uint256 fee = (order.price * FEE_BPS) / 1e4;
            uint256 sellerProceeds = order.price - fee;

            pendingFees += fee;
            claimableProceeds[order.seller] += sellerProceeds;
            delete orders[orderHash];
            delete activeOrderHash[order.nftContract][order.tokenId];

            token.transferFrom(order.seller, msg.sender, order.tokenId);

            emit OrderFulfilled(orderHash, msg.sender);
            return true;
        }
    }

    /// @notice Original internal function for single order fulfillment.
    function _fulfillOrderInternal(bytes32 orderHash, uint256 value) internal returns (bool) {
        Order memory order = getOrder(orderHash);
        return _fulfillOrderInternal(orderHash, order, value);
    }

    /// @notice Internal function to remove an order from the marketplace.
    /// @dev Validates that the caller is the order creator and removes the order.
    /// @param orderHash The hash of the order to remove.
    /// @return success Whether the order removal was successful.
    function _removeOrderInternal(bytes32 orderHash) internal returns (bool) {
        Order memory order = orders[orderHash];

        if (order.seller == address(0)) return false;
        if (order.seller != msg.sender) return false;

        delete orders[orderHash];
        delete activeOrderHash[order.nftContract][order.tokenId];
        emit OrderRemoved(orderHash);
        return true;
    }
}
