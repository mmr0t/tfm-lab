// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IToken {
    function balanceOf(address a) external view returns (uint256);
    function approve(address s, uint256 a) external returns (bool);
}

interface IVault {
    function deposit(uint256 assets) external returns (uint256);
}

/// @notice La víctima: tiene 500 ASSET y una transacción de depósito pendiente.
/// En una red pública su transacción esperaría en la cola y el atacante podría
/// adelantarse a ella. En la red local del reto no hay cola de transacciones, así
/// que cualquiera puede "liberar" el depósito llamando a depositar() una vez.
contract DepositanteHonesto {
    IToken public immutable asset;
    IVault public immutable vault;
    bool public depositado;

    constructor(address a, address v) {
        asset = IToken(a);
        vault = IVault(v);
    }

    function depositar() external {
        require(!depositado, "ya depositado");
        depositado = true;
        uint256 saldo = asset.balanceOf(address(this));
        asset.approve(address(vault), saldo);
        vault.deposit(saldo);
    }
}
