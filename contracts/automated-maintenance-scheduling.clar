;; Automated Maintenance Scheduling Contract
;; Smart contract for automated maintenance scheduling and service provider payments

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-EQUIPMENT (err u201))
(define-constant ERR-INVALID-PROVIDER (err u202))
(define-constant ERR-EQUIPMENT-EXISTS (err u203))
(define-constant ERR-EQUIPMENT-NOT-FOUND (err u204))
(define-constant ERR-PROVIDER-EXISTS (err u205))
(define-constant ERR-PROVIDER-NOT-FOUND (err u206))
(define-constant ERR-INSUFFICIENT-FUNDS (err u207))
(define-constant ERR-MAINTENANCE-EXISTS (err u208))
(define-constant ERR-MAINTENANCE-NOT-FOUND (err u209))
(define-constant ERR-INVALID-STATUS (err u210))
(define-constant MAX-EQUIPMENT u500)
(define-constant MAX-PROVIDERS u100)
(define-constant BASE-MAINTENANCE-COST u1000000) ;; 1 STX in micro-STX
(define-constant URGENT-MULTIPLIER u2)
(define-constant EMERGENCY-MULTIPLIER u3)

;; Data Maps
(define-map equipment-registry
  { equipment-id: (string-ascii 64) }
  {
    owner: principal,
    equipment-type: (string-ascii 32),
    location: (string-ascii 64),
    installation-date: uint,
    last-maintenance: uint,
    maintenance-interval: uint,
    status: (string-ascii 16),
    health-score: uint
  }
)

(define-map service-providers
  { provider-id: principal }
  {
    name: (string-ascii 64),
    specialization: (string-ascii 32),
    rating: uint,
    completed-jobs: uint,
    hourly-rate: uint,
    availability: bool,
    location: (string-ascii 64)
  }
)

(define-map maintenance-requests
  { request-id: uint }
  {
    equipment-id: (string-ascii 64),
    requester: principal,
    provider: (optional principal),
    priority: (string-ascii 16),
    scheduled-date: uint,
    estimated-cost: uint,
    actual-cost: (optional uint),
    status: (string-ascii 16),
    created-at: uint,
    completed-at: (optional uint),
    description: (string-ascii 256)
  }
)

(define-map maintenance-payments
  { request-id: uint }
  {
    amount: uint,
    paid-at: uint,
    provider: principal,
    bonus: uint
  }
)

(define-map provider-ratings
  { provider: principal, rater: principal }
  {
    rating: uint,
    feedback: (string-ascii 256),
    created-at: uint
  }
)

(define-map authorized-managers
  { manager: principal }
  { authorized: bool }
)

;; Data Variables
(define-data-var total-equipment uint u0)
(define-data-var total-providers uint u0)
(define-data-var next-request-id uint u1)
(define-data-var contract-treasury uint u0)
(define-data-var contract-active bool true)

;; Private Functions
(define-private (is-authorized (sender principal))
  (or (is-eq sender CONTRACT-OWNER)
      (default-to false (get authorized (map-get? authorized-managers { manager: sender }))))
)

(define-private (calculate-maintenance-cost (priority (string-ascii 16)) (equipment-type (string-ascii 32)) (provider-rate uint))
  (let (
    (base-cost BASE-MAINTENANCE-COST)
    (priority-multiplier (if (is-eq priority "emergency")
                           EMERGENCY-MULTIPLIER
                           (if (is-eq priority "urgent")
                             URGENT-MULTIPLIER
                             u1)))
    (provider-cost (* provider-rate u8)) ;; 8 hours default
  )
    (+ (* base-cost priority-multiplier) provider-cost)
  )
)

(define-private (determine-priority (health-score uint) (days-since-maintenance uint) (maintenance-interval uint))
  (if (< health-score u30)
      "emergency"
      (if (or (< health-score u50) (> days-since-maintenance maintenance-interval))
          "urgent"
          (if (> days-since-maintenance (* maintenance-interval u8 u10)) ;; 80% of interval
              "scheduled"
              "routine")))
)

(define-private (find-best-provider (equipment-type (string-ascii 32)) (location (string-ascii 64)))
  ;; Simplified provider selection based on specialization and rating
  ;; In a real implementation, this would be more sophisticated
  (ok none) ;; Returns none for now, would implement provider matching logic
)

(define-private (calculate-performance-bonus (completion-time uint) (estimated-time uint) (quality-rating uint))
  (let (
    (time-bonus (if (< completion-time estimated-time) u100000 u0)) ;; 0.1 STX bonus for early completion
    (quality-bonus (if (> quality-rating u8) u200000 u0)) ;; 0.2 STX bonus for high quality
  )
    (+ time-bonus quality-bonus)
  )
)

;; Public Functions
(define-public (register-equipment 
  (equipment-id (string-ascii 64))
  (equipment-type (string-ascii 32))
  (location (string-ascii 64))
  (maintenance-interval uint)
)
  (begin
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? equipment-registry { equipment-id: equipment-id })) ERR-EQUIPMENT-EXISTS)
    (asserts! (< (var-get total-equipment) MAX-EQUIPMENT) (err u211))
    (asserts! (> (len equipment-id) u0) ERR-INVALID-EQUIPMENT)
    (asserts! (> maintenance-interval u0) ERR-INVALID-EQUIPMENT)
    
    (map-set equipment-registry
      { equipment-id: equipment-id }
      {
        owner: tx-sender,
        equipment-type: equipment-type,
        location: location,
        installation-date: stacks-block-height,
        last-maintenance: stacks-block-height,
        maintenance-interval: maintenance-interval,
        status: "active",
        health-score: u100
      }
    )
    (var-set total-equipment (+ (var-get total-equipment) u1))
    (ok equipment-id)
  )
)

(define-public (register-service-provider
  (name (string-ascii 64))
  (specialization (string-ascii 32))
  (hourly-rate uint)
  (location (string-ascii 64))
)
  (begin
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-none (map-get? service-providers { provider-id: tx-sender })) ERR-PROVIDER-EXISTS)
    (asserts! (< (var-get total-providers) MAX-PROVIDERS) (err u212))
    (asserts! (> (len name) u0) ERR-INVALID-PROVIDER)
    (asserts! (> hourly-rate u0) ERR-INVALID-PROVIDER)
    
    (map-set service-providers
      { provider-id: tx-sender }
      {
        name: name,
        specialization: specialization,
        rating: u5, ;; Default 5/10 rating
        completed-jobs: u0,
        hourly-rate: hourly-rate,
        availability: true,
        location: location
      }
    )
    (var-set total-providers (+ (var-get total-providers) u1))
    (ok tx-sender)
  )
)

(define-public (create-maintenance-request
  (equipment-id (string-ascii 64))
  (priority (string-ascii 16))
  (scheduled-date uint)
  (description (string-ascii 256))
)
  (let (
    (equipment-info (unwrap! (map-get? equipment-registry { equipment-id: equipment-id }) ERR-EQUIPMENT-NOT-FOUND))
    (request-id (var-get next-request-id))
    (estimated-cost (calculate-maintenance-cost priority (get equipment-type equipment-info) u50000)) ;; Default rate
  )
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (>= scheduled-date stacks-block-height) (err u213))
    
    (map-set maintenance-requests
      { request-id: request-id }
      {
        equipment-id: equipment-id,
        requester: tx-sender,
        provider: none,
        priority: priority,
        scheduled-date: scheduled-date,
        estimated-cost: estimated-cost,
        actual-cost: none,
        status: "pending",
        created-at: stacks-block-height,
        completed-at: none,
        description: description
      }
    )
    (var-set next-request-id (+ request-id u1))
    (ok request-id)
  )
)

(define-public (assign-provider (request-id uint) (provider principal))
  (let (
    (request-info (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-MAINTENANCE-NOT-FOUND))
    (provider-info (unwrap! (map-get? service-providers { provider-id: provider }) ERR-PROVIDER-NOT-FOUND))
  )
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request-info) "pending") ERR-INVALID-STATUS)
    (asserts! (get availability provider-info) (err u214))
    
    (map-set maintenance-requests
      { request-id: request-id }
      (merge request-info { 
        provider: (some provider),
        status: "assigned",
        actual-cost: (some (calculate-maintenance-cost 
                            (get priority request-info)
                            (get equipment-type (unwrap! (map-get? equipment-registry { equipment-id: (get equipment-id request-info) }) ERR-EQUIPMENT-NOT-FOUND))
                            (get hourly-rate provider-info)))
      })
    )
    (ok true)
  )
)

(define-public (complete-maintenance (request-id uint) (quality-rating uint))
  (let (
    (request-info (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-MAINTENANCE-NOT-FOUND))
    (provider (unwrap! (get provider request-info) ERR-PROVIDER-NOT-FOUND))
    (provider-info (unwrap! (map-get? service-providers { provider-id: provider }) ERR-PROVIDER-NOT-FOUND))
    (actual-cost (unwrap! (get actual-cost request-info) (err u215)))
    (bonus (calculate-performance-bonus stacks-block-height (get scheduled-date request-info) quality-rating))
    (total-payment (+ actual-cost bonus))
  )
    (asserts! (var-get contract-active) (err u999))
    (asserts! (or (is-eq tx-sender provider) (is-authorized tx-sender)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request-info) "assigned") ERR-INVALID-STATUS)
    (asserts! (<= quality-rating u10) (err u216))
    (asserts! (>= (var-get contract-treasury) total-payment) ERR-INSUFFICIENT-FUNDS)
    
    ;; Update request status
    (map-set maintenance-requests
      { request-id: request-id }
      (merge request-info {
        status: "completed",
        completed-at: (some stacks-block-height)
      })
    )
    
    ;; Record payment
    (map-set maintenance-payments
      { request-id: request-id }
      {
        amount: actual-cost,
        paid-at: stacks-block-height,
        provider: provider,
        bonus: bonus
      }
    )
    
    ;; Update provider stats
    (map-set service-providers
      { provider-id: provider }
      (merge provider-info {
        completed-jobs: (+ (get completed-jobs provider-info) u1),
        rating: (/ (+ (* (get rating provider-info) (get completed-jobs provider-info)) quality-rating)
                   (+ (get completed-jobs provider-info) u1))
      })
    )
    
    ;; Update contract treasury
    (var-set contract-treasury (- (var-get contract-treasury) total-payment))
    
    ;; Transfer payment to provider
    (try! (stx-transfer? total-payment (as-contract tx-sender) provider))
    (ok total-payment)
  )
)

(define-public (update-equipment-health (equipment-id (string-ascii 64)) (health-score uint))
  (let (
    (equipment-info (unwrap! (map-get? equipment-registry { equipment-id: equipment-id }) ERR-EQUIPMENT-NOT-FOUND))
  )
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= health-score u100) (err u217))
    
    (map-set equipment-registry
      { equipment-id: equipment-id }
      (merge equipment-info { health-score: health-score })
    )
    
    ;; Auto-create maintenance request if health is critical
    (if (< health-score u30)
        (begin
          (try! (create-maintenance-request equipment-id "emergency" (+ stacks-block-height u144) "Auto-generated emergency maintenance"))
          (ok health-score))
        (ok health-score))
  )
)

(define-public (fund-contract)
  (let (
    (amount (stx-get-balance tx-sender))
  )
    (asserts! (var-get contract-active) (err u999))
    (asserts! (> amount u0) ERR-INSUFFICIENT-FUNDS)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set contract-treasury (+ (var-get contract-treasury) amount))
    (ok amount)
  )
)

(define-public (rate-provider (provider principal) (rating uint) (feedback (string-ascii 256)))
  (begin
    (asserts! (var-get contract-active) (err u999))
    (asserts! (<= rating u10) (err u218))
    (asserts! (is-some (map-get? service-providers { provider-id: provider })) ERR-PROVIDER-NOT-FOUND)
    
    (map-set provider-ratings
      { provider: provider, rater: tx-sender }
      {
        rating: rating,
        feedback: feedback,
        created-at: stacks-block-height
      }
    )
    (ok true)
  )
)

(define-public (authorize-manager (manager principal))
  (begin
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (map-set authorized-managers
      { manager: manager }
      { authorized: true }
    )
    (ok true)
  )
)

(define-public (revoke-manager (manager principal))
  (begin
    (asserts! (var-get contract-active) (err u999))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (map-set authorized-managers
      { manager: manager }
      { authorized: false }
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
(define-read-only (get-equipment-info (equipment-id (string-ascii 64)))
  (map-get? equipment-registry { equipment-id: equipment-id })
)

(define-read-only (get-provider-info (provider principal))
  (map-get? service-providers { provider-id: provider })
)

(define-read-only (get-maintenance-request (request-id uint))
  (map-get? maintenance-requests { request-id: request-id })
)

(define-read-only (get-payment-info (request-id uint))
  (map-get? maintenance-payments { request-id: request-id })
)

(define-read-only (get-provider-rating (provider principal) (rater principal))
  (map-get? provider-ratings { provider: provider, rater: rater })
)

(define-read-only (is-manager-authorized (manager principal))
  (default-to false (get authorized (map-get? authorized-managers { manager: manager })))
)

(define-read-only (get-contract-treasury)
  (var-get contract-treasury)
)

(define-read-only (get-total-equipment)
  (var-get total-equipment)
)

(define-read-only (get-total-providers)
  (var-get total-providers)
)

(define-read-only (get-contract-status)
  (var-get contract-active)
)

(define-read-only (get-contract-owner)
  CONTRACT-OWNER
)
