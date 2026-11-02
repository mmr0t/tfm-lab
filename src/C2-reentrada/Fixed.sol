// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C2 - Versiones corregidas.
// Variante A: Checks-Effects-Interactions + ReentrancyGuard de OpenZeppelin.
// Variante B: CEI estricto para que ningún view pueda observarse a medias.

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Variante A corregida.
/// Se actualiza el estado ANTES de la llamada externa (CEI) y además se aplica
/// `nonReentrant` como defensa en profundidad.
contract BancoFixed is ReentrancyGuard {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "sin fondos");

        balances[msg.sender] = 0; // EFFECT antes que INTERACTION

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transferencia fallida");
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

/// @notice Variante B corregida.
/// Se recalcula `totalShares` ANTES de la llamada externa, de modo que
/// `pricePerShare` nunca devuelve un valor inconsistente durante la operación.
contract PoolFixed {
    uint256 private _locked = 1;
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    modifier nonReentrant() {
        require(_locked == 1, "reentrada");
        _locked = 2;
        _;
        _locked = 1;
    }

    function deposit() external payable {
        uint256 minted = totalShares == 0
            ? msg.value
            : (msg.value * totalShares) / (address(this).balance - msg.value);
        shares[msg.sender] += minted;
        totalShares += minted;
    }

    function withdraw(uint256 amount) external nonReentrant {
        uint256 value = (amount * address(this).balance) / totalShares;
        shares[msg.sender] -= amount;
        totalShares -= amount; // EFFECT antes de ceder el control

        (bool ok, ) = msg.sender.call{value: value}("");
        require(ok, "fallo");
    }

    function pricePerShare() external view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return (address(this).balance * 1e18) / totalShares;
    }
}

/// @notice Variante C corregida.
/// CEI en `withdraw` (el saldo se descuenta antes de ceder el control) y el guard
/// de OpenZeppelin en las dos funciones que comparten estado. Con CEI, cuando el
/// receptor reentra en `transfer` su saldo ya es cero.
contract BancoTransferibleFixed is ReentrancyGuard {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function transfer(address to, uint256 amount) external nonReentrant {
        require(balances[msg.sender] >= amount, "saldo insuficiente");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }

    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "sin fondos");

        balances[msg.sender] = 0; // EFFECT antes que INTERACTION

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transferencia fallida");
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}
