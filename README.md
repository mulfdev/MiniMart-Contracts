# Mini-Mart: A Lightweight ERC721 Marketplace

Mini-Mart is a gas-efficient, signature-based (EIP-712) ERC721 marketplace contract built with the [Foundry](https://github.com/foundry-rs/foundry) framework. It allows users to list NFTs for sale with off-chain signatures, minimizing gas costs for sellers. The marketplace logic is executed on-chain only during the fulfillment of an order.

## Core Features

*   **On-Chain Order Fulfillment:** A buyer fills the seller's signed order to the contract, and the `fulfillOrder` function atomically handles payment, fee collection, and NFT transfer.
*   **Buyer Protection:** If an order cannot be fulfilled (e.g., the NFT was transferred, approval was revoked, or the listing expired), the buyer's payment is automatically refunded within the same transaction.
*   **Fixed Platform Fee:** A 3% fee is collected on every successful sale.
*   **Admin Controls:**
    *   **Pausable:** The owner can pause and unpause all trading activity (`addOrder`, `fulfillOrder`) in case of an emergency.
    *   **Fee Withdrawal:** The owner can withdraw all accumulated fees from the contract.
*   **Comprehensive Testing:** The project includes an extensive test suite using Foundry, covering unit tests, negative paths, and fuzz testing.


## Getting Started

### Prerequisites

*   [Foundry](https://book.getfoundry.sh/getting-started/installation): You will need `forge` and `anvil` installed.
*   [Slither](https://github.com/crytic/slither): For static analysis.
*   [Mythril](https://github.com/Consensys/mythril): For symbolic execution analysis.



### Deployment
```sh 
forge script script/Deploy.s.sol --account mulf-deployer --broadcast
```

## Contract Overview

### `MiniMart.sol`

This is the core contract. It implements the EIP-712 standard to create verifiable order data.

**Order Flow:**
1.  **Seller:** Creates an `Order` struct with sale details (price, tokenId, etc.) and signs its EIP-712 hash.
2.  **Buyer:** Submits the `Order` struct and the seller's `signature` to the `addOrder()` function. The contract verifies the signature and lists the order.
3.  **Buyer:** Calls `fulfillOrder()` with the correct `msg.value` to purchase the NFT. The contract verifies all conditions (e.g., ownership, approval), transfers the NFT to the buyer, and pays the seller (minus fees).
