// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MiniToken} from "../C7-oraculo-flashloan/Vulnerable.sol";

// Caso C8 - Errores aritméticos y de precisión (OWASP SC07).
// Ataque de inflación del primer depositante en un vault estilo ERC-4626: el
// atacante manipula la relación shares/assets para que el depósito de la víctima
// se trunque a 0 shares y luego se lo lleva con su única share.

/// @notice Vault vulnerable (sin virtual shares ni depósito mínimo).
/// Las shares se calculan con división entera que trunca hacia abajo, sin offset
/// que lo impida: por eso el primer depositante puede inflar el precio por share.
contract VaultVulnerable {
    MiniToken public asset;
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    constructor(address a) {
        asset = MiniToken(a);
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

/// @notice Variante B: redondeo a favor del usuario (SC07).
/// Un contrato de intercambio entre dos tokens de 1:1 calcula la comisión con
/// una división entera que trunca hacia abajo. Al truncar la comisión, el usuario
/// paga de menos: con cantidades pequeñas la comisión se redondea a cero y el
/// intercambio sale gratis. Repetido en bucle, drena la liquidez del contrato.
contract CambioVulnerable {
    MiniToken public tokenA;
    MiniToken public tokenB;
    uint256 public constant FEE_BPS = 30; // 0,3 %

    constructor(address a, address b) {
        tokenA = MiniToken(a);
        tokenB = MiniToken(b);
    }

    function cambiar(uint256 amount) external {
        // FALLO: la comisión trunca hacia abajo. Si amount < 334, fee = 0.
        uint256 fee = (amount * FEE_BPS) / 10000;
        uint256 salida = amount - fee;
        tokenA.transferFrom(msg.sender, address(this), amount);
        tokenB.transfer(msg.sender, salida);
    }
}

/// @notice Variante C: división antes de multiplicación (SC07).
/// Reparto de recompensas por token depositado, al estilo de los contratos de
/// staking con acumulador. Al dividir la recompensa entre el total depositado
/// ANTES de escalar, el cociente se trunca a un entero de tokens: cualquier
/// recompensa menor que el total depositado se reparte como cero, y el resto de
/// la división se queda bloqueado en el contrato para siempre.
contract RepartoVulnerable {
    MiniToken public token;
    uint256 public totalDepositado;
    uint256 public recompensaPorToken; // acumulada, escalada por 1e18
    mapping(address => uint256) public depositado;
    mapping(address => uint256) public cobradoPorToken;

    constructor(address t) {
        token = MiniToken(t);
    }

    function depositar(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        depositado[msg.sender] += amount;
        totalDepositado += amount;
    }

    function notificarRecompensa(uint256 recompensa) external {
        token.transferFrom(msg.sender, address(this), recompensa);
        // FALLO: divide antes de multiplicar. Si recompensa < totalDepositado,
        // el cociente es 0 y nadie recibe nada.
        recompensaPorToken += (recompensa / totalDepositado) * 1e18;
    }

    function pendiente(address u) public view returns (uint256) {
        return (depositado[u] * (recompensaPorToken - cobradoPorToken[u])) / 1e18;
    }

    function cobrar() external {
        uint256 p = pendiente(msg.sender);
        cobradoPorToken[msg.sender] = recompensaPorToken;
        token.transfer(msg.sender, p);
    }
}
