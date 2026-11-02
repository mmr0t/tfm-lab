# C1. Control de acceso: writeup

Este documento explica cómo resolver el reto del caso C1 y las otras dos variantes que se estudian en el laboratorio. El análisis completo está en la sección 4.1 de la memoria.

## El reto: La Bóveda sin Dueño

En Polonio el reto se llama `BovedaSinDueno`. En el laboratorio, el mismo contrato es `BovedaVulnerable` (`src/C1-control-acceso/Vulnerable.sol`).

**Escenario.** Una bóveda se despliega con 10 ETH. Quien la despliega es su propietario (`owner`) y es la única cuenta que puede retirar los fondos.

**Objetivo.** Vaciar la bóveda desde la cuenta del jugador, que no es la propietaria. El reto se da por resuelto cuando `isSolved()` devuelve `true`, es decir, cuando el saldo de la bóveda es 0.

## La vulnerabilidad

La función que retira los fondos sí está protegida:

```solidity
function withdrawAll() external {
    require(msg.sender == owner, "solo owner");
    payable(msg.sender).transfer(address(this).balance);
}
```

El problema está en otra función, que cambia quién es el propietario sin comprobar quién la llama:

```solidity
// FALLO: sin control de acceso. Cualquiera puede apropiarse del contrato.
function setOwner(address newOwner) external {
    owner = newOwner;
}
```

La protección de `withdrawAll` depende de `owner`, y `owner` lo puede cambiar cualquiera. Por eso la protección no sirve de nada. Es el fallo de control de acceso en su forma más simple: una función que modifica un estado crítico sin restringir quién puede llamarla.

## Resolución paso a paso

1. **Leer todas las funciones `external` y `public`.** Para cada una, la pregunta es la misma: ¿comprueba quién la llama? `deposit` no necesita hacerlo, `withdrawAll` lo hace y `setOwner` no lo hace. Esa es la puerta de entrada.
2. **Apropiarse del contrato.** Desde la cuenta del jugador, llamar a `setOwner(<dirección del jugador>)`. Tras esta llamada, `owner()` devuelve tu dirección.
3. **Retirar los fondos.** Llamar a `withdrawAll()`. Ahora la comprobación `msg.sender == owner` se cumple y los 10 ETH llegan a tu cuenta.
4. **Verificar.** `isSolved()` devuelve `true`. En Polonio, pulsa *Verificar solución*.

No hace falta ningún contrato atacante: son dos transacciones normales desde tu cuenta.

## Otras variantes del caso

El laboratorio incluye dos variantes más, que no forman parte del reto de Polonio.

**Autorización con `tx.origin`** (`WalletTxOriginVulnerable`). La cartera autoriza con `require(tx.origin == owner)`. `tx.origin` es la cuenta que firmó la transacción, no quien hace la llamada actual. El ataque es un *phishing*:

1. El atacante despliega un contrato señuelo (`Phishing` en la prueba) con una función de aspecto inofensivo, por ejemplo `reclamaPremio()`.
2. Engaña al propietario para que la llame.
3. Esa función llama a la cartera y pide transferir todo al atacante. Durante toda la cadena, `tx.origin` sigue siendo el propietario, así que la cartera autoriza la transferencia.

**Inicialización desprotegida** (`BovedaInicializableVulnerable`). El propietario no se fija en el constructor, sino en una función `initialize` pensada para llamarse una sola vez. Como no comprueba quién la llama ni si ya se ejecutó, el atacante la llama con su dirección, pasa a ser propietario y retira los fondos. Es el fallo del primer incidente de Parity (julio de 2017).

## Mitigación

La versión corregida (`src/C1-control-acceso/Fixed.sol`) no escribe el control de acceso a mano: usa `Ownable` de OpenZeppelin, que fija el propietario en el constructor y protege tanto la retirada como el cambio de propietario.

```solidity
contract BovedaFixed is Ownable {
    constructor() payable Ownable(msg.sender) {}

    function withdrawAll() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
```

Para las otras variantes:

- **`tx.origin`**: autorizar siempre con `msg.sender`. Así un contrato intermedio no puede actuar en nombre de la víctima.
- **Inicialización**: usar el modificador `initializer` de OpenZeppelin, que solo deja ejecutar la función una vez, e inicializar en la misma transacción del despliegue.

Como regla general, toda función que cambie estado sensible (propiedad, permisos, parámetros, fondos) necesita control de acceso, no solo las que mueven dinero.

## Comprobarlo en el laboratorio

```bash
./forge test --match-contract C1_ControlAcceso
./forge test --match-contract C1_ControlAcceso --match-test test_Exploit_Vulnerable -vvvv
```

| Variante | Ataque | Mitigación |
|---|---|---|
| Función desprotegida | `test_Exploit_Vulnerable` | `test_Fixed_Resiste` |
| `tx.origin` | `test_Exploit_TxOrigin_Vulnerable` | `test_Fixed_TxOrigin_Resiste` |
| Inicialización | `test_Exploit_Inicializacion_Vulnerable` | `test_Fixed_Inicializacion_Resiste` |

Las pruebas de mitigación exigen el motivo exacto del fallo: el error `OwnableUnauthorizedAccount(attacker)`, el mensaje `no autorizado` o el error `InvalidInitialization`.
