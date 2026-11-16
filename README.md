# Smart Contracts for MEIRR Protocol and Benchmark Schemes

This repository hosts the Solidity smart contract implementations evaluated in our research paper, **"Micropayment to Ethereum with Instant Redemption and Remittance Using Blockchain and Merkle Trees" (MEIRR)**. To ensure a fair, apples-to-apples evaluation of EVM gas consumption, all three contracts—the proposed MEIRR and the two baselines (PayMerkle and EthWord)—are implemented under the exact same security boundaries, including full collateral escrow verification, reentrancy protection, expiration checks, and standard ETH remittance.

---

## Descriptions for Each Contract

### 1. `MEIRR.sol` (The Proposed Scheme)
* **Description:** This is the smart contract implementation of our proposed MEIRR protocol. It leverages a Merkle-tree-based structure where off-chain payword chains serve as leaf nodes. The contract supports setup-configurable redemption periods and multi-denomination batched settlements within a single transaction. It is highly optimized for gas efficiency and features hardened security invariants, including exact period-boundary alignment, strict monotonicity checks, and proof-length validation to prevent replay and tree-truncation attacks.

### 2. `PayMerkle_Benchmark.sol` (Baseline: PayMerkle)
* **Description:** This contract is the benchmark implementation of the PayMerkle micropayment scheme. Instead of utilizing a sequential payment chain, it uses independent random numbers where each hash value serves as a separate leaf node in a Merkle tree. For a reproducible and fair EVM gas comparison, this baseline has been standardized with the exact same security safeguards, mapping structures, and reentrancy protections as the MEIRR contract.

### 3. `EthWord_Benchmark.sol` (Baseline: EthWord)
* **Description:** This is the benchmark implementation of the EthWord micropayment scheme, which verifies a standard sequential payword chain directly on Ethereum. It relies entirely on linear, sequential hash operations on-chain without utilizing a Merkle tree structure. Like the PayMerkle benchmark, this contract has been unified under identical security checks and execution logic to ensure an accurate, apples-to-apples performance evaluation against our proposed MEIRR scheme.

---

## Compilation and Execution Environment

To compile and execute the contracts in **[Remix IDE](https://remix.ethereum.org/)**, please use the following configuration:

* **Execution Environment:** Remix VM (EVM Version: `Osaka`)
* **Solidity Compiler Version:** `0.8.34+commit.80d5c536`
* **Bytecode Optimizer:** Enabled (`runs = 200`)
* **Hash Function:** `keccak256(abi.encodePacked(...))` over 256-bit (`uint256` / `bytes32`) words
* **Denomination Unit:** `wei`
