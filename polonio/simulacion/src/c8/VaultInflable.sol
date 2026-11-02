// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IToken {
    function balanceOf(address a) external view returns (uint256);
    function transfer(address to, uint256 a) external returns (bool);
    function transferFrom(address f, address to, uint256 a) external returns (bool);
}

/// @notice Vault estilo ERC-4626 sin participaciones virtuales ni depósito
/// mínimo. Las participaciones se calculan con una división que trunca.
contract VaultInflable {
    IToken public immutable asset;
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    constructor(address a) {
        asset = IToken(a);
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function deposit(uint256 assets) external returns (uint256 sharesMinted) {
        sharesMinted = totalShares == 0
            ? assets
            : (assets * totalShares) / totalAssets(); // trunca: puede dar 0
        asset.transferFrom(msg.sender, address(this), assets);
        shares[msg.sender] += sharesMinted;
        totalShares += sharesMinted;
    }

    function redeem(uint256 s) external returns (uint256 assets) {
        assets = (s * totalAssets()) / totalShares;
        shares[msg.sender] -= s;
        totalShares -= s;
        asset.transfer(msg.sender, assets);
    }
}
