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

### Installation & Setup

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-username/mini-mart.git
    cd mini-mart
    ```

2.  **Install dependencies:**
    ```bash
    forge install
    ```

3.  **Set up environment variables:**
    Create a `.env` file in the root of the project. This file is required for deploying to live networks and verifying contracts on Etherscan.

    ```sh
    # .env
    # For live network deployments (e.g., 'make deploy')
    RPC_URL=https://your_rpc_provider_url
    WALLET_ID=your_keystore_wallet_alias # e.g., my_wallet.json
    KEYSTORE_PASSWORD=your_keystore_password

    # For Etherscan verification
    ETHERSCAN_API_KEY=your_etherscan_api_key
    ```


### Deployment

The deployment commands require a script file from the `script/` directory to be passed as an argument.

*   **Deploy to a Local Network (Anvil):**
    This command uses the `DeployLocal.s.sol` script, which not only deploys the contracts but also seeds the local environment by whitelisting the test NFT, minting tokens, and creating/removing sample orders.

    1.  Start a local Anvil node in a separate terminal:
        ```bash
        anvil
        ```
    2.  Run the local deployment script:
        ```bash
        make deploy-local DeployLocal.s.sol
        ```

*   **Deploy to a Live Network:**
    This requires `RPC_URL`, `WALLET_ID`, and `KEYSTORE_PASSWORD` to be set in your `.env` file. The `Deploy.s.sol` script is a template and must be filled out before use.

    ```bash
    # Example: Dry-run a deployment without broadcasting the transaction
    make dry-run Deploy.s.sol

    # Example: Execute the deployment and broadcast the transaction
    make deploy Deploy.s.sol
    ```


## Contract Overview

### `MiniMart.sol`

This is the core contract. It implements the EIP-712 standard to create verifiable off-chain order data.

**Order Flow:**
1.  **Seller:** Creates an `Order` struct with sale details (price, tokenId, etc.) and signs its EIP-712 hash.
2.  **Buyer:** Submits the `Order` struct and the seller's `signature` to the `addOrder()` function. The contract verifies the signature and lists the order.
3.  **Buyer:** Calls `fulfillOrder()` with the correct `msg.value` to purchase the NFT. The contract verifies all conditions (e.g., ownership, approval), transfers the NFT to the buyer, and pays the seller (minus fees).
