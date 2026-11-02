// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MiniToken} from "../C7-oraculo-flashloan/Vulnerable.sol";

// Caso C8 - Versión corregida.
// Mitigación del ataque de inflación con "virtual shares/assets" (offset), el
// mismo enfoque que aplica OpenZeppelin en ERC4626: se añade un offset virtual
// que hace inviable el truncamiento a 0 y la donación directa deja de ser
// rentable. Se redondea siempre en contra del usuario.

/// @notice Vault con shares/assets virtuales (offset de decimales).
contract VaultFixed {
    MiniToken public asset;
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    // Offset virtual (OZ usa 10**_decimalsOffset(); aquí 1e3 como ejemplo).
    uint256 private constant OFFSET = 1e3;

    constructor(address a) {
        asset = MiniToken(a);
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function deposit(uint256 assets) external returns (uint256 sharesMinted) {
        // Se suman shares y assets virtuales: aunque el atacante done tokens, la
        // relación no se puede inflar hasta truncar al siguiente depositante.
        sharesMinted = (assets * (totalShares + OFFSET)) / (totalAssets() + 1);
        asset.transferFrom(msg.sender, address(this), assets);
        shares[msg.sender] += sharesMinted;
        totalShares += sharesMinted;
    }

    function redeem(uint256 s) external returns (uint256 assets) {
        assets = (s * (totalAssets() + 1)) / (totalShares + OFFSET);
        shares[msg.sender] -= s;
        totalShares -= s;
        asset.transfer(msg.sender, assets);
    }
}

/// @notice Variante B corregida: redondeo en contra del usuario.
/// La comisión se redondea hacia arriba (ceil), de modo que nunca es cero para un
/// intercambio con valor y el usuario no puede pagar de menos. Además se exige una
/// cantidad mínima que garantice una comisión no nula.
contract CambioFixed {
    MiniToken public tokenA;
    MiniToken public tokenB;
    uint256 public constant FEE_BPS = 30; // 0,3 %

    constructor(address a, address b) {
        tokenA = MiniToken(a);
        tokenB = MiniToken(b);
    }

    function cambiar(uint256 amount) external {
        // Redondeo hacia arriba: ceil(amount * FEE_BPS / 10000).
        uint256 fee = (amount * FEE_BPS + 9999) / 10000;
        require(fee > 0, "cantidad demasiado pequena");
        uint256 salida = amount - fee;
        tokenA.transferFrom(msg.sender, address(this), amount);
        tokenB.transfer(msg.sender, salida);
    }
}

/// @notice Variante C corregida: multiplicar antes de dividir.
/// Se escala la recompensa por 1e18 antes de dividir, de modo que el cociente
/// conserva 18 decimales de precisión y la pérdida por truncamiento queda en
/// menos de una unidad mínima por token depositado.
contract RepartoFixed {
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
        // Multiplicar antes de dividir: la precisión se conserva.
        recompensaPorToken += (recompensa * 1e18) / totalDepositado;
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
