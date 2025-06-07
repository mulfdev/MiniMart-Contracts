// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract MiniMart is Ownable {
    uint8 public constant FEE_BPS = 15;
    address public feeRecipient;

    struct Order {
        uint256 price;
        address nftContract;
        uint256 tokenId;
        address seller;
        uint256 expiration;
    }

    mapping(address => Order) public orders;

    event FeeRecipientUpdated(address indexed newRecipient);

    constructor(address initialOwner) Ownable(initialOwner) {
        feeRecipient = initialOwner;
    }

    function updateFeeRecipient(address newRecipient) external onlyOwner {
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    receive() external payable {
        Address.sendValue(payable(feeRecipient), msg.value);
    }
}
