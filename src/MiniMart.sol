// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title MiniMart
 * @author mulf: https://github.com/mulfdev
 * @notice A lightweight, signature-based NFT marketplace.
 */
contract MiniMart is Ownable, EIP712, ReentrancyGuard {
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
    error NoPendingFees();
    /// @notice The pending fees could not be withdrawn
    error FeeWithdrawlFailed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STRUCTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice A struct representing a sell order for an NFT.
    struct Order {
        /// @dev The price of the NFT in wei.
        uint256 price;
        /// @dev The ID of the token being sold.
        uint256 tokenId;
        /// @dev The contract address of the NFT.
        address nftContract;
        /// @dev The Unix timestamp (seconds) when the order expires. 0 means no expiration.
        uint64 expiration;
        /// @dev The address of the seller.
        address seller;
        /// @dev The seller's nonce for this order, used to prevent replay attacks.
        uint64 nonce;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        STATE VARIABLES                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The fee percentage in basis points (e.g., 150 = 1.5%).
    uint8 public constant FEE_BPS = 150;

    /// @notice type hash of the order struct for the _hashOrder function
    bytes32 public constant ORDER_TYPEHASH =
        keccak256(
            "Order(uint256 price,address nftContract,uint256 tokenId,address seller,uint64 expiration,uint64 nonce)"
        );

    /// @notice Mapping from an order hash to the corresponding Order struct.
    mapping(bytes32 orderHash => Order order) public orders;

    /// @notice Mapping from a seller's address to their current nonce.
    mapping(address seller => uint64 nonce) public nonces;

    /// @notice storage for fees generated from sales.
    uint256 public pendingFees;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTRUCTOR                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the contract, setting the owner, and EIP-712 domain.
    /// @param initialOwner The initial owner of the contract.
    /// @param name The EIP-712 domain name.
    /// @param version The EIP-712 domain version.
    constructor(
        address initialOwner,
        string memory name,
        string memory version
    ) Ownable(initialOwner) EIP712(name, version) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    EXTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Hashes an order struct according to the EIP-712 standard.
     * @param order The order to hash.
     * @return The EIP-712 typed data hash.
     */
    function _hashOrder(Order calldata order) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                order.price,
                order.nftContract,
                order.tokenId,
                order.seller,
                order.expiration,
                order.nonce
            )
        );

        return _hashTypedDataV4(structHash);
    }

    /// @notice Returns the EIP-712 domain separator used by the contract.
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
    function addOrder(
        Order calldata order,
        bytes calldata signature
    ) external nonReentrant returns (bytes32 orderDigest) {
        IERC721 token = IERC721(order.nftContract);
        orderDigest = _hashOrder(order);

        address signer = ECDSA.recover(orderDigest, signature);
        uint64 currentNonce = nonces[signer];

        if (order.expiration != 0 && order.expiration <= block.timestamp) {
            revert OrderExpired();
        }
        if (signer != order.seller) revert SignerMustBeSeller();
        if (signer == address(0)) revert ZeroAddress();
        if (order.price <= 10000000000000 wei) revert OrderPriceTooLow();
        if (orders[orderDigest].seller != address(0)) revert AlreadyListed();
        if (order.nonce != currentNonce) revert NonceIncorrect();
        if (!order.nftContract.supportsInterface(type(IERC721).interfaceId)) {
            revert NonERC721Interface();
        }
        if (signer != token.ownerOf(order.tokenId)) revert NotTokenOwner();

        nonces[signer] = currentNonce + 1;
        orders[orderDigest] = order;

        emit OrderListed({
            orderId: orderDigest,
            seller: signer,
            nftContract: order.nftContract,
            tokenId: order.tokenId,
            price: order.price
        });
    }

    /**
     * @notice Retrieves the details of a specific order.
     * @param orderHash The hash of the order to retrieve.
     * @return An Order struct containing the order details.
     */
    function getOrder(bytes32 orderHash) external view returns (Order memory) {
        return orders[orderHash];
    }

    /**
     * @notice Removes a listed NFT sell order.
     * @dev Reverts if the order doesn’t exist or the caller is not its creator.
     * @param orderHash The EIP‑712 hash of the order to remove.
     */
    function removeOrder(bytes32 orderHash) external nonReentrant {
        _removeOrder(orderHash);
    }

    /**
     * @notice Removes multiple orders in a single transaction.
     * @dev The caller must be the creator of all orders in the batch.
     *      Batch size is limited to prevent excessive gas usage. Reverts if
     *      any order in the batch does not exist or was not created by the caller.
     * @param orderHashes An array of order hashes to be removed.
     */
    function batchRemoveOrder(
        bytes32[] calldata orderHashes
    ) external nonReentrant {
        uint256 len = orderHashes.length;
        if (len == 0 || len > 25) revert InvalidBatchSize();

        for (uint256 i = 0; i < len; ) {
            _removeOrder(orderHashes[i]);
            unchecked {
                ++i;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _removeOrder(bytes32 orderHash) private {
        Order memory order = orders[orderHash];

        if (order.seller == address(0)) revert OrderNotFound();
        if (order.seller != msg.sender) revert NotListingCreator();

        delete orders[orderHash];

        emit OrderRemoved({orderId: orderHash});
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Allows the owner the withdraw pending fees
     */
    function withdrawFees() external onlyOwner {
        uint256 amount = pendingFees;
        if (amount == 0) revert NoPendingFees();

        pendingFees = 0;

        (bool ok, ) = owner().call{value: amount}("");

        if (!ok) revert FeeWithdrawlFailed();
    }

    /**
     * @notice Adds any eth sent to the contract to pendingFees
     * @dev This can be used for donations or other direct payments to the contract.
     */
    receive() external payable {
        pendingFees += msg.value;
    }
}
