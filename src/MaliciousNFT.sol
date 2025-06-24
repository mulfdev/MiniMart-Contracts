// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import { TestNFT } from "./TestNFT.sol";
import { MiniMart } from "./MiniMart.sol";

contract MaliciousNFT is TestNFT {
    MiniMart internal mart;
    bytes32 internal orderHash;

    constructor(string memory fixedURI, address initialOwner) TestNFT(fixedURI, initialOwner) { }

    function setAttack(MiniMart _mart, bytes32 _orderHash) external {
        mart = _mart;
        orderHash = _orderHash;
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        super.transferFrom(from, to, tokenId); // Do the transfer first
        if (address(mart) != address(0)) {
            // Attempt to re-enter fulfillOrder
            mart.fulfillOrder{ value: 1 ether }(orderHash);
        }
    }
}
