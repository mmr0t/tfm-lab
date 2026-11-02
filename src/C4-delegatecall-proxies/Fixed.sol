// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Caso C4 - Versiones corregidas.
// Variante A: delegatecall solo a una implementación fija y de confianza, y con
//             control de acceso.
// Variante B: la dirección de implementación se guarda en un slot EIP-1967, que
//             no colisiona con las variables de la lógica.
// Variante C: la implementación bloquea su inicializador en el constructor.

/// @notice Variante A corregida.
/// El destino del delegatecall es inmutable (fijado en el despliegue) y la
/// función queda restringida al owner. El atacante ya no puede elegir el código
/// que se ejecuta sobre el storage del monedero.
contract MonederoFixed {
    address public owner; // slot 0
    address public immutable logica;

    constructor(address _logica) payable {
        owner = msg.sender;
        logica = _logica;
    }

    function ejecutar(bytes calldata data) external {
        require(msg.sender == owner, "solo owner");
        (bool ok, ) = logica.delegatecall(data);
        require(ok, "fallo");
    }

    function retirar() external {
        require(msg.sender == owner, "solo owner");
        payable(msg.sender).transfer(address(this).balance);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}

/// @notice Variante B corregida: proxy con slot EIP-1967.
/// La dirección de implementación vive en un slot pseudoaleatorio
/// (keccak256("eip1967.proxy.implementation") - 1), imposible de colisionar por
/// accidente con las variables de la lógica (que empiezan en el slot 0).
contract ProxyFixed {
    // bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
    bytes32 private constant IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address impl) {
        assembly {
            sstore(IMPL_SLOT, impl)
        }
    }

    function _impl() internal view returns (address impl) {
        assembly {
            impl := sload(IMPL_SLOT)
        }
    }

    fallback() external payable {
        address impl = _impl();
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

/// @notice Misma lógica que la vulnerable; ahora el slot 0 (owner) ya no choca
/// con la dirección de implementación, que está en el slot EIP-1967.
contract LogicaFixed {
    address public owner; // slot 0, sin colisión con el proxy

    function setOwner(address o) external {
        owner = o;
    }
}

/// @notice Variante C corregida.
/// El constructor llama a `_disableInitializers()`, como recomienda OpenZeppelin:
/// la implementación queda inicializada "para siempre" en su propio storage y
/// nadie puede tomar su control. El proxy, cuyo storage es independiente, se
/// sigue inicializando con normalidad.
contract LogicaUUPSFixed is Initializable {
    bytes32 private constant IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public owner;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
