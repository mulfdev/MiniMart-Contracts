// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract MiniMart is Ownable {
    uint8 public constant FEE_BPS = 150;
    address public feeRecipient;

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
