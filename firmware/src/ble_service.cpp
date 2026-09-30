#include "ble_service.h"

#include "log.h"
#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <WiFi.h>
#include <string>

#include "command_router.h"
#include "config.h"

namespace {

BLEServer*         s_server   = nullptr;
BLECharacteristic* s_tx       = nullptr;  // eventos hacia la app
BLECharacteristic* s_rx       = nullptr;  // comandos de la app
BLEService*        s_service  = nullptr;
bool               s_connected = false;

CommandRouter* s_router      = nullptr;
BleService::DisconnectHook s_onDisconnect = nullptr;
void*          s_hookUser    = nullptr;

void notifyRouter(const char* json, void* /*user*/) {
    // Notificar sin conexion deja basura en el stack BLE y en algunos cores
    // provoca un assert. Ademas, un evento sin destinatario no se puede
    // reenviar: la app se entera del estado al reconectar con get_config.
    if (!s_tx || !s_connected) return;

    const std::string payload(json);
    if (payload.empty() || payload.size() > MAX_EVENT_BYTES) return;

    // La API clasica del core: setValue() copia el buffer, y notify() empuja
    // la characteristic. No existe BLEServer::notifyPushedValues() en este
    // core, asi que el aviso va por la propia characteristic.
    s_tx->setValue(payload);
    s_tx->notify();
}

class ServerCallbacksImpl : public BLEServerCallbacks {
    void onConnect(BLEServer* /*server*/) override {
        s_connected = true;
        PV_LOG_PRINTLN("[ble] cliente conectado");
        // No se ajustan los parametros de conexion. En este core
        // updateConnParams() exige la direccion del par, y el callback
        // onConnect(BLEServer*) no la recibe. El intervalo por defecto del
        // stack sirve de sobra: este canal manda un comando cada pocos
        // segundos y el unico dato que viaja seguido son eventos de 200 bytes.
    }

    void onDisconnect(BLEServer* /*server*/) override {
        s_connected = false;
        PV_LOG_PRINTLN("[ble] cliente desconectado");
        // Nunca dejar el servo presionando la manija sin supervision.
        if (s_onDisconnect) s_onDisconnect(s_hookUser);
    }
};

class RxCallbacksImpl : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* chr) override {
        if (!chr) return;
        const std::string value = chr->getValue();
        if (value.empty()) return;
        if (s_router) s_router->handleRaw(value.c_str(), value.size());
    }
};

}  // namespace

namespace BleService {

void begin(CommandRouter& router, DisconnectHook onDisconnect, void* user) {
    s_router      = &router;
    s_onDisconnect = onDisconnect;
    s_hookUser    = user;

    router.setSink(&notifyRouter, nullptr);

    // Nombre: prefijo + ultimos 4 digitos del MAC, para distinguir varios
    // modulos si el usuario tiene mas de una puerta.
    const String mac = WiFi.macAddress();
    String name = DEVICE_NAME_PREFIX;
    if (mac.length() >= 4) name += mac.substring(mac.length() - 4);

    // BLEDevice::init() toma std::string, no el String de Arduino. Es un
    // error de compilacion silencioso si se pasa el String: no hay conversion
    // implicita entre los dos.
    BLEDevice::init(std::string(name.c_str()));
    BLEDevice::setMTU(BLE_MTU);
    // Anuncio ajustado al caso de uso: el modulo esta pegado a una puerta y
    // solo hay que encontrarlo, no rastrearlo.
    BLEDevice::setPower(ESP_PWR_LVL_P9);

    s_server = BLEDevice::createServer();
    s_server->setCallbacks(new ServerCallbacksImpl());

    s_service = s_server->createService(SERVICE_UUID);

    s_tx = s_service->createCharacteristic(
        CHAR_TX_UUID, BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
    // CCCD: sin esto el notify no llega en algunos stacks.
    s_tx->addDescriptor(new BLE2902());

    s_rx = s_service->createCharacteristic(
        CHAR_RX_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
    s_rx->setCallbacks(new RxCallbacksImpl());

    s_service->start();
    BLEDevice::startAdvertising();

    PV_LOG_PRINTF("[ble] anunciando como %s  (servicio %s)\n", name.c_str(), SERVICE_UUID);
}

bool isConnected() { return s_connected; }

}  // namespace BleService
