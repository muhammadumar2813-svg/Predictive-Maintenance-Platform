;; IoT Sensor Data Aggregation Contract
;; Real-time IoT sensor data collection and analysis for equipment health monitoring

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-SENSOR (err u101))
(define-constant ERR-INVALID-DATA (err u102))
(define-constant ERR-SENSOR-EXISTS (err u103))
(define-constant ERR-SENSOR-NOT-FOUND (err u104))
(define-constant ERR-THRESHOLD-EXCEEDED (err u105))
(define-constant MAX-SENSORS u1000)
(define-constant CRITICAL-THRESHOLD u85)
(define-constant WARNING-THRESHOLD u70)
(define-constant HEALTHY-THRESHOLD u30)

;; Data Maps
(define-map sensors
  { sensor-id: (string-ascii 64) }
  {
    owner: principal,
    equipment-type: (string-ascii 32),
    location: (string-ascii 64),
    status: (string-ascii 16),
    created-at: uint,
    last-updated: uint
  }
)

(define-map sensor-data
  { sensor-id: (string-ascii 64), timestamp: uint }
  {
    temperature: uint,
    vibration: uint,
    pressure: uint,
    humidity: uint,
    power-consumption: uint,
    operational-hours: uint,
    health-score: uint,
    anomaly-detected: bool
  }
)

(define-map equipment-thresholds
  { equipment-type: (string-ascii 32) }
  {
    max-temperature: uint,
    max-vibration: uint,
    max-pressure: uint,
    max-humidity: uint,
    max-power: uint
  }
)

(define-map sensor-alerts
  { sensor-id: (string-ascii 64), alert-id: uint }
  {
    alert-type: (string-ascii 32),
    severity: (string-ascii 16),
    message: (string-ascii 256),
    created-at: uint,
    resolved: bool
  }
)

(define-map authorized-operators
  { operator: principal }
  { authorized: bool }
)

;; Data Variables
(define-data-var total-sensors uint u0)
(define-data-var next-alert-id uint u1)
(define-data-var contract-active bool true)

;; Private Functions
(define-private (is-authorized (sender principal))
  (or (is-eq sender CONTRACT-OWNER)
      (default-to false (get authorized (map-get? authorized-operators { operator: sender }))))
)

(define-private (calculate-health-score (temperature uint) (vibration uint) (pressure uint) (humidity uint) (power uint) (equipment-type (string-ascii 32)))
  (let (
    (temp-score (if (> temperature (default-to u100 (get max-temperature (map-get? equipment-thresholds { equipment-type: equipment-type })))) u20 u25))
    (vib-score (if (> vibration (default-to u100 (get max-vibration (map-get? equipment-thresholds { equipment-type: equipment-type })))) u20 u25))
    (press-score (if (> pressure (default-to u100 (get max-pressure (map-get? equipment-thresholds { equipment-type: equipment-type })))) u15 u20))
    (hum-score (if (> humidity (default-to u80 (get max-humidity (map-get? equipment-thresholds { equipment-type: equipment-type })))) u10 u15))
    (power-score (if (> power (default-to u1000 (get max-power (map-get? equipment-thresholds { equipment-type: equipment-type })))) u10 u15))
  )
    (+ temp-score vib-score press-score hum-score power-score)
  )
)

(define-private (detect-anomaly (health-score uint) (prev-score uint))
  (or (< health-score HEALTHY-THRESHOLD)
      (> (if (> health-score prev-score) (- health-score prev-score) (- prev-score health-score)) u20))
)

(define-private (determine-severity (health-score uint))
  (if (< health-score HEALTHY-THRESHOLD)
      "critical"
      (if (< health-score WARNING-THRESHOLD)
          "warning"
          "info"))
)

;; Public Functions
(define-public (register-sensor (sensor-id (string-ascii 64)) (equipment-type (string-ascii 32)) (location (string-ascii 64)))
  (begin
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? sensors { sensor-id: sensor-id })) ERR-SENSOR-EXISTS)
    (asserts! (< (var-get total-sensors) MAX-SENSORS) (err u106))
    (asserts! (> (len sensor-id) u0) ERR-INVALID-SENSOR)
    
    (map-set sensors
      { sensor-id: sensor-id }
      {
        owner: tx-sender,
        equipment-type: equipment-type,
        location: location,
        status: "active",
        created-at: stacks-block-height,
        last-updated: stacks-block-height
      }
    )
    (var-set total-sensors (+ (var-get total-sensors) u1))
    (ok sensor-id)
  )
)

(define-public (submit-sensor-data 
  (sensor-id (string-ascii 64))
  (temperature uint)
  (vibration uint)
  (pressure uint)
  (humidity uint)
  (power-consumption uint)
  (operational-hours uint)
)
  (let (
    (sensor-info (unwrap! (map-get? sensors { sensor-id: sensor-id }) ERR-SENSOR-NOT-FOUND))
    (equipment-type (get equipment-type sensor-info))
    (timestamp stacks-block-height)
    (health-score (calculate-health-score temperature vibration pressure humidity power-consumption equipment-type))
    (prev-data (map-get? sensor-data { sensor-id: sensor-id, timestamp: (- timestamp u1) }))
    (prev-score (default-to u50 (get health-score prev-data)))
    (anomaly (detect-anomaly health-score prev-score))
  )
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (< temperature u200) ERR-INVALID-DATA)
    (asserts! (< vibration u100) ERR-INVALID-DATA)
    (asserts! (< pressure u500) ERR-INVALID-DATA)
    (asserts! (< humidity u100) ERR-INVALID-DATA)
    
    (map-set sensor-data
      { sensor-id: sensor-id, timestamp: timestamp }
      {
        temperature: temperature,
        vibration: vibration,
        pressure: pressure,
        humidity: humidity,
        power-consumption: power-consumption,
        operational-hours: operational-hours,
        health-score: health-score,
        anomaly-detected: anomaly
      }
    )
    
    (map-set sensors
      { sensor-id: sensor-id }
      (merge sensor-info { last-updated: timestamp })
    )
    
    (if anomaly
        (begin
          (try! (create-alert sensor-id "anomaly" (determine-severity health-score) "Anomaly detected in sensor readings"))
          (ok health-score))
        (ok health-score))
  )
)

(define-public (create-alert (sensor-id (string-ascii 64)) (alert-type (string-ascii 32)) (severity (string-ascii 16)) (message (string-ascii 256)))
  (let (
    (alert-id (var-get next-alert-id))
  )
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? sensors { sensor-id: sensor-id })) ERR-SENSOR-NOT-FOUND)
    
    (map-set sensor-alerts
      { sensor-id: sensor-id, alert-id: alert-id }
      {
        alert-type: alert-type,
        severity: severity,
        message: message,
        created-at: stacks-block-height,
        resolved: false
      }
    )
    (var-set next-alert-id (+ alert-id u1))
    (ok alert-id)
  )
)

(define-public (resolve-alert (sensor-id (string-ascii 64)) (alert-id uint))
  (let (
    (alert-info (unwrap! (map-get? sensor-alerts { sensor-id: sensor-id, alert-id: alert-id }) (err u107)))
  )
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (get resolved alert-info)) (err u108))
    
    (map-set sensor-alerts
      { sensor-id: sensor-id, alert-id: alert-id }
      (merge alert-info { resolved: true })
    )
    (ok true)
  )
)

(define-public (set-equipment-thresholds (equipment-type (string-ascii 32)) (max-temp uint) (max-vib uint) (max-press uint) (max-hum uint) (max-pow uint))
  (begin
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    
    (map-set equipment-thresholds
      { equipment-type: equipment-type }
      {
        max-temperature: max-temp,
        max-vibration: max-vib,
        max-pressure: max-press,
        max-humidity: max-hum,
        max-power: max-pow
      }
    )
    (ok true)
  )
)

(define-public (authorize-operator (operator principal))
  (begin
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (map-set authorized-operators
      { operator: operator }
      { authorized: true }
    )
    (ok true)
  )
)

(define-public (revoke-operator (operator principal))
  (begin
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (map-set authorized-operators
      { operator: operator }
      { authorized: false }
    )
    (ok true)
  )
)

(define-public (update-sensor-status (sensor-id (string-ascii 64)) (status (string-ascii 16)))
  (let (
    (sensor-info (unwrap! (map-get? sensors { sensor-id: sensor-id }) ERR-SENSOR-NOT-FOUND))
  )
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    
    (map-set sensors
      { sensor-id: sensor-id }
      (merge sensor-info { status: status, last-updated: stacks-block-height })
    )
    (ok true)
  )
)

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-active false)
    (ok true)
  )
)

(define-public (resume-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-active true)
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-sensor-info (sensor-id (string-ascii 64)))
  (map-get? sensors { sensor-id: sensor-id })
)

(define-read-only (get-sensor-data (sensor-id (string-ascii 64)) (timestamp uint))
  (map-get? sensor-data { sensor-id: sensor-id, timestamp: timestamp })
)

(define-read-only (get-latest-sensor-data (sensor-id (string-ascii 64)))
  (match (map-get? sensors { sensor-id: sensor-id })
    sensor-info (let ((last-timestamp (get last-updated sensor-info)))
                  (map-get? sensor-data { sensor-id: sensor-id, timestamp: last-timestamp }))
    none
  )
)

(define-read-only (get-alert (sensor-id (string-ascii 64)) (alert-id uint))
  (map-get? sensor-alerts { sensor-id: sensor-id, alert-id: alert-id })
)

(define-read-only (get-equipment-thresholds (equipment-type (string-ascii 32)))
  (map-get? equipment-thresholds { equipment-type: equipment-type })
)

(define-read-only (is-operator-authorized (operator principal))
  (default-to false (get authorized (map-get? authorized-operators { operator: operator })))
)

(define-read-only (get-total-sensors)
  (var-get total-sensors)
)

(define-read-only (get-contract-status)
  (var-get contract-active)
)

(define-read-only (get-contract-owner)
  CONTRACT-OWNER
)
