// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IToken {
    function balanceOf(address a) external view returns (uint256);
    function transfer(address to, uint256 a) external returns (bool);
    function transferFrom(address f, address to, uint256 a) external returns (bool);
}

interface IAmm {
    function getReserves() external view returns (uint256, uint256);
}

/// @notice Protocolo de préstamos que valora el colateral con el precio SPOT
/// del AMM. Un préstamo flash puede mover ese precio en la misma transacción.
contract PrestamosVulnerable {
    IToken public immutable token;
    IToken public immutable usdc;
    IAmm public immutable amm;
    mapping(address => uint256) public colateral;
    mapping(address => uint256) public deuda;

    constructor(address t, address u, address a) {
        token = IToken(t);
        usdc = IToken(u);
        amm = IAmm(a);
    }

    // FALLO: precio spot leído directo de las reservas.
    function precioToken() public view returns (uint256) {
        (uint256 rt, uint256 ru) = amm.getReserves();
        return (ru * 1e18) / rt;
    }

    function depositar(uint256 amt) external {
        token.transferFrom(msg.sender, address(this), amt);
        colateral[msg.sender] += amt;
    }

    function pedir(uint256 amt) external {
        uint256 maxDeuda = (colateral[msg.sender] * precioToken()) / 1e18;
        require(deuda[msg.sender] + amt <= maxDeuda, "sobre-colateralizado");
        deuda[msg.sender] += amt;
        usdc.transfer(msg.sender, amt);
    }

    /// @notice Condición de éxito: el protocolo se queda sin USDC.
    function isSolved() external view returns (bool) {
        return usdc.balanceOf(address(this)) == 0;
    }
}
