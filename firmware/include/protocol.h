#pragma once

// Contrato de protocolo. Ver PROTOCOL.md.
//
// Este header es puro: no incluye ArduinoJson ni nada de Arduino, para poder
// compilarlo en el entorno nativo de pruebas.

#include <stdint.h>

#include "config.h"

// ---------------------------------------------------------------------------
// Comandos app -> ESP32
// ---------------------------------------------------------------------------
enum class CmdId : uint8_t {
    None = 0,
    Open,
    Close,
    Estop,
    Ping,
    GetConfig,
    SaveConfig,
    Calibrate,
    /// JSON valido con un `cmd` que no existe en el contrato. Se distingue de
    /// None (= payload ilegible) para poder responder UNKNOWN_CMD en vez de
    /// MALFORMED: son fallos distintos y la app los registra distinto.
    Unknown,
};

inline const char* cmdName(CmdId c) {
    switch (c) {
        case CmdId::Open:       return "open";
        case CmdId::Close:      return "close";
        case CmdId::Estop:      return "estop";
        case CmdId::Ping:       return "ping";
        case CmdId::GetConfig:  return "get_config";
        case CmdId::SaveConfig: return "save_config";
        case CmdId::Calibrate:  return "calibrate";
        case CmdId::Unknown:    return "unknown";
        case CmdId::None:
        default:                return "none";
    }
}

// ---------------------------------------------------------------------------
// Estados de la maquina de estados del eje
// ---------------------------------------------------------------------------
enum class AxisState : uint8_t {
    Idle = 0,
    Presenting,  // avanzando hacia press_us
    Holding,     // sosteniendo la manija presionada
    Returning,   // volviendo a rest_us, siempre a velocidad maxima
};

inline const char* axisStateName(AxisState s) {
    switch (s) {
        case AxisState::Presenting: return "PRESENTING";
        case AxisState::Holding:    return "HOLDING";
        case AxisState::Returning:  return "RETURNING";
        case AxisState::Idle:
        default:                    return "IDLE";
    }
}

// ---------------------------------------------------------------------------
// Codigos de error
// ---------------------------------------------------------------------------
enum class ErrCode : uint8_t {
    None = 0,
    Malformed,
    UnknownCmd,
    StaleSeq,
    Debounced,
    NotCalibrated,
    OutOfRange,
    Stall,
    VoltageLow,
};

inline const char* errCodeName(ErrCode e) {
    switch (e) {
        case ErrCode::Malformed:      return "MALFORMED";
        case ErrCode::UnknownCmd:     return "UNKNOWN_CMD";
        case ErrCode::StaleSeq:       return "STALE_SEQ";
        case ErrCode::Debounced:      return "DEBOUNCED";
        case ErrCode::NotCalibrated:  return "NOT_CALIBRATED";
        case ErrCode::OutOfRange:     return "OUT_OF_RANGE";
        case ErrCode::Stall:          return "STALL";
        case ErrCode::VoltageLow:     return "VOLTAGE_LOW";
        case ErrCode::None:
        default:                      return "NONE";
    }
}

inline const char* errMsg(ErrCode e) {
    switch (e) {
        case ErrCode::Malformed:      return "json invalido";
        case ErrCode::UnknownCmd:     return "comando desconocido";
        case ErrCode::StaleSeq:       return "seq fuera de orden";
        case ErrCode::Debounced:      return "comando duplicado";
        case ErrCode::NotCalibrated:  return "falta calibracion";
        case ErrCode::OutOfRange:     return "valor fuera de rango";
        case ErrCode::Stall:          return "no alcanzo press_us; retorno a reposo";
        case ErrCode::VoltageLow:     return "riel de servo por debajo de 5.0 V";
        case ErrCode::None:
        default:                      return "";
    }
}

// ---------------------------------------------------------------------------
// Configuracion persistida
// ---------------------------------------------------------------------------
struct ServoConfig {
    uint16_t minUs;
    uint16_t maxUs;
    uint16_t restUs;   // estado seguro
    uint16_t pressUs;  // manija presionada
    uint16_t holdMs;
    bool     calibrated;
};

// Acota un valor de pulso contra los limites configurados.
inline uint16_t clampUs(const ServoConfig& cfg, int32_t us) {
    if (us < cfg.minUs) return cfg.minUs;
    if (us > cfg.maxUs) return cfg.maxUs;
    return static_cast<uint16_t>(us);
}

inline ServoConfig defaultConfig() {
    return ServoConfig{
        /*minUs*/ DEFAULT_MIN_US, /*maxUs*/ DEFAULT_MAX_US,
        /*restUs*/ DEFAULT_REST_US, /*pressUs*/ DEFAULT_PRESS_US,
        /*holdMs*/ DEFAULT_HOLD_MS, /*calibrated*/ false,
    };
}
