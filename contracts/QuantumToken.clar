;; QuantumToken: Strategic Resource Allocation Protocol
;; This Clarity 2.0 smart contract enables quantum-secured token distribution with milestone-based verification and comprehensive oversight mechanisms.

;; Protocol administration parameters
(define-constant PROTOCOL_SUPERVISOR tx-sender)
(define-constant ERR_PERMISSION_DENIED (err u200))
(define-constant ERR_CAPSULE_MISSING (err u201))
(define-constant ERR_RESOURCES_DEPLETED (err u202))
(define-constant ERR_TRANSACTION_REJECTED (err u203))
(define-constant ERR_INVALID_CAPSULE_REFERENCE (err u204))
(define-constant ERR_QUANTITY_UNACCEPTABLE (err u205))
(define-constant ERR_VALIDATION_FAILURE (err u206))
(define-constant ERR_CAPSULE_EXPIRED (err u207))
(define-constant CAPSULE_DURATION u1008)

;; Supplementary error definitions
(define-constant ERR_ALREADY_EXPIRED (err u208))
(define-constant ERR_OVERRIDE_AUTHORIZATION_REQUIRED (err u209))
(define-constant ERR_MILESTONE_LOGGED (err u210))
(define-constant ERR_PROXY_ASSIGNMENT_EXISTS (err u211))
(define-constant ERR_BULK_OPERATION_INCOMPLETE (err u212))
(define-constant ERR_THRESHOLD_EXCEEDED (err u213))
(define-constant ERR_ANOMALY_DETECTED (err u215))
(define-constant ERR_DIVERGENCE_EXISTS (err u236))
(define-constant ERR_ARBITRATION_WINDOW_EXPIRED (err u237))

;; Protocol operational parameters
(define-constant PROTECTION_INTERVAL u720) ;; ~5 days in blocks
(define-constant ERR_PROTECTION_ENGAGED (err u222))
(define-constant ERR_PROTECTION_COOLDOWN (err u223))
(define-constant RECIPIENT_UPPER_BOUND u5)
(define-constant ERR_RECIPIENT_CAP_REACHED (err u224))
(define-constant ERR_DISTRIBUTION_IMBALANCE (err u225))
(define-constant MAX_TIMELINE_ADJUSTMENT u1008) ;; ~7 days in blocks
(define-constant DISTRIBUTION_TIMEFRAME u144) ;; ~24 hours in blocks
(define-constant MAX_OPERATIONS_PER_TIMEFRAME u5)
(define-constant VOLUME_ALERT_THRESHOLD u1000000000) ;; Large operation threshold
(define-constant FREQUENCY_ALERT_THRESHOLD u3) ;; Number of rapid operations that trigger monitoring
(define-constant ARBITRATION_TIMEFRAME u1008) ;; ~7 days
(define-constant ARBITRATION_STAKE u1000000) ;; 1 STX stake for arbitration requests

;; Core capsule registry
(define-map QuantumCapsules
  { capsule-id: uint }
  {
    originator: principal,
    recipient: principal,
    quantum: uint,
    phase: (string-ascii 10),
    genesis-block: uint,
    termination-block: uint,
    milestones: (list 5 uint),
    fulfilled-milestones: uint
  }
)

(define-data-var capsule-sequence uint u0)

;; Multi-recipient distribution structure
(define-map BranchedCapsules
  { branch-capsule-id: uint }
  {
    originator: principal,
    destinations: (list 5 { recipient: principal, allocation: uint }),
    total-quantum: uint,
    genesis-block: uint,
    phase: (string-ascii 10)
  }
)

(define-data-var branch-capsule-sequence uint u0)

;; Authorized recipient registry
(define-map CertifiedRecipients
  { recipient: principal }
  { certified: bool }
)

;; Milestone verification ledger
(define-map MilestoneJournal
  { capsule-id: uint, milestone-index: uint }
  {
    completion-level: uint,
    documentation: (string-ascii 200),
    timestamp-block: uint,
    cryptographic-proof: (buff 32)
  }
)

;; Operation delegation registry
(define-map CapsuleProxies
  { capsule-id: uint }
  {
    proxy: principal,
    permission-terminate: bool,
    permission-extend: bool,
    permission-amplify: bool,
    proxy-expiration: uint
  }
)

;; Anomaly detection registry
(define-map MonitoredCapsules
  { capsule-id: uint }
  { 
    alert-type: (string-ascii 20),
    reported-by: principal,
    resolved: bool
  }
)

;; Originator activity surveillance
(define-map OriginatorMonitor
  { originator: principal }
  {
    last-operation-block: uint,
    operations-in-timeframe: uint
  }
)

;; Arbitration mechanism
(define-map CapsuleArbitration
  { capsule-id: uint }
  {
    claimant: principal,
    claim-basis: (string-ascii 200),
    claim-stake: uint,
    resolved: bool,
    valid-claim: bool,
    claim-block: uint
  }
)

;; Emergency protocol activation requests
(define-map OverrideRequests
  { capsule-id: uint }
  { 
    supervisor-approval: bool,
    originator-approval: bool,
    justification: (string-ascii 100)
  }
)

;; Protocol operational state
(define-data-var protocol-halted bool false)

;; Utility functions
(define-private (is-eligible-recipient (recipient principal))
  (not (is-eq recipient tx-sender))
)

(define-private (is-valid-capsule-id (capsule-id uint))
  (<= capsule-id (var-get capsule-sequence))
)

(define-private (get-allocation-value (destination { recipient: principal, allocation: uint }))
  (get allocation destination)
)

;; Public query functions
(define-read-only (is-recipient-certified (recipient principal))
  (default-to false (get certified (map-get? CertifiedRecipients { recipient: recipient })))
)

;; Core functionality: Initialize a new quantum capsule
(define-public (initialize-capsule (recipient principal) (quantum uint) (milestones (list 5 uint)))
  (let
    (
      (capsule-id (+ (var-get capsule-sequence) u1))
      (termination-block (+ block-height CAPSULE_DURATION))
    )
    (asserts! (> quantum u0) ERR_QUANTITY_UNACCEPTABLE)
    (asserts! (is-eligible-recipient recipient) ERR_VALIDATION_FAILURE)
    (asserts! (> (len milestones) u0) ERR_VALIDATION_FAILURE)
    (match (stx-transfer? quantum tx-sender (as-contract tx-sender))
      success
        (begin
          (map-set QuantumCapsules
            { capsule-id: capsule-id }
            {
              originator: tx-sender,
              recipient: recipient,
              quantum: quantum,
              phase: "active",
              genesis-block: block-height,
              termination-block: termination-block,
              milestones: milestones,
              fulfilled-milestones: u0
            }
          )
          (var-set capsule-sequence capsule-id)
          (ok capsule-id)
        )
      error ERR_TRANSACTION_REJECTED
    )
  )
)

;; Advanced distribution: Create a multi-recipient quantum distribution
(define-public (initialize-branched-capsule (destinations (list 5 { recipient: principal, allocation: uint })) (quantum uint))
  (begin
    (asserts! (> quantum u0) ERR_QUANTITY_UNACCEPTABLE)
    (asserts! (> (len destinations) u0) ERR_INVALID_CAPSULE_REFERENCE)
    (asserts! (<= (len destinations) RECIPIENT_UPPER_BOUND) ERR_RECIPIENT_CAP_REACHED)

    ;; Verify allocation distribution totals 100%
    (let
      (
        (total-allocation (fold + (map get-allocation-value destinations) u0))
      )
      (asserts! (is-eq total-allocation u100) ERR_DISTRIBUTION_IMBALANCE)

      ;; Process the capsule initialization
      (match (stx-transfer? quantum tx-sender (as-contract tx-sender))
        success
          (let
            (
              (capsule-id (+ (var-get branch-capsule-sequence) u1))
            )
            (map-set BranchedCapsules
              { branch-capsule-id: capsule-id }
              {
                originator: tx-sender,
                destinations: destinations,
                total-quantum: quantum,
                genesis-block: block-height,
                phase: "active"
              }
            )
            (var-set branch-capsule-sequence capsule-id)
            (ok capsule-id)
          )
        error ERR_TRANSACTION_REJECTED
      )
    )
  )
)

;; Milestone validation: Confirm milestone completion and distribute quantum
(define-public (validate-milestone (capsule-id uint))
  (begin
    (asserts! (is-valid-capsule-id capsule-id) ERR_INVALID_CAPSULE_REFERENCE)
    (let
      (
        (capsule (unwrap! (map-get? QuantumCapsules { capsule-id: capsule-id }) ERR_CAPSULE_MISSING))
        (milestones (get milestones capsule))
        (fulfilled-count (get fulfilled-milestones capsule))
        (recipient (get recipient capsule))
        (total-quantum (get quantum capsule))
        (distribution-quantum (/ total-quantum (len milestones)))
      )
      (asserts! (< fulfilled-count (len milestones)) ERR_RESOURCES_DEPLETED)
      (asserts! (is-eq tx-sender PROTOCOL_SUPERVISOR) ERR_PERMISSION_DENIED)
      (match (stx-transfer? distribution-quantum (as-contract tx-sender) recipient)
        success
          (begin
            (map-set QuantumCapsules
              { capsule-id: capsule-id }
              (merge capsule { fulfilled-milestones: (+ fulfilled-count u1) })
            )
            (ok true)
          )
        error ERR_TRANSACTION_REJECTED
      )
    )
  )
)

;; Originator protection: Reclaim quantum on expiration
(define-public (reclaim-quantum (capsule-id uint))
  (begin
    (asserts! (is-valid-capsule-id capsule-id) ERR_INVALID_CAPSULE_REFERENCE)
    (let
      (
        (capsule (unwrap! (map-get? QuantumCapsules { capsule-id: capsule-id }) ERR_CAPSULE_MISSING))
        (originator (get originator capsule))
        (quantum (get quantum capsule))
      )
      (asserts! (is-eq tx-sender PROTOCOL_SUPERVISOR) ERR_PERMISSION_DENIED)
      (asserts! (> block-height (get termination-block capsule)) ERR_CAPSULE_EXPIRED)
      (match (stx-transfer? quantum (as-contract tx-sender) originator)
        success
          (begin
            (map-set QuantumCapsules
              { capsule-id: capsule-id }
              (merge capsule { phase: "reclaimed" })
            )
            (ok true)
          )
        error ERR_TRANSACTION_REJECTED
      )
    )
  )
)
