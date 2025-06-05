// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Thrown when an invalid zero address is provided.
error InvalidAddress();

/// @notice Thrown when `msg.value` does not equal the specified price.
error IncorrectEthAmount(uint256 provided, uint256 required);

/// @notice Thrown when an order's expiration timestamp has passed.
error SignatureExpired(uint64 expirationTimestamp);

/// @notice Thrown when the provided nonce does not match the expected nonce.
error InvalidNonce(uint256 provided, uint256 expected);

/// @notice Thrown when ECDSA signature recovery fails or signer mismatch occurs.
error InvalidSignature(address recovered, address expected);

/// @notice Thrown when attempting to withdraw but no funds are available.
error NoFundsToWithdraw();

/// @notice Thrown when attempting to update the fee recipient to the zero address.
error FeeRecipientZeroAddress();

/// @notice Thrown when `buyWithSignature` is called with a zero-address seller.
error ZeroSellerAddress();

/// @notice Thrown when seller doesn't own the NFT.
error InvalidOwnership(address seller, address actualOwner);

/// @notice Thrown when contract is not approved to transfer NFT.
error NotApprovedForTransfer();

/// @notice Thrown when any other unexpected invariant failure occurs.
error OperationFailed();

contract MiniMartMarketplace is ReentrancyGuard, EIP712, Ownable {
    using Address for address payable;
    using ECDSA for bytes32; // This allows digest.recover(signature)

    // ── Constants ──
    uint8 public constant FEE_BPS = 150; // 1.5% fee
    uint256 private constant MAX_BPS = 10000;
    bytes32 private constant ORDER_TYPEHASH =
        keccak256(
            "Order(address nft,uint256 tokenId,uint128 price,uint64 expiration,uint256 nonce,uint256 globalNonce,address seller)"
        );

    // Define the struct for buyWithSignature parameters
    struct BuyOrderParams {
        address nft;
        uint256 tokenId;
        uint128 price;
        uint64 expiration;
        uint256 nonce;
        uint256 globalNonce;
        address seller;
        bytes signature;
    }

    // ── State Variables ──
    address payable public feeRecipient;
    mapping(address => uint256) public globalNonces; // For bulk cancellation
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        public nftNonces; // seller => nft => tokenId => nonce
    mapping(address => uint256) public pendingWithdrawals;

    // ── Events ──
    event OrderFilled(
        address indexed nft,
        uint256 indexed tokenId,
        address indexed seller,
        address buyer,
        uint128 price,
        uint128 fee,
        uint256 nonce
    );

    event OrderCancelled(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 newNonce
    );
    event AllOrdersCancelled(address indexed seller, uint256 newGlobalNonce);
    event FeeRecipientUpdated(
        address indexed previousRecipient,
        address indexed newRecipient
    );

    // ── Constructor ──
    constructor(
        address payable _feeRecipient
    ) EIP712("SignatureNFTMarketplace", "1") Ownable(msg.sender) {
        if (_feeRecipient == address(0)) {
            revert InvalidAddress();
        }
        feeRecipient = _feeRecipient;
    }

    // ── Receive Ether ──
    receive() external payable {
        if (msg.value == 0) {
            revert IncorrectEthAmount(msg.value, 1 wei);
        }
        feeRecipient.sendValue(msg.value);
    }

    // ── Main Functions ──

    /// @notice Purchase an NFT by verifying the seller's EIP-712 signature.
    /// @param params The structured parameters for the buy order.
    function buyWithSignature(
        BuyOrderParams calldata params
    ) external payable nonReentrant {
        // ── Input validation ──
        if (params.seller == address(0)) {
            revert ZeroSellerAddress();
        }

        if (block.timestamp > params.expiration) {
            revert SignatureExpired(params.expiration);
        }

        if (msg.value != params.price) {
            revert IncorrectEthAmount(msg.value, params.price);
        }

        // ── Nonce validation ──
        // NOTE: The line that previously caused the error was related to accessing nftNonces.
        // The local variable `expectedNonce` is still useful for clarity and to avoid multiple map lookups.
        uint256 expectedNonce = nftNonces[params.seller][params.nft][
            params.tokenId
        ];
        if (params.nonce != expectedNonce) {
            revert InvalidNonce(params.nonce, expectedNonce);
        }

        // ── Global nonce validation (for bulk cancellation) ──
        uint256 expectedGlobalNonce = globalNonces[params.seller];
        if (params.globalNonce != expectedGlobalNonce) {
            revert InvalidNonce(params.globalNonce, expectedGlobalNonce);
        }

        // ── NFT ownership verification ──
        address actualOwner = IERC721(params.nft).ownerOf(params.tokenId);
        if (actualOwner != params.seller) {
            revert InvalidOwnership(params.seller, actualOwner);
        }

        // ── Approval verification ──
        if (
            IERC721(params.nft).getApproved(params.tokenId) != address(this) &&
            !IERC721(params.nft).isApprovedForAll(params.seller, address(this))
        ) {
            revert NotApprovedForTransfer();
        }

        // ── Signature verification ──
        // The ORDER_TYPEHASH should still match the layout of parameters used for signing
        bytes32 structHash = keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                params.nft,
                params.tokenId,
                params.price,
                params.expiration,
                params.nonce,
                params.globalNonce,
                params.seller
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = digest.recover(params.signature);

        if (recovered == address(0) || recovered != params.seller) {
            revert InvalidSignature(recovered, params.seller);
        }

        // ── Update nonce to prevent replay ──
        // This is the line that was indicated in your original error message.
        // With the struct refactor and potentially other changes, stack pressure is reduced.
        unchecked {
            nftNonces[params.seller][params.nft][params.tokenId] =
                expectedNonce +
                1;
        }

        // ── Calculate fee and seller proceeds ──
        uint256 feeAmount = (uint256(params.price) * FEE_BPS) / MAX_BPS;
        uint256 sellerProceeds;
        unchecked {
            sellerProceeds = uint256(params.price) - feeAmount;
        }

        // ── Update balances ──
        pendingWithdrawals[feeRecipient] += feeAmount;
        pendingWithdrawals[params.seller] += sellerProceeds;

        // ── Transfer NFT ──
        IERC721(params.nft).transferFrom(
            params.seller,
            msg.sender,
            params.tokenId
        );

        emit OrderFilled(
            params.nft,
            params.tokenId,
            params.seller,
            msg.sender,
            params.price,
            uint128(feeAmount),
            params.nonce
        );
    }

    /// @notice Cancel a specific NFT order by bumping its nonce.
    /// @param nft The address of the NFT contract.
    /// @param tokenId The ID of the token whose order is to be cancelled.
    function cancelOrder(address nft, uint256 tokenId) external {
        unchecked {
            nftNonces[msg.sender][nft][tokenId] += 1;
        }
        emit OrderCancelled(
            msg.sender,
            nft,
            tokenId,
            nftNonces[msg.sender][nft][tokenId]
        );
    }

    /// @notice Cancel ALL orders for the caller by bumping their global nonce.
    function cancelAllOrders() external {
        unchecked {
            globalNonces[msg.sender] += 1;
        }
        emit AllOrdersCancelled(msg.sender, globalNonces[msg.sender]);
    }

    /// @notice Withdraw accumulated ETH for the caller.
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) {
            revert NoFundsToWithdraw();
        }

        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).sendValue(amount);
    }

    // ── Admin Functions ──
    /// @notice Update fee recipient (owner only).
    /// @param newRecipient The address of the new fee recipient.
    function updateFeeRecipient(
        address payable newRecipient
    ) external onlyOwner {
        if (newRecipient == address(0)) {
            revert FeeRecipientZeroAddress();
        }
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }
}
