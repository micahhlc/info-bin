#!/usr/bin/env bash
set -euo pipefail

# MacBook Pro 13" M2 (Mac14,7) reference ranges
# Battery: 3-cell Li-Po, 58.2Wh, 11.4V nominal, 5103 mAh design
# Per-cell: 3.0V min, 3.6–4.2V normal, 4.25V max
# Pack:     9900 mV min, 11100–12600 mV normal, 12600 mV max
# Adapter:  USB-C PD 5/9/15/20V; 30W min to charge, 67W stock, 100W max safe
# Charging current (pack side): 1000–5500 mA normal

CELL_V_MIN=3000   # mV — BMS cutoff warning
CELL_V_MAX=4350   # mV — overcharge warning (Apple Li-Po actual max ~4.35V)
CELL_V_LO=3600    # mV — low but not critical
CELL_V_HI=4200    # mV — full charge

PACK_V_MIN=9900   # mV
PACK_V_MAX=12600  # mV

ADAPTER_W_MIN=30  # W — below this won't reliably charge
ADAPTER_W_MAX=100 # W — above this is unusual for USB-C PD SPR
ADAPTER_V_VALID="5000 9000 15000 20000"  # valid PD negotiation voltages (mV)

# ── helpers ──────────────────────────────────────────────────────────────────

RAW_IOREG="$(ioreg -rn AppleSmartBattery 2>/dev/null)"

get_ioreg() {
  echo "$RAW_IOREG" | grep -E "^\s+\"$1\" = [0-9]+" | head -n1 \
    | sed -E 's/.*= ([0-9]+).*/\1/' || true
}

get_cell_voltages() {
  echo "$RAW_IOREG" | grep -oE '"CellVoltage"=\([0-9,]+\)' | head -n1 \
    | sed -E 's/"CellVoltage"=\(([^)]+)\)/\1/' || true
}

get_inline_field() {
  local blob_key="$1" field="$2"
  echo "$RAW_IOREG" | grep -E "^\s+\"$blob_key\"" | head -n1 \
    | grep -oE "\"$field\"=[0-9]+" | sed -E 's/.*=([0-9]+)/\1/' || true
}

ok()   { echo "  [OK]  $*"; }
warn() { echo "  [WARN] $*"; }
bad()  { echo "  [!!]  $*"; }

check_range() {
  local label="$1" val="$2" lo="$3" hi="$4" unit="$5"
  if   (( val < lo )); then bad  "$label ${val}${unit} — below normal (min ${lo}${unit})"
  elif (( val > hi )); then warn "$label ${val}${unit} — above normal (max ${hi}${unit})"
  else                      ok   "$label ${val}${unit}"
  fi
}

# ── gather data ───────────────────────────────────────────────────────────────

VOLTAGE=$(get_ioreg "AppleRawBatteryVoltage")
AMPERAGE=$(get_ioreg "Amperage")
NOMINAL_CAP=$(get_ioreg "NominalChargeCapacity")
MAX_CAP=$(get_ioreg "AppleRawMaxCapacity")
DESIGN_CAP=$(get_ioreg "DesignCapacity")
CYCLE=$(get_ioreg "CycleCount")
CELL_VOLTAGES=$(get_cell_voltages)
TEMP=$(get_ioreg "Temperature")

CHARGING_CURRENT=$(get_inline_field "ChargerData" "ChargingCurrent")
CHARGING_VOLTAGE=$(get_inline_field "ChargerData" "ChargingVoltage")
ADAPTER_WATTS=$(get_inline_field "AdapterDetails" "Watts")
ADAPTER_VOLTAGE=$(get_inline_field "AdapterDetails" "AdapterVoltage")

PMSET="$(pmset -g batt 2>/dev/null)"
STATUS_LINE=$(echo "$PMSET" | grep "InternalBattery")
PERCENT=$(echo "$STATUS_LINE" | grep -oE '[0-9]+%' || true)
CHARGE_STATE=$(echo "$STATUS_LINE" | grep -oE 'charging|discharging|charged|AC attached' || true)
TIME_LEFT=$(echo "$STATUS_LINE" | grep -oE '[0-9]+:[0-9]+' || true)
POWER_SOURCE=$(echo "$PMSET" | grep -oE "'[^']+'" | head -n1 | tr -d "'" || true)

# ── compute display values ────────────────────────────────────────────────────

HEALTH_PCT=""
if [[ -n "$MAX_CAP" && -n "$DESIGN_CAP" && "$DESIGN_CAP" -gt 0 ]]; then
  HEALTH_PCT="$(echo "$MAX_CAP $DESIGN_CAP" | awk '{printf "%.1f%%", ($1/$2)*100}')"
fi

VOLTAGE_V=""
[[ -n "$VOLTAGE" ]] && VOLTAGE_V="$(echo "$VOLTAGE" | awk '{printf "%.3f V", $1/1000}')"

TEMP_C=""
[[ -n "$TEMP" ]] && TEMP_C="$(echo "$TEMP" | awk '{printf "%.1f°C", $1/100}')"

ADAPTER_V_DISPLAY="${ADAPTER_VOLTAGE:-N/A}"
[[ -n "$ADAPTER_VOLTAGE" ]] && ADAPTER_V_DISPLAY="$(echo "$ADAPTER_VOLTAGE" | awk '{printf "%.0f V", $1/1000}')"

# ── output ────────────────────────────────────────────────────────────────────

echo "— MacBook Battery Status (MacBook Pro 13\" M2) —"
echo ""
echo "Charge:         ${PERCENT:-N/A} (${CHARGE_STATE:-unknown})"
[[ -n "$TIME_LEFT" ]] && echo "Time left:      ${TIME_LEFT}"
echo "Power source:   ${POWER_SOURCE:-unknown}"
echo ""
echo "Voltage:        ${VOLTAGE_V:-N/A} (${VOLTAGE:-?} mV)"
echo "Amperage:       ${AMPERAGE:-N/A} mA"
echo "Charging V:     ${CHARGING_VOLTAGE:-N/A} mV target"
echo "Charging A:     ${CHARGING_CURRENT:-N/A} mA"
echo "Temperature:    ${TEMP_C:-N/A}"
echo ""

if [[ -n "$CELL_VOLTAGES" ]]; then
  echo "Cell voltages:"
  echo "$CELL_VOLTAGES" | tr ',' '\n' | awk '{
    v = $1+0
    printf "  Cell %d: %d mV (%.3f V)\n", NR, v, v/1000
  }'
  echo ""
fi

echo "Adapter:        ${ADAPTER_WATTS:-N/A}W @ ${ADAPTER_V_DISPLAY}"
echo ""
echo "Capacity now:   ${NOMINAL_CAP:-N/A} mAh"
echo "Max capacity:   ${MAX_CAP:-N/A} mAh"
echo "Design cap:     ${DESIGN_CAP:-N/A} mAh"
echo "Health:         ${HEALTH_PCT:-N/A}"
echo "Cycle count:    ${CYCLE:-N/A}"

# ── range checks ─────────────────────────────────────────────────────────────

echo ""
echo "— Range Check (MacBook Pro 13\" M2 specs) —"

# Battery pack voltage
if [[ -n "$VOLTAGE" ]]; then
  check_range "Battery pack" "$VOLTAGE" "$PACK_V_MIN" "$PACK_V_MAX" " mV"
fi

# Per-cell voltage
if [[ -n "$CELL_VOLTAGES" ]]; then
  i=1
  for cv in $(echo "$CELL_VOLTAGES" | tr ',' ' '); do
    if   (( cv < CELL_V_MIN )); then bad  "Cell $i ${cv} mV — critical low (min ${CELL_V_MIN} mV)"
    elif (( cv > CELL_V_MAX )); then bad  "Cell $i ${cv} mV — overcharge risk (max ${CELL_V_MAX} mV)"
    elif (( cv < CELL_V_LO  )); then warn "Cell $i ${cv} mV — low charge"
    else                              ok   "Cell $i ${cv} mV"
    fi
    (( i++ ))
  done
fi

# Adapter wattage
if [[ -n "$ADAPTER_WATTS" ]]; then
  if   (( ADAPTER_WATTS < ADAPTER_W_MIN )); then warn "Adapter ${ADAPTER_WATTS}W — too weak to reliably charge (need ≥${ADAPTER_W_MIN}W)"
  elif (( ADAPTER_WATTS > ADAPTER_W_MAX )); then warn "Adapter ${ADAPTER_WATTS}W — unusually high for USB-C PD SPR (max expected ${ADAPTER_W_MAX}W)"
  else                                           ok   "Adapter ${ADAPTER_WATTS}W"
  fi
fi

# Adapter voltage (must be a valid USB-C PD level)
if [[ -n "$ADAPTER_VOLTAGE" ]]; then
  PD_OK=false
  for valid in $ADAPTER_V_VALID; do
    delta=$(( ADAPTER_VOLTAGE - valid ))
    [[ $delta -lt 0 ]] && delta=$(( -delta ))
    (( delta <= 200 )) && PD_OK=true && break
  done
  V_DISPLAY="$(echo "$ADAPTER_VOLTAGE" | awk '{printf "%.1f V", $1/1000}')"
  if $PD_OK; then
    ok "Adapter PD voltage ${V_DISPLAY} (valid USB-C PD level)"
  else
    warn "Adapter PD voltage ${V_DISPLAY} — not a standard USB-C PD level (5/9/15/20V)"
  fi
fi

# Charging current (only check while actively charging)
if [[ "$CHARGE_STATE" == "charging" && -n "$CHARGING_CURRENT" ]]; then
  check_range "Charging current" "$CHARGING_CURRENT" 100 5500 " mA"
fi

echo ""
