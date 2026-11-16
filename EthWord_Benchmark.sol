// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract EthWord_Benchmark {
    struct chainInfo {
        bytes32 anchor;        // Current anchor payword (initially a_0)
        uint256 denomination;  // Denomination (in wei)
        uint256 chainLen;      // Total length of the chain (n = 1024)
        uint256 redemption;    // Current redeemed position
        bool exists;
    }

    address private immutable _vendor;
    address private immutable _funder;
    uint256 public immutable expiry;
    bool private _locked;
    mapping(string => chainInfo) private _chains;

    event FinalVerification(uint256 payword, string name);

    // 輔助函式：輸入測試 payword 與要連續雜湊的次數 steps (= 1024 / RT)，自動算出初始 anchor a_0
    function computeAnchor(uint256 payword, uint256 steps) external pure returns (bytes32) {
        bytes32 hash = bytes32(payword);
        for (uint256 i = 0; i < steps; i++) {
            hash = keccak256(abi.encodePacked(hash));
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
                anchor: chains[i].anchor,
                denomination: chains[i].denomination,
                chainLen: chains[i].chainLen,
                redemption: 0,
                exists: true
            });
            totalLiability += chains[i].chainLen * chains[i].denomination;
        }
        require(msg.value == totalLiability, "Escrow must equal total liability");
    }

    function redemptionAndRemittance(
        uint256[] memory paywords,
        uint256[] memory numbers,
        string[] memory names
    ) external {
        require(!_locked, "Reentrancy blocked");
        _locked = true;
        require(msg.sender == _vendor, "Not vendor");
        require(block.timestamp <= expiry, "Channel expired");
        require(paywords.length == numbers.length && numbers.length == names.length, "Wrong format");

        verification(paywords, numbers, names);
        convertToETH(paywords, numbers, names);

        for (uint256 i = 0; i < paywords.length; i++) {
            if (_chains[names[i]].redemption == _chains[names[i]].chainLen) {
                delete _chains[names[i]];
                emit FinalVerification(paywords[i], names[i]);
            }
        }
        _locked = false;
    }

    function verification(
        uint256[] memory paywords,
        uint256[] memory numbers,
        string[] memory names
    ) private view {
        for (uint256 i = 0; i < paywords.length; i++) {
            singleVerification(paywords[i], numbers[i], names[i]);
        }
    }

    function singleVerification(
        uint256 payword,
        uint256 number,
        string memory name
    ) private view {
        chainInfo memory c = _chains[name];
        require(c.exists, "Chain does not exist");
        require(number > c.redemption && number <= c.chainLen, "Out of bounds or already redeemed");

        uint256 steps = number - c.redemption;
        bytes32 hash = bytes32(payword);
        for (uint256 i = 0; i < steps; i++) {
            hash = keccak256(abi.encodePacked(hash));
        }
        require(c.anchor == hash, "Invalid payword");
    }

    function convertToETH(
        uint256[] memory paywords,
        uint256[] memory numbers,
        string[] memory names
    ) private {
        uint256 total = 0;
        for (uint256 i = 0; i < numbers.length; i++) {
            total += (numbers[i] - _chains[names[i]].redemption) * _chains[names[i]].denomination;
            _chains[names[i]].redemption = numbers[i];
            _chains[names[i]].anchor = bytes32(paywords[i]);
        }
        (bool success, ) = payable(_vendor).call{value: total}("");
        require(success, "ETH transfer failed");
    }
}