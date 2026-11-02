// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C9 - Lógica de negocio (OWASP SC02).
// El código compila, no tiene reentrada ni overflow, pero implementa mal la regla
// económica: la recompensa se calcula sobre el total depositado en CADA llamada,
// sin descontar lo ya pagado, de modo que se puede reclamar en bucle hasta drenar
// el fondo de recompensas.

/// @notice Staking vulnerable. `reclamar()` no lleva registro de lo ya pagado.
contract StakingVulnerable {
    mapping(address => uint256) public depositado;
    uint256 public constant TASA = 100; // % de recompensa

    constructor() payable {} // se despliega con un fondo de recompensas

    function depositar() external payable {
        depositado[msg.sender] += msg.value;
    }

    // FALLO: paga la recompensa completa en cada llamada, sin descontar nada.
    function reclamar() external {
        uint256 recompensa = (depositado[msg.sender] * TASA) / 100;
        payable(msg.sender).transfer(recompensa);
    }

    /// @notice Condición de éxito: el fondo queda a cero.
    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}
