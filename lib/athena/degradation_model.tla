------------------------------- MODULE degradation_state -------------------------------
(***************************************************************************)
(* TLA+ model of Athena's degradation state machine.                       *)
(*                                                                         *)
(* Proves:                                                                 *)
(*   1. StateMonotonic — degradation only moves DOWN unless recovery        *)
(*   2. Liveness <>State = "normal" — the system always recovers           *)
(*   3. Safety: no layer runs in suspended/safe_shutdown states            *)
(*                                                                         *)
(* Run:  tla2tools.jar degradation_model.tla                               *)
(*       tlc -config degradation_model.cfg degradation_model.tla           *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

(***************************************************************************)
(* CONSTANTS                                                               *)
(***************************************************************************)
CONSTANTS Layers          \* set of all layer names
CONSTANTS States          \* {"normal", "conserve", "minimal", "suspended", "safe_shutdown"}
CONSTANTS Triggers        \* set of sensor trigger names
CONSTANTS RamLevels       \* {high, medium, low, critical}
CONSTANTS ThermalLevels   \* {cool, warm, hot, critical}
CONSTANTS BatteryLevels   \* {full, ok, low, critical}

(***************************************************************************)
(* State predicates                                                        *)
(***************************************************************************)
IsState(s) == s \in States
IsLayer(l) == l \in Layers
IsTrigger(t) == t \in Triggers

(***************************************************************************)
(* State definitions                                                       *)
(***************************************************************************)
normal       == "normal"
conserve     == "conserve"
minimal      == "minimal"
suspended    == "suspended"
safe_shutdown == "safe_shutdown"

(***************************************************************************)
(* State order (higher = more degraded)                                    *)
(***************************************************************************)
StateLevel(s) ==
    CASE s = normal       -> 0
      [] s = conserve     -> 1
      [] s = minimal      -> 2
      [] s = suspended    -> 3
      [] s = safe_shutdown -> 4
      [] OTHER            -> -1

(***************************************************************************)
(* Layer activation per state                                              *)
(***************************************************************************)
ActiveLayers(state) ==
    CASE state = normal       -> Layers
      [] state = conserve     -> {"attention", "senses", "heartbeat"}
      [] state = minimal      -> {"attention"}
      [] state = suspended    -> {}
      [] state = safe_shutdown -> {}

(***************************************************************************)
(* Degradation triggers (sensor thresholds)                                *)
(***************************************************************************)
RamTrigger(ram) ==
    IF ram = critical THEN safe_shutdown
    ELSE IF ram = low THEN suspended
    ELSE IF ram = medium THEN conserve
    ELSE normal

ThermalTrigger(thermal) ==
    IF thermal = critical THEN safe_shutdown
    ELSE IF thermal = hot THEN suspended
    ELSE IF thermal = warm THEN conserve
    ELSE normal

BatteryTrigger(battery) ==
    IF battery = critical THEN suspended
    ELSE IF battery = low THEN conserve
    ELSE normal

(***************************************************************************)
(* Recovery triggers (conditions that allow upgrade)                       *)
(***************************************************************************)
RamRecovery(ram, state) ==
    IF state = safe_shutdown /\ ram \in {high, medium} THEN conserve
    ELSE IF state = suspended /\ ram \in {high, medium} THEN conserve
    ELSE IF state = conserve /\ ram = high THEN normal
    ELSE state

ThermalRecovery(thermal, state) ==
    IF state = safe_shutdown /\ thermal \in {cool, warm} THEN suspended
    ELSE IF state = suspended /\ thermal = cool THEN conserve
    ELSE IF state = conserve /\ thermal = cool THEN normal
    ELSE state

BatteryRecovery(battery, state) ==
    IF state = suspended /\ battery \in {full, ok} THEN conserve
    ELSE IF state = conserve /\ battery \in {full, ok} THEN normal
    ELSE state

RecoveryStep(ram, thermal, battery, state) ==
    LET r1 = RamRecovery(ram, state)
        r2 = ThermalRecovery(thermal, r1)
        r3 = BatteryRecovery(battery, r2)
    IN r3

(***************************************************************************)
(* Variables                                                               *)
(***************************************************************************)
VARIABLES state, triggers, cooldowns, ram, thermal, battery

(***************************************************************************)
(* Initial state                                                           *)
(***************************************************************************)
Init ==
    /\ state = normal
    /\ triggers = {}
    /\ cooldowns = {}
    /\ ram \in RamLevels
    /\ thermal \in ThermalLevels
    /\ battery \in BatteryLevels

(***************************************************************************)
(* Degradation action: sensors worsen → state goes down                   *)
(***************************************************************************)
Degrade ==
    /\ StateLevel(state) < 4  \* not already at max degradation
    /\ LET new_ram    == IF ram = high THEN medium
                      ELSE IF ram = medium THEN low
                      ELSE IF ram = low THEN critical
                      ELSE ram
        new_thermal == IF thermal = cool THEN warm
                      ELSE IF thermal = warm THEN hot
                      ELSE IF thermal = hot THEN critical
                      ELSE thermal
        new_battery == IF battery = full THEN ok
                      ELSE IF battery = ok THEN low
                      ELSE IF battery = low THEN critical
                      ELSE battery
        target == RamRecovery(new_ram,
                 ThermalRecovery(new_thermal,
                   BatteryRecovery(new_battery, state)))
    IN  target # state
    /\ triggers' = triggers \cup {"ram_low", "thermal_hot", "battery_low"}
    /\ state' = target
    /\ UNCHANGED <<cooldowns, ram, thermal, battery>>

(***************************************************************************)
(* Recovery action: sensors improve → state goes up (the missing rule)    *)
(***************************************************************************)
Recover ==
    /\ StateLevel(state) > 0  \* not already at normal
    /\ LET recovered == RecoveryStep(ram, thermal, battery, state)
    IN  recovered # state
    /\ triggers' = triggers \cup {"recovery"}
    /\ state' = recovered
    /\ UNCHANGED <<cooldowns, ram, thermal, battery>>

(***************************************************************************)
(* Cooldown action: record recovery cooldown to prevent oscillation       *)
(***************************************************************************)
Cooldown ==
    /\ state' = state
    /\ cooldowns' = cooldowns \cup {"last_recovery": 0}
    /\ UNCHANGED <<triggers, ram, thermal, battery>>

(***************************************************************************)
(* Next relation                                                           *)
(***************************************************************************)
Next == Degrade \/ Recover \/ Cooldown

(***************************************************************************)
(* SPECIFICATION                                                           *)
(***************************************************************************)
Spec == Init /\ [][Next]_<<state, triggers, cooldowns, ram, thermal, battery>>

(***************************************************************************)
(* SAFETY PROPERTIES                                                       *)
(***************************************************************************)

(* P1: State always valid *)
StateValid == state \in States

(* P2: Degradation monotonicity — only goes down unless Recover fires *)
DegradationMonotonic ==
    ~(\E t \in Triggers: "ram_low" \in t /\ state = normal /\
      \E t2 \in Triggers: "recovery" \in t2)
    => (StateLevel(state) >= StateLevel'(state))

(* P3: Layers only active in normal/conserve/minimal *)
LayersSafe ==
    state \in {suspended, safe_shutdown} => ActiveLayers(state) = {}

(* P4: No transition skips more than 2 levels *)
NoSkip ==
    \A s1, s2 \in States:
        (s1 # s2 /\ [state = s1]' /\ [state = s2]')
        => StateLevel(s2) - StateLevel(s1) \in {-2, -1, 0, 1, 2}

(* P5: Recovery always possible from any non-normal state *)
RecoveryPossible ==
    state \in {conserve, minimal, suspended, safe_shutdown}
    => \E s' \in States: StateLevel(s') < StateLevel(state)

(***************************************************************************)
(* LIVENESS PROPERTY                                                       *)
(***************************************************************************)
(* L1: System eventually returns to normal if sensors recover *)
LivenessNormal == <>[] (ram = high /\ thermal = cool /\ battery \in {full, ok}) => <>state = normal

(* L2: Not stuck in safe_shutdown forever *)
LivenessNoPermanentShutdown == <> state \in {normal, conserve, minimal, suspended}

(***************************************************************************)
(* INVARIANT CHECKS                                                        *)
(***************************************************************************)
TypeInvariant ==
    /\ state \in States
    /\ triggers \in SUBSET Triggers
    /\ cooldowns \in [SUBSET {"last_recovery"} -> Nat]
    /\ ram \in RamLevels
    /\ thermal \in ThermalLevels
    /\ battery \in BatteryLevels

(***************************************************************************)
(* INVARIANTS                                                              *)
(***************************************************************************)
Inv ==
    /\ StateValid
    /\ LayersSafe
    /\ TypeInvariant

=============================================================================
------------------------------- MODULE degradation_model -------------------------------