# C4. delegatecall y proxies: writeup

Este documento explica cómo resolver el reto del caso C4 y las otras dos variantes que se estudian en el laboratorio. El análisis completo está en la sección 4.4 de la memoria.

## El reto: El Monedero Delegado

En Polonio el reto se llama `MonederoDelegado`. En el laboratorio, el contrato equivalente es `MonederoVulnerable` (`src/C4-delegatecall-proxies/Vulnerable.sol`).

**Escenario.** Un monedero guarda 5 ETH. Solo su propietario (`owner`) puede retirarlos. El monedero tiene además una función `ejecutar` que delega la ejecución en otro contrato.

**Objetivo.** Vaciar el monedero sin ser su propietario. El reto se da por resuelto cuando `isSolved()` devuelve `true`, es decir, cuando el saldo del monedero es 0.

## Lo que hay que saber de `delegatecall`

`delegatecall` ejecuta el código de otro contrato, pero **sobre el almacenamiento del contrato que llama**, y con su mismo `msg.sender`. El código delegado no escribe "en la variable `owner`", escribe en una posición de almacenamiento (un *slot*). Las variables se guardan por orden de declaración: la primera ocupa el slot 0, la segunda el slot 1, y así sucesivamente.

## La vulnerabilidad

```solidity
contract MonederoVulnerable {
    address public owner; // slot 0

    // FALLO: destino arbitrario y sin control de acceso.
    function ejecutar(address logica, bytes calldata data) external {
        (bool ok, ) = logica.delegatecall(data);
        require(ok, "delegatecall fallido");
    }

    function retirar() external {
        require(msg.sender == owner, "solo owner");
        payable(msg.sender).transfer(address(this).balance);
    }
}
```

`ejecutar` deja elegir a cualquiera qué código se ejecuta sobre el almacenamiento del monedero. Si ese código escribe en el slot 0, sobrescribe `owner`.

## Resolución paso a paso

1. **Escribir un contrato malicioso** cuya primera variable ocupe también el slot 0 y con una función que la sobrescriba:

   ```solidity
   contract Malicioso {
       address public owner; // mismo slot 0 que el monedero

       function pwn() external {
           owner = msg.sender;
       }
   }
   ```

2. **Desplegar `Malicioso`.**
3. **Hacer que el monedero ejecute `pwn`.** Llama a `ejecutar` con la dirección de `Malicioso` y, como datos, la llamada codificada a `pwn()`. Esos datos son el selector de la función: `0xdd365b8b`, que equivale a `abi.encodeWithSignature("pwn()")`. El código de `pwn` se ejecuta sobre el almacenamiento del monedero y `msg.sender` sigue siendo tu cuenta, así que escribe tu dirección en el slot 0. Ahora `owner()` del monedero devuelve tu dirección.
4. **Retirar.** Llama a `retirar()`. La comprobación `msg.sender == owner` se cumple y los 5 ETH pasan a tu cuenta.
5. **Verificar.** `isSolved()` devuelve `true`.

Este es el mecanismo del robo a Bybit de febrero de 2025: los firmantes de una cartera Safe aprobaron, sin advertirlo, una operación `delegatecall` hacia un contrato del atacante que escribió en el slot 0 de la cartera.

## Otras variantes del caso

**Colisión de almacenamiento** (`ProxyVulnerable` y `LogicaVulnerable`). Un proxy ingenuo guarda la dirección de su implementación en el slot 0, y la implementación declara `owner` como primera variable, también en el slot 0. Basta con llamar a `setOwner(x)` a través del proxy: la escritura cae en el slot 0 del proxy y sustituye el puntero de implementación por `x`. Desde ese momento el proxy delega todo en `x`. Es la causa del ataque a Audius (julio de 2022).

**Implementación sin inicializar** (`LogicaUUPSVulnerable`). En un proxy actualizable, el estado se fija con una función `initialize` que el proxy llama una vez. El proxy queda inicializado, pero el contrato de implementación, desplegado por separado, no. El atacante lee la dirección de la implementación, llama directamente a `initialize` sobre ella, se convierte en su propietario y ejecuta una función reservada (`upgradeTo`). Es el fallo de Parity (noviembre de 2017) y de Wormhole (2022). Desde EIP-6780 ya no se puede destruir la implementación con `SELFDESTRUCT`, y la prueba comprueba que el proxy conserva su propietario.

## Mitigación

La versión corregida (`src/C4-delegatecall-proxies/Fixed.sol`) fija el destino del `delegatecall` en el despliegue y restringe la función al propietario:

```solidity
address public immutable logica;

function ejecutar(bytes calldata data) external {
    require(msg.sender == owner, "solo owner");
    (bool ok, ) = logica.delegatecall(data);
    require(ok, "fallo");
}
```

Para las otras variantes:

- **Colisión**: guardar la dirección de implementación en el slot que fija el estándar EIP-1967, `keccak256("eip1967.proxy.implementation") - 1`, que ninguna variable de la lógica ocupará por accidente.
- **Implementación sin inicializar**: llamar a `_disableInitializers()` en el constructor de la implementación, como recomienda OpenZeppelin.

## Comprobarlo en el laboratorio

```bash
./forge test --match-contract C4_DelegatecallProxies
./forge test --match-contract C4_DelegatecallProxies --match-test test_Exploit_Vulnerable -vvvv
```

Con `-vvvv` se ve en la traza el `delegatecall` hacia `Malicioso` y el cambio del slot 0.

| Variante | Ataque | Mitigación |
|---|---|---|
| `delegatecall` arbitrario | `test_Exploit_Vulnerable` | `test_Fixed_Resiste` |
| Colisión de almacenamiento | `test_Exploit_StorageCollision_Vulnerable` | `test_Fixed_StorageCollision_Resiste` |
| Implementación sin inicializar | `test_Exploit_ImplSinInicializar_Vulnerable` | `test_Fixed_ImplSinInicializar_Resiste` |
