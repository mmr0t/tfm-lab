// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C1 - Versiones corregidas.
// La mitigación estándar es delegar el control de acceso en una librería
// auditada (OpenZeppelin Ownable) y autorizar siempre por msg.sender.
// La variante C usa Initializable para que la inicialización sea única.

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @notice Variante A corregida.
/// La propiedad la gestiona `Ownable`: `transferOwnership` ya es `onlyOwner` y
/// `withdrawAll` queda protegido. No hay forma de apropiarse del contrato.
contract BovedaFixed is Ownable {
    constructor() payable Ownable(msg.sender) {}

    function deposit() external payable {}

    function withdrawAll() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

/// @notice Variante B corregida.
/// Autoriza por `msg.sender`: un contrato intermedio ya no puede actuar en
/// nombre de la víctima, porque `msg.sender` sería el contrato, no el owner.
contract WalletTxOriginFixed {
    address public owner;

    constructor() payable {
        owner = msg.sender;
    }

    receive() external payable {}

    function transfer(address payable to, uint256 amount) external {
        require(msg.sender == owner, "no autorizado");
        to.transfer(amount);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

/// @notice Variante C corregida.
/// `initializer` (OpenZeppelin) garantiza que la función solo se ejecuta una vez.
/// Además, la inicialización se hace en la misma transacción que el despliegue
/// (aquí, desde el constructor), de modo que no existe ninguna ventana en la que
/// un tercero pueda adelantarse.
contract BovedaInicializableFixed is Initializable {
    address public owner;

    constructor(address _owner) payable {
        initialize(_owner);
    }

    function initialize(address _owner) public initializer {
        owner = _owner;
    }

    function deposit() external payable {}

    function withdrawAll() external {
        require(msg.sender == owner, "solo owner");
        payable(msg.sender).transfer(address(this).balance);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}
