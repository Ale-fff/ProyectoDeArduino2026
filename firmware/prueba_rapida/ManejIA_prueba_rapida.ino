// ===========================================================================
// ManejIA - Prueba rapida: BLE + un servo MG995
//
// Sketch autonomo para Arduino IDE. Habla el mismo protocolo congelado de
// PROTOCOL.md que la app ManejIA, asi que funciona sin tocarla: el movil
// reconoce la voz, manda {"cmd":"open","seq":N} por BLE y este sketch mueve
// el servo. No hay calibracion ni puerta: reporta calibrated:true siempre.
//
// Librerias: SOLO las incluidas en el paquete arduino-esp32 (BLE).
// Probado contra arduino-esp32 3.2.0 (Bluedroid).
//
// Conexiones (ver PRUEBA_RAPIDA.md):
//   MG995 senal  -> GPIO 18
//   MG995 Vcc    -> fuente externa 5-6 V (NO el pin 5V del devkit)
//   MG995 GND    -> GND comun con el ESP32
// ===========================================================================

#include <Arduino.h>
#include <BLE2902.h>
#include <BLEAdvertising.h>
#include <BLECharacteristic.h>
#include <BLEDevice.h>
#include <BLEServer.h>

// ---------------------------------------------------------------------------
// EDITA AQUI — lo unico que suele hacer falta cambiar
// ---------------------------------------------------------------------------

// GPIO de la senal PWM del servo. El firmware de produccion usa el 4; este
// sketch usa el 18 porque fue el que se verifico funcionando a mano.
const int PIN_SERVO = 18;

// Rango de pulso en microsegundos. MG995 tipico: 1000-2000 us es el recorrido
// util completo. Los extremos 500/2400 us empujan contra los topes mecanicos:
// con carga sobrecalientan el motor y pueden reventar la reductora. Solo para
// autoprueba sin nada enganchado.
const int PULSE_MIN_US = 1000;   // reposo / 0 grados
const int PULSE_MAX_US = 2000;   // tope util / 180 grados

// Posicion de reposo (estado seguro) y posicion de "manija presionada".
// Ambas se acotan contra [PULSE_MIN_US, PULSE_MAX_US], lo que mande la app.
const int REST_US  = 1500;
const int PRESS_US = 1800;

// Tiempo de retencion. YA NO SE USA para volver solo: el servo se queda
// presionado hasta que llegue un `close`. Se conserva porque `config` lo
// publica como campo del contrato y la app lo lee.
const int HOLD_MS = 1500;

// 1 = barre 0/90/180 grados al arrancar, para comprobar el servo sin la app.
// 0 = arranca sin mover nada (lo normal con el MG995 enganchado).
#define SELFTEST_BOOT 0

// ---------------------------------------------------------------------------
// Constantes del protocolo (NO editar: deben coincidir con PROTOCOL.md)
// ---------------------------------------------------------------------------

const char* SERVICE_UUID = "0000ff00-0000-1000-8000-00805f9b34fb";
const char* CHAR_RX_UUID = "0000ff01-0000-1000-8000-00805f9b34fb";
const char* CHAR_TX_UUID = "0000ff02-0000-1000-8000-00805f9b34fb";
const char* NAME_PREFIX  = "ManejIA";   // el prefijo real es "PuertaVoz", pero
                                        // para la prueba se anuncia ManejIA

const uint32_t WATCHDOG_MS = 30000;  // sin ping: volver a reposo
const uint32_t DEBOUNCE_MS = 500;    // mismo cmd seguido: se descarta
const uint16_t MAX_MOVE_MS = 2000;   // corte duro de un movimiento
const uint16_t STATUS_MS   = 5000;   // status periodico

// ---------------------------------------------------------------------------
// PWM — portable entre ESP32 Core 2.x y 3.x
// ---------------------------------------------------------------------------
//
// La API de LEDC cambio por completo en el Core 3.0:
//
//   Core 2.x:  ledcSetup(canal, freq, res) + ledcAttachPin(pin, canal)
//              ledcWrite(canal, duty)
//   Core 3.x:  ledcAttach(pin, freq, res)
//              ledcWrite(pin, duty)
//
// El sketch se compila con las dos. Se eligio hacerlo portable y no fijar una
// version porque este archivo se flashea desde el IDE de Arduino, cuya version
// del core depende de lo que tenga instalado la persona, y no del platformio.ini
// del firmware de produccion.

const int FREQ_PWM    = 50;   // 50 Hz estandar para servos
const int RES_PWM     = 14;  // 14 bits (0 a 16383)

// Solo se usa en el Core 2.x. El canal no importa: el servo es el unico PWM.
#if ESP_ARDUINO_VERSION_MAJOR < 3
const int LEDC_CHANNEL = 0;
#endif

void moverServoUS(int microsegundos) {
  if (microsegundos < PULSE_MIN_US) microsegundos = PULSE_MIN_US;
  if (microsegundos > PULSE_MAX_US) microsegundos = PULSE_MAX_US;
  uint32_t duty = ((uint32_t)microsegundos * 16383) / 20000;
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcWrite(PIN_SERVO, duty);
#else
  ledcWrite(LEDC_CHANNEL, duty);
#endif
}

// ---------------------------------------------------------------------------
// Estado
// ---------------------------------------------------------------------------

enum Estado : uint8_t { IDLE, PRESENTING, HOLDING, RETURNING };

Estado    s_estado      = IDLE;
uint16_t  s_seq         = 0;          // ultimo seq aceptado
uint16_t  s_usActual    = REST_US;
uint16_t  s_usDestino   = REST_US;
uint32_t  s_tFase       = 0;          // millis() del inicio de la fase actual
uint32_t  s_tUltimoCmd  = 0;
uint32_t  s_tPing       = 0;
uint32_t  s_tStatus     = 0;
String    s_lastCmd     = "";

BLECharacteristic* s_txChr = nullptr;
bool               s_connected = false;
bool               s_reanunciar = false;   // reanudar anuncio desde loop()
uint16_t           s_mtuPeer = 23;         // lo negocia el movil al conectar

const char* nombreEstado() {
  switch (s_estado) {
    case PRESENTING: return "PRESENTING";
    case HOLDING:    return "HOLDING";
    case RETURNING:  return "RETURNING";
    default:         return "IDLE";
  }
}

// ---------------------------------------------------------------------------
// BLE — eventos hacia la app (contrato PROTOCOL.md seccion 3)
// ---------------------------------------------------------------------------

void enviarEvento(const String& json) {
  if (!s_txChr || !s_connected) return;

  // La libreria TRUNCA en silencio los notify que no caben (BLECharacteristic.cpp
  // los corta a mtu-3). Con MTU de 23 (el default de Android) un 'config' de
  // ~140 bytes llegaria partido y la app no podria interpretarlo. Avisamos
  // fuerte para que se note en vez de perder el evento en silencio.
  if ((int)json.length() > (int)s_mtuPeer - 3) {
    Serial.printf("[ble] AVISO: evento de %d bytes no cabe en el MTU (%d). "
                  "Se mandara truncado. La app debe pedir MTU.\n",
                  (int)json.length(), (int)s_mtuPeer);
  }

  s_txChr->setValue((uint8_t*)json.c_str(), json.length());
  s_txChr->notify();
}

void enviarAck(const char* action, const char* state) {
  String e = "{\"ev\":\"ack\",\"seq\":" + String(s_seq) +
             ",\"action\":\"" + action + "\",\"state\":\"" + state + "\"}";
  enviarEvento(e);
}

void enviarDone(const char* action, const char* note, uint32_t durMs) {
  String e = "{\"ev\":\"done\",\"seq\":" + String(s_seq) +
             ",\"action\":\"" + action + "\",\"state\":\"REST\",\"dur_ms\":" +
             String(durMs);
  if (note != nullptr && note[0] != '\0') e += ",\"note\":\"" + String(note) + "\"";
  e += "}";
  enviarEvento(e);
}

void enviarError(const char* code, const char* msg) {
  String e = "{\"ev\":\"error\",\"seq\":" + String(s_seq) +
             ",\"code\":\"" + code + "\",\"msg\":\"" + msg + "\"}";
  enviarEvento(e);
}

void enviarPong() {
  String e = "{\"ev\":\"pong\",\"seq\":" + String(s_seq) + "}";
  enviarEvento(e);
}

void enviarConfig() {
  String e = "{\"ev\":\"config\",\"press_us\":" + String(PRESS_US) +
             ",\"rest_us\":" + String(REST_US) +
             ",\"min_us\":" + String(PULSE_MIN_US) +
             ",\"max_us\":" + String(PULSE_MAX_US) +
             ",\"hold_ms\":" + String(HOLD_MS) +
             ",\"calibrated\":true,\"fw\":\"prueba-rapida\"}";
  enviarEvento(e);
}

void enviarStatus() {
  // El `String(...)` inicial no es cosmetico: sin el, la expresion empieza por
  // un `const char[25]` y el `+` con `const char*` de nombreEstado() no
  // compila. Hay que anclar la concatenacion en un String.
  String e = String("{\"ev\":\"status\",\"state\":\"") + nombreEstado() +
             "\",\"servo_us\":" + String(s_usActual) +
             ",\"vrail_ok\":true,\"fw\":\"prueba-rapida\"}";
  enviarEvento(e);
}

// ---------------------------------------------------------------------------
// Movimiento — maquina de estados no bloqueante
// ---------------------------------------------------------------------------

void iniciarMovimiento(uint16_t destino) {
  s_usDestino = destino;
  s_tFase = millis();
  s_estado = (destino > s_usActual) ? PRESENTING : RETURNING;
}

// Interpola hacia el destino a un ritmo fijo: un recorrido completo de 1000 us
// tarda ~1 s, parecido al servo real con carga. Asi el corte duro de 2 s da
// tiempo de sobra y el movimiento se ve suave.
void tickMovimiento() {
  if (s_estado != PRESENTING && s_estado != RETURNING) return;

  uint32_t dt = millis() - s_tFase;
  if (dt > MAX_MOVE_MS) {
    // Corte duro: el firmware real reporta stall y vuelve a reposo.
    s_usActual = s_usDestino;
    moverServoUS(s_usActual);
    s_estado = IDLE;
    enviarDone(s_lastCmd.c_str(), nullptr, MAX_MOVE_MS);
    return;
  }

  int delta = (int)s_usDestino - (int)s_usActual;
  int paso  = delta / 25;             // ~25 pasos por recorrido
  if (paso == 0) paso = (delta > 0) ? 1 : -1;
  s_usActual += paso;

  if ((delta > 0 && s_usActual >= (int)s_usDestino) ||
      (delta < 0 && s_usActual <= (int)s_usDestino)) {
    s_usActual = s_usDestino;
    moverServoUS(s_usActual);

    if (s_estado == PRESENTING && s_usActual >= PRESS_US) {
      // Llego a presionar. El servo SE QUEDA AQUI: el pestillo sigue
      // retraido y la puerta queda desbloqueada hasta que llegue un `close`.
      //
      // Se manda `done` igual, y es lo mas importante de este bloque: sin el
      // `done` la app se queda en fase "ejecutando" con el microfono
      // bloqueado, y no hay forma de cerrar la puerta ni de voz ni a mano.
      s_estado = HOLDING;
      moverServoUS(s_usActual);
      enviarDone(s_lastCmd.c_str(), "holding", dt);
      return;
    }
    s_estado = IDLE;
    enviarDone(s_lastCmd.c_str(), nullptr, dt);
  } else {
    moverServoUS(s_usActual);
  }
}

// ¿Esta el servo quieto y en una posicion conocida?
//
// IDLE    = en reposo, o acaba de llegar a reposo. Nada pendiente.
// HOLDING = en la posicion de pulsacion y se queda ahi.
//
// Las dos cuentan como "reposo" para admitir un comando nuevo. Antes solo
// IDLE lo era, asi que un `close` despues de un `open` se rechazaba en
// silencio: el servo quedaba trabado presionado sin poder volver.
bool enReposo() {
  return s_estado == IDLE || s_estado == HOLDING;
}

// ---------------------------------------------------------------------------
// Router de comandos (contrato PROTOCOL.md seccion 2)
// ---------------------------------------------------------------------------

// Extrae un string entre comillas de "clave":"valor" de un JSON plano.
String jsonStr(const String& json, const char* clave) {
  String k = String("\"") + clave + "\":";
  int i = json.indexOf(k);
  if (i < 0) return "";
  i += k.length();
  if (i >= (int)json.length() || json[i] != '"') return "";
  int fin = json.indexOf('"', i + 1);
  if (fin < 0) return "";
  return json.substring(i + 1, fin);
}

// Extrae un entero de "clave":valor de un JSON plano. -1 si no esta.
long jsonInt(const String& json, const char* clave) {
  String k = String("\"") + clave + "\":";
  int i = json.indexOf(k);
  if (i < 0) return -1;
  i += k.length();
  int fin = json.indexOf(',', i);
  if (fin < 0) fin = json.indexOf('}', i);
  if (fin < 0) return -1;
  String v = json.substring(i, fin);
  v.trim();
  if (!v.length()) return -1;
  for (unsigned int c = 0; c < v.length(); c++) {
    if (!isDigit(v[c]) && !(c == 0 && v[c] == '-')) return -1;
  }
  return v.toInt();
}

void handleRaw(const String& payload) {
  if (!payload.length()) return;

  String cmd = jsonStr(payload, "cmd");
  if (!cmd.length()) {
    enviarError("MALFORMED", "json invalido");
    return;
  }

  long seq = jsonInt(payload, "seq");
  if (seq <= 0 || seq > 65535) {
    enviarError("MALFORMED", "json invalido");
    return;
  }

  // estop es la excepcion a las guardas: siempre se acepta y conserva su seq.
  if (cmd == "estop") {
    s_seq = (uint16_t)seq;
    s_tPing = millis();
    s_lastCmd = "estop";
    enviarAck("estop", nombreEstado());
    if (s_estado == PRESENTING || s_estado == RETURNING) {
      // Corte duro hacia reposo.
      s_tFase = millis();
      s_usDestino = REST_US;
      s_estado = RETURNING;
    } else if (s_estado == HOLDING) {
      // Venia presionado: hay que soltar el pestillo aunque el servo este
      // quieto, asi que se manda al reposo igual.
      s_tFase = millis();
      s_usDestino = REST_US;
      s_estado = RETURNING;
    } else {
      enviarDone("estop", nullptr, 0);
    }
    return;
  }

  // El resto de comandos se descarta si el seq va fuera de orden.
  // NO se toca `s_seq` aqui: si un comando viejo rebaantara el marcador, se
  // reabriria la puerta a repeticiones. `s_seq` solo avanza al ACEPTAR.
  if ((uint16_t)seq <= s_seq) {
    enviarError("STALE_SEQ", "seq fuera de orden");
    return;
  }

  uint32_t ahora = millis();
  if (cmd == s_lastCmd && s_tUltimoCmd && (ahora - s_tUltimoCmd) < DEBOUNCE_MS) {
    s_tUltimoCmd = ahora;
    enviarError("DEBOUNCED", "comando duplicado");
    return;
  }

  s_seq = (uint16_t)seq;
  s_tUltimoCmd = ahora;
  s_tPing = ahora;
  s_lastCmd = cmd;

  if (cmd == "open") {
    enviarAck("open", "PRESENTING");
    iniciarMovimiento(PRESS_US);
  } else if (cmd == "close") {
    enviarAck("close", nombreEstado());
    if (s_estado == IDLE && s_usActual == REST_US) {
      enviarDone("close", "already_at_rest", 0);
    } else {
      // Admite volver desde HOLDING: es el unico modo de soltar el pestillo.
      iniciarMovimiento(REST_US);
    }
  } else if (cmd == "ping") {
    enviarPong();
  } else if (cmd == "get_config") {
    enviarConfig();
  } else if (cmd == "save_config") {
    // La prueba no persiste en NVS: acota y responde con la config vigente.
    enviarConfig();
  } else if (cmd == "calibrate") {
    // La prueba no barre limites reales: responde y deja el servo en reposo.
    enviarConfig();
    if (enReposo() && s_usActual != REST_US) iniciarMovimiento(REST_US);
  } else {
    enviarError("UNKNOWN_CMD", "comando desconocido");
  }
}

// ---------------------------------------------------------------------------
// Callbacks BLE
// ---------------------------------------------------------------------------

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* chr) override {
    if (!chr) return;
    // getValue() devuelve std::string en el BLE del Core 2.x y String en el del
    // 3.x. c_str() existe en los dos tipos, asi que esta linea compila con
    // cualquiera de los dos.
    String value = String(chr->getValue().c_str());
    handleRaw(value);
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    s_connected = true;
    Serial.println("[ble] cliente conectado");
    // La app pide get_config al conectar, pero mandarla aqui tambien no
    // estorba: la pantalla se entera del estado sin esperar al pedido.
    enviarConfig();
  }

  void onDisconnect(BLEServer*) override {
    s_connected = false;
    Serial.println("[ble] cliente desconectado");
    // Como ya no se vuelve solo a reposo, desconectar no suelta el pestillo: el
    // servo se queda donde esta. Un `close` explicito si lo suelta.
    //
    // NO reanunciamos aqui: llamar a startAdvertising() DENTRO del callback
    // compite con el desmontaje de la conexion en el stack, falla en
    // silencio y el modulo deja de anunciarse -> desaparece de la app hasta
    // reiniciar el ESP. Se marca una bandera y se reanuncia desde loop().
    s_reanunciar = true;
  }

  // Android no negocia MTU solo; el movil lo pide explicitamente. Solo
  // registramos el valor para saber si el comando va a caber.
  void onMtuChanged(BLEServer*, esp_ble_gatts_cb_param_t* param) override {
    s_mtuPeer = param->mtu.mtu;
    Serial.printf("[ble] MTU negociado: %d (%d bytes utiles)\n",
                  (int)s_mtuPeer, (int)s_mtuPeer - 3);
  }
};

// ---------------------------------------------------------------------------
// Setup / loop
// ---------------------------------------------------------------------------

void setup() {
  Serial.begin(115200);
  const uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 2000) { /* espera al monitor, max 2 s */ }

  Serial.println();
  Serial.println("==============================================");
  Serial.println("  ManejIA - Prueba rapida BLE + MG995");
  Serial.println("==============================================");

  // PWM
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcAttach(PIN_SERVO, FREQ_PWM, RES_PWM);
#else
  ledcSetup(LEDC_CHANNEL, FREQ_PWM, RES_PWM);
  ledcAttachPin(PIN_SERVO, LEDC_CHANNEL);
#endif
  moverServoUS(REST_US);
  Serial.printf("[servo] GPIO %d, reposo %d us, rango %d-%d us\n",
                PIN_SERVO, REST_US, PULSE_MIN_US, PULSE_MAX_US);

  // BLE
  BLEDevice::init(std::string(NAME_PREFIX));
  BLEDevice::setMTU(247);
  BLEDevice::setPower(ESP_PWR_LVL_P9);

  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService* servicio = server->createService(SERVICE_UUID);

  // TX: eventos hacia la app. El CCCD (BLE2902) hace falta para que el
  // notify llegue en algunos stacks.
  s_txChr = servicio->createCharacteristic(
      CHAR_TX_UUID, BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
  s_txChr->addDescriptor(new BLE2902());

  BLECharacteristic* rxChr = servicio->createCharacteristic(
      CHAR_RX_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rxChr->setCallbacks(new RxCallbacks());

  servicio->start();

  // CRITICO: sin esto el anuncio no lleva el UUID de servicio y la app no ve
  // el dispositivo: el escaneo por servicio sale vacio. setScanResponse deja
  // el nombre en la respuesta de escaneo, que tambien ayuda a que aparezca.
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  adv->start();

  Serial.println("[ble] anunciando como " + String(NAME_PREFIX));
  Serial.println("[ble] servicio " + String(SERVICE_UUID));

#if SELFTEST_BOOT
  Serial.println("[selftest] barre 0/90/180 grados");
  moverServoUS(500);  delay(1000);
  moverServoUS(1450); delay(1000);
  moverServoUS(2400); delay(1000);
  moverServoUS(REST_US);
  Serial.println("[selftest] fin");
#endif
}

void loop() {
  uint32_t ahora = millis();

  // Reanudar el anuncio FUERA del callback de desconexion. El stack ya no esta
  // dismantling la conexion aqui, asi que el anuncio vuelve de verdad y el
  // modulo reaparece en la lista sin reiniciar el ESP.
  if (s_reanunciar) {
    s_reanunciar = false;
    BLEAdvertising* adv = BLEDevice::getAdvertising();
    adv->start();
    Serial.println("[ble] reanunciando");
  }

  tickMovimiento();

  // Watchdog de un solo disparo. Solo aborta un MOVIMIENTO EN CURSO: si el
  // servo ya llego y esta presionado (HOLDING), dejarlo ahi es justo lo que
  // se pidio. Antes la condicion era `s_estado != IDLE`, que arrastraba tambien
  // a HOLDING y hacia volver el servo a los 30 s aunque la app siguiera
  // conectada mandando pings (el ping solo renovaba `s_tPing`, no el estado).
  if ((s_estado == PRESENTING || s_estado == RETURNING) &&
      s_tPing && (ahora - s_tPing) > WATCHDOG_MS) {
    s_tPing = 0;   // no volver a disparar hasta el proximo ping
    Serial.println("[watchdog] sin ping durante el movimiento: retorno a reposo");
    s_tFase = ahora;
    s_usDestino = REST_US;
    s_estado = RETURNING;
  }

  if (s_tStatus == 0) s_tStatus = ahora;
  if (ahora - s_tStatus >= STATUS_MS) {
    s_tStatus = ahora;
    enviarStatus();
  }

  delay(5);
}
