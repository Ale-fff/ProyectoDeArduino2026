#include "ble_service.h"

#include "log.h"
#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <WiFi.h>

#include "config.h"

namespace {

BLEServer*         s_server   = nullptr;
BLECharacteristic* s_tx       = nullptr;  // eventos hacia la app
BLECharacteristic* s_rx       = nullptr;  // comandos de la app
BLEService*        s_service  = nullptr;
bool               s_connected = false;
int8_t             s_rssi     = 0;

CommandRouter* s_router      = nullptr;
BleService::DisconnectHook s_onDisconnect = nullptr;
void*          s_hookUser    = nullptr;

void notifyRouter(const char* json, void* /*user*/) {
    if (!s_tx || !s_server) return;
    const size_t len = strlen(json);
    if (len == 0 || len > 200) return;  // el contrato tope en 200 bytes

    s_tx->setValue(reinterpret_cast<const uint8_t*>(json), len);
    // API clasica del core. Si tu version expone BLECharacteristic::notify(),
    // esta linea se puede simplificar a s_tx->notify();
    s_server->notifyPushedValues(s_tx->getHandle());
}

class ServerCallbacksImpl : public BLEServerCallbacks {
    void onConnect(BLEServer* server) override {
        s_connected = true;
        PV_LOG_PRINTLN("[ble] cliente conectado");
        server->getPeerAddr().toString();
        // Intervalo de conexion corto: la app es interactiva.
        server->updateConnParam(6, 12, 0, 400);
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

    BLEDevice::init(name);
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

uint8_t lastRssi() { return static_cast<uint8_t>(s_rssi < 0 ? 0 : s_rssi); }

}  // namespace BleService
