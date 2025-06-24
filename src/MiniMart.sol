// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title MiniMart
 * @author mulf: https://github.com/mulfdev
 * @notice A lightweight, signature-based ERC721 marketplace.
 */
contract MiniMart is Ownable, Pausable, EIP712, ReentrancyGuard {
    using ERC165Checker for address;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new order is successfully listed.
    /// @param orderId The unique hash of the order.
    /// @param seller The address of the seller.
    /// @param nftContract The address of the NFT contract.
    /// @param tokenId The ID of the token being listed.
    /// @param price The price of the token in wei.
    event OrderListed(
        bytes32 indexed orderId,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );

    /// @notice Emitted when an order is removed from the marketplace.
    /// @param orderId The unique hash of the removed order.
    event OrderRemoved(bytes32 indexed orderId);

    /// @notice Emitted when an order is successfully fulfilled.
    /// @param orderId The unique hash of the fulfilled order.
    /// @param buyer The address of the buyer.
    event OrderFulfilled(bytes32 indexed orderId, address indexed buyer);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The signer of the order must be the seller.
    error SignerMustBeSeller();
    /// @notice The provided address cannot be the zero address.
    error ZeroAddress();
    /// @notice The order has already been listed.
    error AlreadyListed();
    /// @notice The order has expired.
    error OrderExpired();
    /// @notice The provided nonce is incorrect.
    error NonceIncorrect();
    /// @notice The order price is below the minimum threshold.
    error OrderPriceTooLow();
    /// @notice The contract does not support the ERC721 interface.
    error NonERC721Interface();
    /// @notice The caller is not the creator of the listing.
    error NotListingCreator();
    /// @notice The seller is not the owner of the token.
    error NotTokenOwner();
    /// @notice The specified order was not found.
    error OrderNotFound();
    /// @notice The number of orders in a batch operation is invalid.
    error InvalidBatchSize();
    /// @notice The contract does not have pending fees for the owner to collect.
    error FeeWithdrawlFailed();
    /// @notice The value of a transaction was too wrong for the order.
    error OrderPriceWrong();
    /// @notice The marketplace contract is not approve for the given token id.
    error MarketplaceNotApproved();
    /// @notice The order value could not be sent to the seller.
    error CouldNotPaySeller();
    /// @notice The buyer couldnt be refunded on purchase;
    error RefundFailed();
    /// @notice The msg.sender for a private order is invalid
    error InvalidTaker();
    /// @notice generic error for fallback function
    error CallNotSupported();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STRUCTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice A struct representing a sell order for an NFT.
    struct Order {
        /// @dev The address of the seller.
        address seller;
        /// @dev The price of the NFT in wei.
        uint96 price;
        /// @dev The contract address of the NFT.
        address nftContract;
        /// @dev The Unix timestamp (seconds) when the order expires. 0 means no expiration.
        uint64 expiration;
        /// @dev The address of the intended buyer for a private sale. If set to address(0), the order is public.
        address taker;
        /// @dev The seller's nonce for this order, used to prevent replay attacks.
        uint64 nonce;
        /// @dev The ID of the token being sold.
        uint256 tokenId;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        STATE VARIABLES                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The fee percentage in basis points (e.g., 300 = 3%).
    uint16 public constant FEE_BPS = 300;

    /// @notice type hash of the order struct for the hashOrder function
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(address seller,uint96 price,address nftContract,uint64 expiration,address taker,uint64 nonce,uint256 tokenId)"
    );

    /// @notice Mapping from an order hash to the corresponding Order struct.
    mapping(bytes32 orderHash => Order) public orders;

    /// @notice Mapping from a seller's address to their current nonce.
    mapping(address seller => uint64 nonce) public nonces;

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

    /**
     * @notice Hashes an order struct according to the EIP-712 standard.
     * @dev Computes the EIP-712 typed data hash for the given order.
     * @param order The order to hash.
     * @return The EIP-712 typed data hash.
     */
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

    /**
     * @notice Adds a new order to the marketplace after verifying the signature.
     * @dev Validates the order details, checks ownership, and ensures the order is unique.
     *      Increments the seller's nonce upon successful listing.
     * @param order The Order struct containing the listing details.
     * @param signature The EIP-712 signature of the order hash from the seller.
     * @return orderDigest The unique hash of the newly created order.
     */
    function addOrder(Order calldata order, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
        returns (bytes32 orderDigest)
    {
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
        if (!token.isApprovedForAll(order.seller, address(this))) revert MarketplaceNotApproved();
        if (signer != token.ownerOf(order.tokenId)) revert NotTokenOwner();

        nonces[signer] = currentNonce + 1;
        orders[orderDigest] = order;

        emit OrderListed(orderDigest, signer, order.nftContract, order.tokenId, order.price);
    }

    /**
     * @notice Fulfills an existing order by purchasing the NFT.
     * @dev Validates the order, handles payment, transfers the NFT, and distributes fees.
     *      The order is deleted after successful fulfillment.
     * @param orderHash The hash of the order to fulfill.
     */
    function fulfillOrder(bytes32 orderHash) external payable nonReentrant whenNotPaused {
        Order memory order = getOrder(orderHash);
        IERC721 token = IERC721(order.nftContract);

        if (order.seller == address(0)) revert OrderNotFound();
        if (msg.value != order.price) revert OrderPriceWrong();
        if (order.taker != address(0) && order.taker != msg.sender) {
            revert InvalidTaker();
        }

        bool shouldRefund = false;

        // Check for expired orders
        if (order.expiration != 0 && order.expiration <= block.timestamp) {
            shouldRefund = true;
        }
        // Check for ownership changes
        else if (token.ownerOf(order.tokenId) != order.seller) {
            shouldRefund = true;
        }
        // Check for approval changes
        else if (!token.isApprovedForAll(order.seller, address(this))) {
            shouldRefund = true;
        }

        // Clean up order in all cases
        delete orders[orderHash];

        if (shouldRefund) {
            // Refund buyer and emit removal event
            (bool ok,) = msg.sender.call{ value: msg.value }("");
            if (!ok) revert RefundFailed();
            emit OrderRemoved(orderHash);
        } else {
            // Execute successful trade
            token.transferFrom(order.seller, msg.sender, order.tokenId);
            uint256 fee = (order.price * FEE_BPS) / 1e4;
            (bool orderPayment,) = order.seller.call{ value: order.price - fee }("");
            if (!orderPayment) revert CouldNotPaySeller();
            emit OrderFulfilled(orderHash, msg.sender);
        }
    }
    /**
     * @notice Retrieves the details of a specific order.
     * @param orderHash The hash of the order to retrieve.
     * @return An Order struct containing the order details.
     */

    function getOrder(bytes32 orderHash) public view returns (Order memory) {
        return orders[orderHash];
    }

    /**
     * @notice Removes a listed NFT sell order.
     * @dev Reverts if the order doesn't exist or the caller is not its creator.
     * @param orderHash The EIP‑712 hash of the order to remove.
     */
    function removeOrder(bytes32 orderHash) external {
        _removeOrder(orderHash);
    }

    /**
     * @notice Removes multiple orders in a single transaction.
     * @dev The caller must be the creator of all orders in the batch.
     *      Batch size is limited to prevent excessive gas usage. Reverts if
     *      any order in the batch does not exist or was not created by the caller.
     * @param orderHashes An array of order hashes to be removed.
     */
    function batchRemoveOrder(bytes32[] calldata orderHashes) external {
        uint256 batchSize = orderHashes.length;

        if (batchSize == 0 || batchSize > 25) {
            revert InvalidBatchSize();
        }

        for (uint256 i = 0; i < batchSize;) {
            _removeOrder(orderHashes[i]);
            unchecked {
                ++i;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev The internal logic for removing a single order from the marketplace.
     *      This function is called by `removeOrder` and `batchRemoveOrder`.
     *      It performs the necessary checks to ensure the order exists and that
     *      the caller is the original seller before deleting the order from storage.
     * @param orderHash The unique EIP-712 hash of the order to be removed.
     */
    function _removeOrder(bytes32 orderHash) private {
        Order memory order = orders[orderHash];

        if (order.seller == address(0)) revert OrderNotFound();
        if (order.seller != msg.sender) revert NotListingCreator();

        delete orders[orderHash];

        emit OrderRemoved({ orderId: orderHash });
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Allows the owner to withdraw accumulated fees from the contract.
     * @dev Transfers the entire contract balance to the owner. Reverts if the transfer fails.
     */
    function withdrawFees() external onlyOwner {
        (bool ok,) = owner().call{ value: address(this).balance }("");

        if (!ok) revert FeeWithdrawlFailed();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Allows the contract to receive ETH directly.
     * @dev This can be used for donations or other direct payments to the contract.
     */
    receive() external payable { }

    fallback() external payable {
        revert CallNotSupported();
    }
}
