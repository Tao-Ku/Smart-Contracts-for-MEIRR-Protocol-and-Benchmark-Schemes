// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MEIRR {
    struct chainInfo {
        bytes32 root;          // Merkle tree root of the chain (RN)
        uint256 denomination;  // Denomination of the chain (in wei)
        uint256 chainLen;      // Total length of the chain (n)
        uint256 csLen;         // Required CS length (Tree Height H = log2(n/j) + 1)
        uint256 j;             // Redemption parameter j (RP = 2 * j)
        uint256 redemption;    // Current cumulative redeemed position
        bool exists;           // Guard against duplicate chain names
    }

    address private immutable _vendor;
    address private immutable _funder;
    uint256 public immutable expiry;
    bool private _locked;      // Reentrancy guard

    mapping(string => chainInfo) private _chains;

    event FinalVerification(uint256[] CS, string name);

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
            require(chains[i].chainLen > 0 && chains[i].denomination > 0, "Invalid chain params");
            require(chains[i].csLen >= 2 && chains[i].j > 0, "Invalid tree params");
            require(
                chains[i].chainLen == chains[i].j * (1 << (chains[i].csLen - 1)),
                "Mismatched n, j, and csLen"
            );

            _chains[names[i]] = chainInfo({
                root: chains[i].root,
                denomination: chains[i].denomination,
                chainLen: chains[i].chainLen,
                csLen: chains[i].csLen,
                j: chains[i].j,
                redemption: 0,
                exists: true
            });

            totalLiability += chains[i].chainLen * chains[i].denomination;
        }
        require(msg.value == totalLiability, "Escrow must equal total liability");
    }
    // Initialize contract to store chains information and verify full ETH escrow
    // names are chain names, for example: A-chain and B-chain in our MEIRR

    function redemptionAndRemittance(
        uint256[][] memory CSs,
        uint256[] memory numbers,
        string[] memory names
    ) external {
        require(!_locked, "Reentrancy blocked");
        _locked = true;

        require(msg.sender == _vendor, "Not vendor");
        require(block.timestamp <= expiry, "Channel expired");
        require(
            CSs.length == numbers.length && numbers.length == names.length,
            "Wrong format"
        );

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
    // Check if the chain is exhausted. Remove the chain and emit events to record in the blockchain's transaction logs

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
        require(c.exists, "Chain does not exist or already closed");
        require(CS.length == c.csLen, "Invalid CS length");

        uint256 twoJ = 2 * c.j;
        require(
            number > c.redemption && number <= c.chainLen,
            "Amount out of bounds or already redeemed"
        );
        require(number % twoJ == 0, "Number must align with redemption period 2j");

        uint256 state = (number / twoJ) - 1;
        bytes32 hash = keccak256(abi.encodePacked(CS[0], CS[1]));
        for (uint256 i = 2; i < CS.length; i++) {
            hash = ((state >> (i - 2)) & 1 == 1)
                ? keccak256(abi.encodePacked(CS[i], hash))
                : keccak256(abi.encodePacked(hash, CS[i]));
        }
        require(c.root == hash, "Invalid cryptographic slice");
        // Merge tree according to state and verify against root
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

    function claimRefund(string[] memory names) external {
        require(!_locked, "Reentrancy blocked");
        _locked = true;
        require(msg.sender == _funder, "Not funder");
        require(block.timestamp > expiry, "Channel still active");

        uint256 refundWei = 0;
        for (uint256 i = 0; i < names.length; i++) {
            if (_chains[names[i]].exists) {
                refundWei += (_chains[names[i]].chainLen - _chains[names[i]].redemption) * _chains[names[i]].denomination;
                delete _chains[names[i]];
            }
        }
        (bool success, ) = payable(_funder).call{value: refundWei}("");
        require(success, "Refund failed");
        _locked = false;
    }
    // Reclaim unspent ETH collateral after channel expiration
}