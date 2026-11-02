// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IToken {
    function balanceOf(address a) external view returns (uint256);
    function transfer(address to, uint256 a) external returns (bool);
}

interface IFlashBorrower {
    function onFlashLoan(uint256 amount) external;
}

/// @notice Prestamista flash de USDC sin comisión. Revierte si no se devuelve.
contract PrestamistaFlash {
    IToken public immutable usdc;

    constructor(address u) {
        usdc = IToken(u);
    }

    function flashLoan(uint256 amount) external {
        uint256 saldoAntes = usdc.balanceOf(address(this));
        usdc.transfer(msg.sender, amount);
        IFlashBorrower(msg.sender).onFlashLoan(amount);
        require(usdc.balanceOf(address(this)) >= saldoAntes, "flash no devuelto");
    }
}
