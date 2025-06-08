// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

contract MiniMart is Ownable, EIP712, ReentrancyGuard {
    bytes32 public immutable DOMAIN_SEPARATOR;

    uint8 public constant FEE_BPS = 15;
    address public feeRecipient;

    struct Order {
        uint256 price;
        address nftContract;
        uint256 tokenId;
        address seller;
        uint256 expiration;
        uint256 nonce;
    }

    bytes32 public constant ORDER_TYPEHASH =
        keccak256(
            "Order(uint256 price,address nftContract,uint256 tokenId,address seller,uint256 expiration,uint256 nonce)"
        );

    mapping(bytes32 orderhash => Order) public orders;

    mapping(address => uint256) public nonces;

    event FeeRecipientUpdated(address indexed newRecipient);
    event OrderListed(
        bytes32 indexed orderId,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );

    error NotTokenOwner();
    error SignerMustBeSeller();
    error ZeroAddress();
    error AlreadyListed();
    error OrderExpired();
    error NonceIncorrect();
    error OrderPriceTooLow();
    error NonERC721Interface();

    constructor(
        address initialOwner,
        string memory name,
        string memory version
    ) Ownable(initialOwner) EIP712(name, version) {
        feeRecipient = initialOwner;
        DOMAIN_SEPARATOR = _domainSeparatorV4();
    }

    function addOrder(
        Order calldata order,
        bytes calldata signature
    ) public nonReentrant returns (bytes32) {
        IERC721 token = IERC721(order.nftContract);

        bytes32 orderDigest = _hashOrder(order);

        address signer = ECDSA.recover(orderDigest, signature);
        uint256 currentNonce = nonces[signer];

        /// @dev if order expiration is zero, then it does not expire
        if (order.expiration != 0) {
            require(order.expiration > block.timestamp, OrderExpired());
        }

        require(
            IERC165(order.nftContract).supportsInterface(0x80ac58cd),
            NonERC721Interface()
        );
        require(signer == token.ownerOf(order.tokenId), NotTokenOwner());
        require(signer == order.seller, SignerMustBeSeller());
        require(signer != address(0), ZeroAddress());
        require(order.price > 10000000000000 wei, OrderPriceTooLow());
        require(orders[orderDigest].seller == address(0), AlreadyListed());
        require(order.nonce == currentNonce, NonceIncorrect());

        nonces[signer] += 1;

        orders[orderDigest] = order;

        emit OrderListed(
            orderDigest,
            signer,
            order.nftContract,
            order.tokenId,
            order.price
        );

        return orderDigest;
    }

    function getOrder(
        bytes32 orderHash
    ) public view returns (MiniMart.Order memory) {
        return orders[orderHash];
    }

    function _hashOrder(Order calldata order) internal view returns (bytes32) {
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

        return EIP712._hashTypedDataV4(structHash);
    }

    // Admin Functions

    function updateFeeRecipient(
        address newRecipient
    ) external onlyOwner nonReentrant {
        require(newRecipient != address(0), ZeroAddress());

        feeRecipient = newRecipient;

        emit FeeRecipientUpdated(newRecipient);
    }

    receive() external payable {
        Address.sendValue(payable(feeRecipient), msg.value);
    }
}
