// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Caso C4 - delegatecall y proxies (OWASP SC10, SWC-112).
// Variante A: delegatecall a una dirección arbitraria controlada por el atacante.
// Variante B: colisión de almacenamiento entre proxy e implementación.
// Variante C: implementación sin inicializar detrás de un proxy actualizable.

/// @notice Variante A: delegatecall arbitrario.
/// `ejecutar` delega a una dirección que decide quien llama. Como el código se
/// ejecuta sobre el storage del monedero, el atacante puede sobrescribir `owner`
/// (slot 0) y apropiarse del contrato.
contract MonederoVulnerable {
    address public owner; // slot 0

    constructor() payable {
        owner = msg.sender;
    }

    function ejecutar(address logica, bytes calldata data) external {
        // FALLO: destino arbitrario y sin control de acceso.
        (bool ok, ) = logica.delegatecall(data);
        require(ok, "delegatecall fallido");
    }

    function retirar() external {
        require(msg.sender == owner, "solo owner");
        payable(msg.sender).transfer(address(this).balance);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

/// @notice Contrato malicioso. Al ejecutarse vía delegatecall escribe en el
/// slot 0 del monedero (owner), porque comparte el layout.
contract Malicioso {
    address public owner; // mismo slot 0 que MonederoVulnerable

    function pwn() external {
        owner = msg.sender; // sobrescribe MonederoVulnerable.owner
    }
}

// Variante B: colisión de almacenamiento

/// @notice Proxy ingenuo: guarda la implementación en el slot 0.
contract ProxyVulnerable {
    address public implementation; // slot 0

    constructor(address impl) {
        implementation = impl;
    }

    // Delega todo a la implementación.
    fallback() external payable {
        address impl = implementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

/// @notice Implementación con un layout incompatible: `owner` cae en el slot 0,
/// el mismo que `implementation` del proxy. Escribir owner corrompe el proxy.
contract LogicaVulnerable {
    address public owner; // slot 0 -> COLISIÓN con ProxyVulnerable.implementation

    function setOwner(address o) external {
        owner = o;
    }
}

// Variante C: implementación sin inicializar

/// @notice Lógica actualizable al estilo UUPS: la función de actualización vive
/// en la implementación y está restringida al owner.
/// El proxy se inicializa correctamente (su propio storage queda con owner), pero
/// el contrato de implementación, desplegado por separado, nunca se inicializa ni
/// bloquea su inicializador. Cualquiera puede llamar a `initialize` directamente
/// sobre la implementación y convertirse en su owner.
contract LogicaUUPSVulnerable is Initializable {
    // bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
    bytes32 private constant IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public owner;

    // FALLO: falta un constructor que llame a _disableInitializers().
    function initialize(address _owner) external initializer {
        owner = _owner;
    }

    function upgradeTo(address nueva) external {
        require(msg.sender == owner, "solo owner");
        assembly {
            sstore(IMPL_SLOT, nueva)
        }
    }

    function implementacion() external view returns (address impl) {
        assembly {
            impl := sload(IMPL_SLOT)
        }
    }
}
