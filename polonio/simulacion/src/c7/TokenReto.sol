// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice ERC20 mínimo del reto (TOKEN). Solo quien lo despliega puede acuñar.
contract TokenReto {
    string public constant name = "TOKEN";
    uint8 public constant decimals = 18;
    address public immutable admin;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        admin = msg.sender;
    }

    function mint(address to, uint256 a) external {
        require(msg.sender == admin, "solo admin");
        balanceOf[to] += a;
        totalSupply += a;
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        _t(msg.sender, to, a);
        return true;
    }

    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        require(al >= a, "allowance");
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        _t(f, to, a);
        return true;
    }

    function _t(address f, address to, uint256 a) internal {
        require(balanceOf[f] >= a, "balance");
        balanceOf[f] -= a;
        balanceOf[to] += a;
    }
}
