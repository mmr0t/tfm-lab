// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C9 - Versión corregida.
// La recompensa es única: se lleva registro de lo ya reclamado y solo se paga la
// diferencia pendiente. Reclamar en bucle ya no extrae valor.

contract StakingFixed {
    mapping(address => uint256) public depositado;
    mapping(address => uint256) public reclamado;
    uint256 public constant TASA = 100;

    constructor() payable {}

    function depositar() external payable {
        depositado[msg.sender] += msg.value;
    }

    function reclamar() external {
        uint256 total = (depositado[msg.sender] * TASA) / 100;
        uint256 pendiente = total - reclamado[msg.sender]; // descuenta lo pagado
        require(pendiente > 0, "nada pendiente");
        reclamado[msg.sender] += pendiente; // effect antes de la interacción
        payable(msg.sender).transfer(pendiente);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}
