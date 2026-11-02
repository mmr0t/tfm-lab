// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MiniToken, SimpleAMM} from "./Vulnerable.sol";

// Caso C7 - Versión corregida.
// El colateral se valora con un oráculo TWAP (precio medio ponderado en el
// tiempo) construido sobre el acumulador del propio AMM, al estilo de Uniswap V2.
// Una manipulación dentro de una única transacción no mueve el TWAP: el precio
// alterado solo empezaría a pesar a medida que pasan segundos, y el atacante
// tendría que sostenerlo (con capital propio y expuesto a arbitraje) durante
// toda la ventana. En producción se usaría además Chainlink con validación de
// frescura como fuente principal o de contraste.

/// @notice Oráculo TWAP de ventana fija sobre `SimpleAMM`.
/// Guarda una observación (acumulador y marca de tiempo) y devuelve la media del
/// precio entre esa observación y el momento actual.
contract OraculoTWAP {
    SimpleAMM public immutable amm;
    uint256 public immutable periodo; // ventana mínima en segundos

    uint256 public acumuladoObservado;
    uint256 public instanteObservado;

    constructor(address a, uint256 _periodo) {
        amm = SimpleAMM(a);
        periodo = _periodo;
        _observar();
    }

    /// @notice Registra una nueva observación cuando la anterior ya cubre la
    /// ventana. Cualquiera puede llamarla (en producción lo hace un keeper).
    function actualizar() external {
        require(block.timestamp - instanteObservado >= periodo, "ventana no cumplida");
        _observar();
    }

    function _observar() internal {
        acumuladoObservado = amm.precioAcumuladoActual();
        instanteObservado = block.timestamp;
    }

    /// @notice Precio medio (USDC por token, 18 decimales) desde la observación.
    function precio() external view returns (uint256) {
        uint256 transcurrido = block.timestamp - instanteObservado;
        require(transcurrido >= periodo, "TWAP sin ventana suficiente");
        return (amm.precioAcumuladoActual() - acumuladoObservado) / transcurrido;
    }
}

/// @notice Protocolo de préstamos que valora el colateral con el TWAP.
contract PrestamosFixed {
    MiniToken public token;
    MiniToken public usdc;
    OraculoTWAP public oraculo;
    mapping(address => uint256) public colateral;
    mapping(address => uint256) public deuda;

    constructor(address t, address u, address o) {
        token = MiniToken(t);
        usdc = MiniToken(u);
        oraculo = OraculoTWAP(o);
    }

    function precioToken() public view returns (uint256) {
        return oraculo.precio();
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

    function isSolved() external view returns (bool) {
        return usdc.balanceOf(address(this)) == 0;
    }
}
