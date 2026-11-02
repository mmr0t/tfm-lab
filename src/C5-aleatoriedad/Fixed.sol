// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C5 - Versión corregida.
// La aleatoriedad debe ser imprevisible en el momento de apostar. El estándar de
// la industria es Chainlink VRF (azar generado fuera de la cadena y entregado en
// una transacción posterior, con prueba criptográfica). Como en el laboratorio no
// hay oráculo, se ilustra con un esquema de "bloque futuro": el jugador se
// compromete en un bloque y el sorteo usa el blockhash de ese bloque, que todavía
// no existe cuando se ejecuta `entrar()`. El ataque de "calcular y jugar solo si
// gano" deja de ser posible.
//
// Riesgo residual (documentado en la memoria): quien propone el bloque conoce su
// hash y podría retenerlo; por eso en producción se usa VRF.

/// @notice Lotería en dos fases.
/// `entrar()` fija al jugador y el bloque de compromiso; nunca paga en el acto.
/// `sortear()` se ejecuta más tarde, la puede llamar cualquiera, y decide con el
/// blockhash del bloque de compromiso.
contract LoteriaFixed {
    /// @notice La EVM solo expone el hash de los últimos 256 bloques.
    uint256 public constant VENTANA = 256;

    address public jugador;
    uint256 public commitBlock;

    constructor() payable {}

    function entrar() external payable {
        require(msg.value == 1 ether, "1 ETH");
        require(jugador == address(0), "ronda ocupada");
        jugador = msg.sender;
        commitBlock = block.number;
    }

    function sortear() external {
        require(jugador != address(0), "sin jugador");
        // Debe haber pasado al menos un bloque para que blockhash exista.
        require(block.number > commitBlock, "espera al siguiente bloque");

        address ganador = jugador;
        jugador = address(0); // la ronda se libera siempre (no hay bloqueo)

        // Si han pasado más de 256 bloques, blockhash devuelve 0. La ronda se
        // cierra como perdida: devolver la apuesta daría al jugador una opción
        // gratuita (esperar a que caduque cuando sabe que pierde).
        if (block.number - commitBlock > VENTANA) return;

        bytes32 h = blockhash(commitBlock);
        uint256 aleatorio = uint256(keccak256(abi.encodePacked(h)));
        if (aleatorio % 2 == 0) {
            payable(ganador).transfer(address(this).balance);
        }
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}
