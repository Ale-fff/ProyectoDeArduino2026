#pragma once

// Servidor GATT.
//
// AISLAMIENTO: toda la API de BLE vive en este par de archivos. Si hay que
// migrar de la API clasica BLE* a NimBLE-Arduino 2.x (core 4.0), el cambio
// se limita a src/ble_service.cpp; ningun otro modulo depende de el.

#include <stddef.h>
#include <stdint.h>

class CommandRouter;

namespace BleService {

// Callback invocado cuando se desconecta un cliente, para que el router
// pueda abortar cualquier movimiento en curso.
using DisconnectHook = void (*)(void* user);

void begin(CommandRouter& router, DisconnectHook onDisconnect, void* user);

// Hay que llamar a esto desde loop(). Reanuda el anuncio si el cliente se
// desconectó. No se hace dentro del callback de desconexión a propósito:
// compite con el desmontaje de la conexión y falla en silencio, dejando el
// módulo invisible hasta reiniciar el ESP.
void service();

bool isConnected();

}  // namespace BleService
