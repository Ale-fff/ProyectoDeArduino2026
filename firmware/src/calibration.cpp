#include "calibration.h"

#include "log.h"
#include "config.h"

#if defined(ARDUINO)
#include <Preferences.h>
static Preferences s_prefs;
#endif

static constexpr const char* NAMESPACE_ = "puertavoz";
static constexpr const char* KEY_MIN   = "min_us";
static constexpr const char* KEY_MAX   = "max_us";
static constexpr const char* KEY_REST  = "rest_us";
static constexpr const char* KEY_PRESS = "press_us";
static constexpr const char* KEY_HOLD  = "hold_ms";
static constexpr const char* KEY_CAL   = "calibrated";

void Calibration::begin() {
    _cfg = defaultConfig();

#if defined(ARDUINO)
    if (!s_prefs.begin(NAMESPACE_, false)) {
        PV_LOG_PRINTLN("[cal] no se pudo abrir NVS, uso defaults sin calibrar");
        return;
    }

    _cfg.minUs   = s_prefs.getUShort(KEY_MIN,   DEFAULT_MIN_US);
    _cfg.maxUs   = s_prefs.getUShort(KEY_MAX,   DEFAULT_MAX_US);
    _cfg.restUs  = s_prefs.getUShort(KEY_REST,  DEFAULT_REST_US);
    _cfg.pressUs = s_prefs.getUShort(KEY_PRESS, DEFAULT_PRESS_US);
    _cfg.holdMs  = s_prefs.getUShort(KEY_HOLD,  DEFAULT_HOLD_MS);
    _cfg.calibrated = s_prefs.getBool(KEY_CAL, false);
    s_prefs.end();

    // NVS corrupto: si los limites no cierran, se descarta todo.
    if (_cfg.minUs >= _cfg.maxUs ||
        _cfg.minUs < SERVO_ABS_MIN_US || _cfg.maxUs > SERVO_ABS_MAX_US) {
        PV_LOG_PRINTLN("[cal] NVS incoherente, uso defaults sin calibrar");
        _cfg = defaultConfig();
        return;
    }
#endif

    PV_LOG_PRINTF("[cal] min=%u max=%u rest=%u press=%u hold=%ums cal=%d\n",
                  _cfg.minUs, _cfg.maxUs, _cfg.restUs, _cfg.pressUs,
                  _cfg.holdMs, _cfg.calibrated ? 1 : 0);
}

bool Calibration::save(const ServoConfig& in) {
    // Validacion completa antes de tocar NVS. Si algo falla no se escribe nada:
    // una calibracion a medias es peor que no tener calibracion.
    if (in.minUs < SERVO_ABS_MIN_US || in.maxUs > SERVO_ABS_MAX_US) {
        PV_LOG_PRINTLN("[cal] save rechazado: limites fuera de rango absoluto");
        return false;
    }
    if (in.minUs >= in.maxUs) {
        PV_LOG_PRINTLN("[cal] save rechazado: min_us >= max_us");
        return false;
    }
    if (in.restUs < in.minUs || in.restUs > in.maxUs) {
        PV_LOG_PRINTLN("[cal] save rechazado: rest_us fuera de [min_us, max_us]");
        return false;
    }
    if (in.pressUs < in.minUs || in.pressUs > in.maxUs) {
        PV_LOG_PRINTLN("[cal] save rechazado: press_us fuera de [min_us, max_us]");
        return false;
    }
    if (in.holdMs < HOLD_MS_MIN || in.holdMs > HOLD_MS_MAX) {
        PV_LOG_PRINTLN("[cal] save rechazado: hold_ms fuera de rango");
        return false;
    }

    _cfg = in;

#if defined(ARDUINO)
    if (s_prefs.begin(NAMESPACE_, false)) {
        s_prefs.putUShort(KEY_MIN,   _cfg.minUs);
        s_prefs.putUShort(KEY_MAX,   _cfg.maxUs);
        s_prefs.putUShort(KEY_REST,  _cfg.restUs);
        s_prefs.putUShort(KEY_PRESS, _cfg.pressUs);
        s_prefs.putUShort(KEY_HOLD,  _cfg.holdMs);
        s_prefs.putBool(KEY_CAL,     _cfg.calibrated);
        s_prefs.end();
    }
#endif

    PV_LOG_PRINTF("[cal] guardada min=%u max=%u rest=%u press=%u hold=%ums\n",
                  _cfg.minUs, _cfg.maxUs, _cfg.restUs, _cfg.pressUs, _cfg.holdMs);
    return true;
}

void Calibration::markCalibrated() {
    _cfg.calibrated = true;
#if defined(ARDUINO)
    if (s_prefs.begin(NAMESPACE_, false)) {
        s_prefs.putBool(KEY_CAL, true);
        s_prefs.end();
    }
#endif
    PV_LOG_PRINTLN("[cal] marcada como calibrada");
}
