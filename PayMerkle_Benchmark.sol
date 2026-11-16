// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PayMerkle_Benchmark {
    struct chainInfo {
        bytes32 root;          // Merkle tree root (RN)
        uint256 denomination;  // Denomination (in wei)
        uint256 chainLen;      // Total tokens (n = 1024)
        uint256 csLen;         // Proof length (log2(n) + 1 = 11 elements: s_i + 10 siblings)
        uint256 redemption;    // Current redeemed position
        bool exists;
    }

    address private immutable _vendor;
    address private immutable _funder;
    uint256 public immutable expiry;
    bool private _locked;
    mapping(string => chainInfo) private _chains;

    event FinalVerification(uint256[] CS, string name);

    // 輔助計算 PayMerkle Root 函式（供測試前產生 Root 使用）
    function computePayMerkleRoot(
        uint256[] memory CS,
        uint256 number
    ) external pure returns (bytes32) {
        uint256 state = number - 1;
        // 1st hash: compute leaf node h(i || s_i)
        bytes32 hash = keccak256(abi.encodePacked(number, CS[0]));
        // Remaining 10 hashes: merge with 10 sibling nodes CS[1..10]
        for (uint256 i = 1; i < CS.length; i++) {
            hash = ((state >> (i - 1)) & 1 == 1)
                ? keccak256(abi.encodePacked(CS[i], hash))
                : keccak256(abi.encodePacked(hash, CS[i]));
        }
        return hash;
    }

    constructor(
        address payable vendor,
        uint256 duration,
        chainInfo[] memory chains,
        string[] memory names
    ) payable {
        require(vendor != address(0), "Invalid vendor address");
        require(names.length == chains.length && chains.length > 0, "Wrong format");
        _vendor = vendor;
        _funder = msg.sender;
        expiry = block.timestamp + duration;

        uint256 totalLiability = 0;
        for (uint256 i = 0; i < chains.length; i++) {
            require(!_chains[names[i]].exists, "Duplicate chain name");
            require(chains[i].chainLen > 0 && chains[i].denomination > 0, "Invalid params");
            _chains[names[i]] = chainInfo({
                root: chains[i].root,
                denomination: chains[i].denomination,
                chainLen: chains[i].chainLen,
                csLen: chains[i].csLen,
                redemption: 0,
                exists: true
            });
            totalLiability += chains[i].chainLen * chains[i].denomination;
        }
        require(msg.value == totalLiability, "Escrow must equal total liability");
    }

    function redemptionAndRemittance(
        uint256[][] memory CSs,
        uint256[] memory numbers,
        string[] memory names
    ) external {
        require(!_locked, "Reentrancy blocked");
        _locked = true;
        require(msg.sender == _vendor, "Not vendor");
        require(block.timestamp <= expiry, "Channel expired");
        require(CSs.length == numbers.length && numbers.length == names.length, "Wrong format");

        verification(CSs, numbers, names);
        convertToETH(numbers, names);

        for (uint256 i = 0; i < CSs.length; i++) {
            if (_chains[names[i]].redemption == _chains[names[i]].chainLen) {
                delete _chains[names[i]];
                emit FinalVerification(CSs[i], names[i]);
            }
        }
        _locked = false;
    }

    function verification(
        uint256[][] memory CSs,
        uint256[] memory numbers,
        string[] memory names
    ) private view {
        for (uint256 i = 0; i < CSs.length; i++) {
            singleVerification(CSs[i], numbers[i], names[i]);
        }
    }

    function singleVerification(
        uint256[] memory CS,
        uint256 number,
        string memory name
    ) private view {
        chainInfo memory c = _chains[name];
        require(c.exists, "Chain does not exist");
        require(CS.length == c.csLen, "Invalid proof length");
        require(number > c.redemption && number <= c.chainLen, "Out of bounds or already redeemed");

        uint256 state = number - 1;
        // Extra hash operation required by PayMerkle to compute leaf h(i || s_i)
        bytes32 hash = keccak256(abi.encodePacked(number, CS[0]));
        // log2(1024) = 10 hash operations along the Merkle path
        for (uint256 i = 1; i < CS.length; i++) {
            hash = ((state >> (i - 1)) & 1 == 1)
                ? keccak256(abi.encodePacked(CS[i], hash))
                : keccak256(abi.encodePacked(hash, CS[i]));
        }
        require(c.root == hash, "Invalid Merkle proof");
    }

    function convertToETH(
        uint256[] memory numbers,
        string[] memory names
    ) private {
        uint256 total = 0;
        for (uint256 i = 0; i < numbers.length; i++) {
            total += (numbers[i] - _chains[names[i]].redemption) * _chains[names[i]].denomination;
            _chains[names[i]].redemption = numbers[i];
        }
        (bool success, ) = payable(_vendor).call{value: total}("");
        require(success, "ETH transfer failed");
    }
}