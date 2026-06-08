%% ── 0. CLEAN SLATE ───────────────────────────────────────────────────────
clear; clc; close all;

MODEL = 'SmartSense_EMS';          % model name (no spaces → valid identifier)

% Close and delete any previously loaded version
if bdIsLoaded(MODEL)
    close_system(MODEL, 0);
end

% ── Simulation parameters (change here to retune) ────────────────────────
STOP_TIME     = 86400;   % 24 hours in seconds
SAMPLE_TIME   = 1;       % 1-second fixed step
VACANT_DELAY  = 300;     % 5 min before room declared empty
LIGHT_W       = 40;
FAN_W         = 70;
AC_W          = 1200;
TOTAL_W       = LIGHT_W + FAN_W + AC_W;   % 1310 W

fprintf('╔══════════════════════════════════════════════════════╗\n');
fprintf('║   SmartSense EMS  ─  Simulink Model Builder          ║\n');
fprintf('║   MATLAB R2024a/b                                     ║\n');
fprintf('╚══════════════════════════════════════════════════════╝\n\n');

%% ── 1. CREATE MODEL ──────────────────────────────────────────────────────
new_system(MODEL);
open_system(MODEL);

% Solver: fixed-step ODE3 (Bogacki-Shampine), 1-second step
set_param(MODEL, ...
    'StopTime',      num2str(STOP_TIME), ...
    'SolverType',    'Fixed-step', ...
    'Solver',        'ode3', ...
    'FixedStep',     num2str(SAMPLE_TIME), ...
    'SystemTargetFile', 'grt.tlc');   % generic real-time (safe default)

fprintf('[1/6] Model "%s" created  (stop=%ds, dt=%ds)\n', ...
        MODEL, STOP_TIME, SAMPLE_TIME);

%% =========================================================================
%%  SECTION A ─ OCCUPANCY SIGNAL GENERATOR SUBSYSTEM
%%  Produces realistic 24-hour PIR (motion) and IR (seated) signals.
%%
%%  Student schedule modelled:
%%   07:00-08:00  Arrival                  PIR bursts, IR rising
%%   08:00-12:00  Morning study session    IR sustained, PIR periodic
%%   12:00-13:00  Lunch break              Both sensors LOW
%%   13:00-17:00  Afternoon study          IR sustained, PIR periodic
%%   17:00-18:00  Short outing             Both sensors LOW
%%   18:00-22:00  Evening session          IR sustained, PIR periodic
%%   22:00-07:00  Sleeping / out           Both sensors LOW
%% =========================================================================

fprintf('[2/6] Building OccupancySignalGen subsystem...\n');

SS_OCC = [MODEL '/OccupancySignalGen'];
add_block('built-in/Subsystem', SS_OCC, ...
    'Position', [40, 100, 220, 220]);

%  ── Internal layout of the subsystem ──────────────────────────────────
%  All block paths below are relative to SS_OCC

% ---- PIR pulse generators (motion bursts during each occupied window) ----
% Pulse Generator parameters:
%   Period     = how often a burst repeats (seconds)
%   PulseWidth = % of period the pulse is HIGH
%   PhaseDelay = when the first pulse starts (seconds from t=0)
%
% Morning window  08:00–12:00  (t=28800 to 43200 s)
add_block('simulink/Sources/Pulse Generator', ...
    [SS_OCC '/PIR_Morning'], ...
    'Position',   [30, 25, 105, 55], ...
    'Amplitude',  '1', ...
    'Period',     '600', ...       % burst every 10 min
    'PulseWidth', '20', ...        % 20% = 120 s HIGH per burst
    'PhaseDelay', '28800', ...     % starts at 08:00
    'SampleTime', '1');

% Afternoon window  13:00–17:00  (t=46800 to 61200 s)
add_block('simulink/Sources/Pulse Generator', ...
    [SS_OCC '/PIR_Afternoon'], ...
    'Position',   [30, 75, 105, 105], ...
    'Amplitude',  '1', ...
    'Period',     '600', ...
    'PulseWidth', '20', ...
    'PhaseDelay', '46800', ...     % starts at 13:00
    'SampleTime', '1');

% Evening window  18:00–22:00  (t=64800 to 79200 s)
add_block('simulink/Sources/Pulse Generator', ...
    [SS_OCC '/PIR_Evening'], ...
    'Position',   [30, 125, 105, 155], ...
    'Amplitude',  '1', ...
    'Period',     '600', ...
    'PulseWidth', '20', ...
    'PhaseDelay', '64800', ...     % starts at 18:00
    'SampleTime', '1');

% ---- IR pulse generators (sustained HIGH while person is seated) ----
% Higher PulseWidth = person seated for most of the session
% Morning study  08:00–12:00
add_block('simulink/Sources/Pulse Generator', ...
    [SS_OCC '/IR_Morning'], ...
    'Position',   [30, 185, 105, 215], ...
    'Amplitude',  '1', ...
    'Period',     '14400', ...     % one cycle per 4-hour session
    'PulseWidth', '80', ...        % HIGH for 80% of session
    'PhaseDelay', '28800', ...     % 08:00
    'SampleTime', '1');

% Afternoon study  13:00–17:00
add_block('simulink/Sources/Pulse Generator', ...
    [SS_OCC '/IR_Afternoon'], ...
    'Position',   [30, 235, 105, 265], ...
    'Amplitude',  '1', ...
    'Period',     '14400', ...
    'PulseWidth', '80', ...
    'PhaseDelay', '46800', ...     % 13:00
    'SampleTime', '1');

% Evening  18:00–22:00
add_block('simulink/Sources/Pulse Generator', ...
    [SS_OCC '/IR_Evening'], ...
    'Position',   [30, 285, 105, 315], ...
    'Amplitude',  '1', ...
    'Period',     '14400', ...
    'PulseWidth', '80', ...
    'PhaseDelay', '64800', ...     % 18:00
    'SampleTime', '1');

% ---- OR logic to combine the three PIR windows into one signal ----
% R2024: Logical Operator block lives in Logic and Bit Operations library
add_block('simulink/Logic and Bit Operations/Logical Operator', ...
    [SS_OCC '/PIR_OR'], ...
    'Position',        [155, 55, 200, 125], ...
    'Operator',        'OR', ...
    'Inputs',          '3', ...
    'OutDataTypeStr',  'boolean');

add_line(SS_OCC, 'PIR_Morning/1',   'PIR_OR/1', 'autorouting','on');
add_line(SS_OCC, 'PIR_Afternoon/1', 'PIR_OR/2', 'autorouting','on');
add_line(SS_OCC, 'PIR_Evening/1',   'PIR_OR/3', 'autorouting','on');

% ---- OR logic to combine the three IR windows into one signal ----
add_block('simulink/Logic and Bit Operations/Logical Operator', ...
    [SS_OCC '/IR_OR'], ...
    'Position',        [155, 220, 200, 290], ...
    'Operator',        'OR', ...
    'Inputs',          '3', ...
    'OutDataTypeStr',  'boolean');

add_line(SS_OCC, 'IR_Morning/1',   'IR_OR/1', 'autorouting','on');
add_line(SS_OCC, 'IR_Afternoon/1', 'IR_OR/2', 'autorouting','on');
add_line(SS_OCC, 'IR_Evening/1',   'IR_OR/3', 'autorouting','on');

% ---- Convert boolean → double so downstream blocks accept the signal ----
add_block('simulink/Signal Attributes/Data Type Conversion', ...
    [SS_OCC '/PIR_Bool2Dbl'], ...
    'Position',         [225, 75, 265, 105], ...
    'OutDataTypeStr',   'double');

add_block('simulink/Signal Attributes/Data Type Conversion', ...
    [SS_OCC '/IR_Bool2Dbl'], ...
    'Position',         [225, 240, 265, 270], ...
    'OutDataTypeStr',   'double');

add_line(SS_OCC, 'PIR_OR/1', 'PIR_Bool2Dbl/1', 'autorouting','on');
add_line(SS_OCC, 'IR_OR/1',  'IR_Bool2Dbl/1',  'autorouting','on');

% ---- Outports -------------------------------------------------------
add_block('simulink/Ports & Subsystems/Out1', ...
    [SS_OCC '/PIR_Out'], 'Position', [295, 82, 320, 98]);
add_block('simulink/Ports & Subsystems/Out1', ...
    [SS_OCC '/IR_Out'],  'Position', [295, 247, 320, 263]);

add_line(SS_OCC, 'PIR_Bool2Dbl/1', 'PIR_Out/1', 'autorouting','on');
add_line(SS_OCC, 'IR_Bool2Dbl/1',  'IR_Out/1',  'autorouting','on');

fprintf('    OccupancySignalGen: 6 pulse generators, 2 OR gates, 2 outports\n');

%% =========================================================================
%%  SECTION B ─ STATEFLOW FSM (OccupancyFSM)
%%
%%  R2024 Stateflow API  ─  key points:
%%   • Use sfroot to find the machine/chart objects
%%   • Chart must be inside a Simulink model, added via 'sflib/Chart'
%%   • States, Transitions, Data are all added as Stateflow objects
%%   • ChartUpdate = 'DISCRETE' with SampleTime for fixed-step compatibility
%% =========================================================================

fprintf('[3/6] Building Stateflow FSM (OccupancyFSM)...\n');

SF_PATH = [MODEL '/OccupancyFSM'];
add_block('sflib/Chart', SF_PATH, ...
    'Position', [290, 100, 490, 220]);

% ── Find the chart via sfroot (R2024 recommended approach) ────────────────
rt    = sfroot;                         % Stateflow root object
mach  = rt.find('-isa','Stateflow.Machine', 'Name', MODEL);

if isempty(mach)
    error('Stateflow machine not found. Make sure Stateflow is installed.');
end

chart = mach.find('-isa','Stateflow.Chart');

% There may be multiple charts if this script is re-run; take the last one
chart = chart(end);

% ── Configure chart properties ────────────────────────────────────────────
chart.ChartUpdate = 'DISCRETE';        % runs on fixed sample time
chart.SampleTime  = num2str(SAMPLE_TIME);
chart.ActionLanguage = 'MATLAB';       % MATLAB action language (not C)
chart.Name        = 'OccupancyFSM';

% ── INPUT DATA (from Simulink inports) ───────────────────────────────────
dPIR              = Stateflow.Data(chart);
dPIR.Name         = 'PIR';
dPIR.Scope        = 'Input';
dPIR.Port         = 1;
dPIR.Props.Type.Method  = 'Inherited';   % inherits double from subsystem

dIR               = Stateflow.Data(chart);
dIR.Name          = 'IR';
dIR.Scope         = 'Input';
dIR.Port          = 2;
dIR.Props.Type.Method   = 'Inherited';

% ── OUTPUT DATA ───────────────────────────────────────────────────────────
dState            = Stateflow.Data(chart);
dState.Name       = 'ctrl_state';
dState.Scope      = 'Output';
dState.Port       = 1;
dState.Props.Type.Method      = 'Built-in';
dState.Props.Type.Primitive   = 'uint8';
dState.Props.InitialValue     = '0';

% ── LOCAL VARIABLE (vacancy hold-off timer) ───────────────────────────────
dTimer            = Stateflow.Data(chart);
dTimer.Name       = 'vacant_timer';
dTimer.Scope      = 'Local';
dTimer.Props.Type.Method      = 'Built-in';
dTimer.Props.Type.Primitive   = 'double';
dTimer.Props.InitialValue     = '0';

% ── DEFINE THE 4 STATES ───────────────────────────────────────────────────
%
%  Layout (pixels inside the chart canvas):
%
%    EMPTY ──────────► ENTERING
%      ▲                  │
%      │                  ▼
%    VACANT_DELAY ◄── OCCUPIED
%

stEmpty = Stateflow.State(chart);
stEmpty.Name     = 'EMPTY';
stEmpty.Position = [40, 40, 180, 90];
% Entry action: reset outputs and timer
stEmpty.LabelString = ['EMPTY' newline ...
    'entry: ctrl_state = uint8(0);' newline ...
    'entry: vacant_timer = 0;'];

stEntering = Stateflow.State(chart);
stEntering.Name     = 'ENTERING';
stEntering.Position = [300, 40, 180, 90];
% Entry: light goes on immediately (handled in ApplianceController by state=1)
stEntering.LabelString = ['ENTERING' newline ...
    'entry: ctrl_state = uint8(1);'];

stOccupied = Stateflow.State(chart);
stOccupied.Name     = 'OCCUPIED';
stOccupied.Position = [300, 210, 180, 90];
% Entry: full appliance control (handled downstream)
stOccupied.LabelString = ['OCCUPIED' newline ...
    'entry: ctrl_state = uint8(2);'];

stVacant = Stateflow.State(chart);
stVacant.Name     = 'VACANT_DELAY';
stVacant.Position = [40, 210, 180, 90];
% During: increment the vacancy timer every sample step
stVacant.LabelString = ['VACANT_DELAY' newline ...
    'entry: ctrl_state = uint8(3);' newline ...
    'entry: vacant_timer = 0;' newline ...
    'during: vacant_timer = vacant_timer + 1;'];

% ── DEFAULT TRANSITION (enter EMPTY at t=0) ───────────────────────────────
defTr = Stateflow.Transition(chart);
defTr.Destination         = stEmpty;
defTr.DestinationOClock   = 9;     % arrow comes from the left

% ── STATE TRANSITIONS ─────────────────────────────────────────────────────
%  Condition strings must match the Data names defined above.

% EMPTY → ENTERING  :  any sensor fires
t_E2N = Stateflow.Transition(chart);
t_E2N.Source      = stEmpty;
t_E2N.Destination = stEntering;
t_E2N.LabelString = '[PIR || IR]';
t_E2N.LabelPosition = [130 25 53.5 16];

% ENTERING → OCCUPIED  :  both sensors confirm person is present
t_N2O = Stateflow.Transition(chart);
t_N2O.Source      = stEntering;
t_N2O.Destination = stOccupied;
t_N2O.LabelString = '[PIR && IR]';

% ENTERING → EMPTY  :  false trigger — sensors go quiet quickly
t_N2E = Stateflow.Transition(chart);
t_N2E.Source      = stEntering;
t_N2E.Destination = stEmpty;
t_N2E.LabelString = '[~PIR && ~IR]';

% OCCUPIED → VACANT_DELAY  :  sensors go silent (person may have stepped out)
t_O2V = Stateflow.Transition(chart);
t_O2V.Source      = stOccupied;
t_O2V.Destination = stVacant;
t_O2V.LabelString = '[~PIR && ~IR]';

% VACANT_DELAY → OCCUPIED  :  person returned before timeout
t_V2O = Stateflow.Transition(chart);
t_V2O.Source      = stVacant;
t_V2O.Destination = stOccupied;
t_V2O.LabelString = '[PIR || IR]';

% VACANT_DELAY → EMPTY  :  timeout expired → room truly empty
t_V2E = Stateflow.Transition(chart);
t_V2E.Source      = stVacant;
t_V2E.Destination = stEmpty;
t_V2E.LabelString = sprintf('[vacant_timer >= %d]', VACANT_DELAY);

fprintf('    Stateflow chart: 4 states, 6 transitions, MATLAB action language\n');

%% =========================================================================
%%  SECTION C ─ APPLIANCE CONTROLLER SUBSYSTEM
%%
%%  Input:  ctrl_state  (uint8, 0-3)
%%  Output: P_smart     (double, W) — SmartSense-controlled power
%%          P_conv      (double, W) — Conventional always-on power
%%
%%  Switching logic:
%%    Light (40W)  ON when state >= 1   (ENTERING, OCCUPIED, VACANT_DELAY)
%%    Fan   (70W)  ON when state >= 2   (OCCUPIED, VACANT_DELAY)
%%    AC  (1200W)  ON when state == 2   (OCCUPIED only)
%%
%%  Implementation uses Compare-To-Constant + Product (relay switch pattern)
%% =========================================================================

fprintf('[4/6] Building ApplianceController subsystem...\n');

SS_APP = [MODEL '/ApplianceController'];
add_block('built-in/Subsystem', SS_APP, ...
    'Position', [560, 100, 760, 220]);

% ── Inport: ctrl_state from FSM ─────────────────────────────────────────
add_block('simulink/Ports & Subsystems/In1', ...
    [SS_APP '/ctrl_in'], ...
    'Position', [20, 155, 45, 175]);

% ── Type conversion: uint8 → double for arithmetic operations ─────────────
add_block('simulink/Signal Attributes/Data Type Conversion', ...
    [SS_APP '/uint8_to_dbl'], ...
    'Position',       [65, 150, 110, 180], ...
    'OutDataTypeStr', 'double');

add_line(SS_APP, 'ctrl_in/1', 'uint8_to_dbl/1', 'autorouting','on');

% ── Power constants ──────────────────────────────────────────────────────
add_block('simulink/Sources/Constant', ...
    [SS_APP '/C_Light'], ...
    'Position', [65, 30, 115, 60], ...
    'Value',    num2str(LIGHT_W));

add_block('simulink/Sources/Constant', ...
    [SS_APP '/C_Fan'], ...
    'Position', [65, 90, 115, 120], ...
    'Value',    num2str(FAN_W));

add_block('simulink/Sources/Constant', ...
    [SS_APP '/C_AC'], ...
    'Position', [65, 230, 115, 260], ...
    'Value',    num2str(AC_W));

% ── Compare-to-Constant blocks (generate 0/1 relay signals) ──────────────
% R2024 correct path: simulink/Logic and Bit Operations/Compare To Constant
add_block('simulink/Logic and Bit Operations/Compare To Constant', ...
    [SS_APP '/Light_Cond'], ...
    'Position',       [145, 35, 215, 65], ...
    'relop',       '>=', ...
    'const',          '1' );   % output 0.0 / 1.0 (not boolean) for Product

add_block('simulink/Logic and Bit Operations/Compare To Constant', ...
    [SS_APP '/Fan_Cond'], ...
    'Position',       [145, 95, 215, 125], ...
    'relop',       '>=', ...
    'const',          '2');

add_block('simulink/Logic and Bit Operations/Compare To Constant', ...
    [SS_APP '/AC_Cond'], ...
    'Position',       [145, 235, 215, 265], ...
    'relop',       '==', ...
    'const',          '2');

% ── Wire ctrl_state → all comparators ────────────────────────────────────
add_line(SS_APP, 'uint8_to_dbl/1', 'Light_Cond/1', 'autorouting','on');
add_line(SS_APP, 'uint8_to_dbl/1', 'Fan_Cond/1',   'autorouting','on');
add_line(SS_APP, 'uint8_to_dbl/1', 'AC_Cond/1',    'autorouting','on');

% ── Product blocks: multiply condition(0/1) × rated_power ────────────────
add_block('simulink/Math Operations/Product', ...
    [SS_APP '/Light_Relay'], 'Position', [245, 28, 285, 72]);
add_block('simulink/Math Operations/Product', ...
    [SS_APP '/Fan_Relay'],   'Position', [245, 88, 285, 132]);
add_block('simulink/Math Operations/Product', ...
    [SS_APP '/AC_Relay'],    'Position', [245, 228, 285, 272]);

add_line(SS_APP, 'Light_Cond/1', 'Light_Relay/1', 'autorouting','on');
add_line(SS_APP, 'C_Light/1',    'Light_Relay/2', 'autorouting','on');
add_line(SS_APP, 'Fan_Cond/1',   'Fan_Relay/1',   'autorouting','on');
add_line(SS_APP, 'C_Fan/1',      'Fan_Relay/2',   'autorouting','on');
add_line(SS_APP, 'AC_Cond/1',    'AC_Relay/1',    'autorouting','on');
add_line(SS_APP, 'C_AC/1',       'AC_Relay/2',    'autorouting','on');

% ── Sum: total SmartSense power ───────────────────────────────────────────
add_block('simulink/Math Operations/Sum', ...
    [SS_APP '/P_Smart_Sum'], ...
    'Position', [320, 90, 360, 170], ...
    'Inputs',   '+++');    % 3 positive inputs (Light+Fan+AC)

add_line(SS_APP, 'Light_Relay/1', 'P_Smart_Sum/1', 'autorouting','on');
add_line(SS_APP, 'Fan_Relay/1',   'P_Smart_Sum/2', 'autorouting','on');
add_line(SS_APP, 'AC_Relay/1',    'P_Smart_Sum/3', 'autorouting','on');

% ── Conventional power: fixed constant (all loads always on) ─────────────
add_block('simulink/Sources/Constant', ...
    [SS_APP '/C_Conventional'], ...
    'Position', [320, 200, 390, 230], ...
    'Value',    num2str(TOTAL_W));

% ── Outports ─────────────────────────────────────────────────────────────
add_block('simulink/Ports & Subsystems/Out1', ...
    [SS_APP '/P_Smart_Out'], 'Position', [400, 118, 430, 138]);
add_block('simulink/Ports & Subsystems/Out1', ...
    [SS_APP '/P_Conv_Out'],  'Position', [430, 207, 460, 227]);

add_line(SS_APP, 'P_Smart_Sum/1',    'P_Smart_Out/1', 'autorouting','on');
add_line(SS_APP, 'C_Conventional/1', 'P_Conv_Out/1',  'autorouting','on');

fprintf('    ApplianceController: 3 relay switches, SmartSense + Conventional outputs\n');

%% =========================================================================
%%  SECTION D ─ ENERGY CALCULATOR SUBSYSTEM
%%
%%  Computes cumulative energy via numerical integration:
%%    E(t) = ∫₀ᵗ P(τ) dτ   [Watt-seconds]  then ÷ 3600 → Wh
%%
%%  NOTE: For a fixed-step discrete model we use a Discrete-Time Integrator
%%  (simulink/Discrete/Discrete-Time Integrator) instead of the continuous
%%  Integrator, which is more appropriate and numerically stable at dt=1s.
%% =========================================================================

fprintf('[5/6] Building EnergyCalculator subsystem...\n');

SS_EN = [MODEL '/EnergyCalculator'];
add_block('built-in/Subsystem', SS_EN, ...
    'Position', [830, 100, 1030, 220]);

% Two inports
add_block('simulink/Ports & Subsystems/In1', ...
    [SS_EN '/P_Smart_In'], 'Position', [20, 70, 50, 90]);
add_block('simulink/Ports & Subsystems/In1', ...
    [SS_EN '/P_Conv_In'],  'Position', [20, 180, 50, 200]);

% Discrete-Time Integrators (forward Euler, sample time = 1s)
% R2024 path: simulink/Discrete/Discrete-Time Integrator
add_block('simulink/Discrete/Discrete-Time Integrator', ...
    [SS_EN '/DTI_Smart'], ...
    'Position',   [100, 60, 160, 100], ...
    'SampleTime', num2str(SAMPLE_TIME), ...
    'gainval',    '1.0', ...
    'InitialCondition', '0');

add_block('simulink/Discrete/Discrete-Time Integrator', ...
    [SS_EN '/DTI_Conv'], ...
    'Position',   [100, 170, 160, 210], ...
    'SampleTime', num2str(SAMPLE_TIME), ...
    'gainval',    '1.0', ...
    'InitialCondition', '0');

add_line(SS_EN, 'P_Smart_In/1', 'DTI_Smart/1', 'autorouting','on');
add_line(SS_EN, 'P_Conv_In/1',  'DTI_Conv/1',  'autorouting','on');

% Gain blocks: convert Watt-seconds → Watt-hours (÷ 3600)
add_block('simulink/Math Operations/Gain', ...
    [SS_EN '/Ws2Wh_Smart'], ...
    'Position', [200, 60, 255, 100], ...
    'Gain',     '1/3600');

add_block('simulink/Math Operations/Gain', ...
    [SS_EN '/Ws2Wh_Conv'], ...
    'Position', [200, 170, 255, 210], ...
    'Gain',     '1/3600');

add_line(SS_EN, 'DTI_Smart/1', 'Ws2Wh_Smart/1', 'autorouting','on');
add_line(SS_EN, 'DTI_Conv/1',  'Ws2Wh_Conv/1',  'autorouting','on');

% Savings = E_conv − E_smart  (sum with +-)
add_block('simulink/Math Operations/Sum', ...
    [SS_EN '/Savings'], ...
    'Position', [300, 110, 340, 160], ...
    'Inputs',   '+-');   % input 1 = +E_conv, input 2 = -E_smart

add_line(SS_EN, 'Ws2Wh_Conv/1',  'Savings/1', 'autorouting','on');
add_line(SS_EN, 'Ws2Wh_Smart/1', 'Savings/2', 'autorouting','on');

% Three outports: E_smart, E_conv, E_savings
add_block('simulink/Ports & Subsystems/Out1', ...
    [SS_EN '/E_Smart_Out'],   'Position', [375, 68, 405, 88]);
add_block('simulink/Ports & Subsystems/Out1', ...
    [SS_EN '/E_Conv_Out'],    'Position', [375, 178, 405, 198]);
add_block('simulink/Ports & Subsystems/Out1', ...
    [SS_EN '/E_Savings_Out'], 'Position', [375, 122, 405, 142]);

add_line(SS_EN, 'Ws2Wh_Smart/1', 'E_Smart_Out/1',   'autorouting','on');
add_line(SS_EN, 'Ws2Wh_Conv/1',  'E_Conv_Out/1',    'autorouting','on');
add_line(SS_EN, 'Savings/1',     'E_Savings_Out/1', 'autorouting','on');

fprintf('    EnergyCalculator: Discrete-Time Integrators, Wh conversion, savings\n');

%% =========================================================================
%%  SECTION E ─ DASHBOARD LAYER (Top-level scopes and displays)
%% =========================================================================

fprintf('[6/6] Building Dashboard (Scopes & Displays)...\n');

% ── Scope 1: Sensor Signals + FSM State ──────────────────────────────────
%  3 inputs: PIR, IR, ctrl_state
add_block('simulink/Sinks/Scope', ...
    [MODEL '/Scope_Sensors_FSM'], ...
    'Position',      [290, 270, 360, 320], ...
    'NumInputPorts', '3', ...
    'Open',          'off');
set_param([MODEL '/Scope_Sensors_FSM'], ...
    'Title', 'Occupancy: PIR / IR / FSM State');

% ── Scope 2: Power comparison (Conventional vs SmartSense) ───────────────
add_block('simulink/Sinks/Scope', ...
    [MODEL '/Scope_Power'], ...
    'Position',      [560, 270, 630, 320], ...
    'NumInputPorts', '2', ...
    'Open',          'off');
set_param([MODEL '/Scope_Power'], ...
    'Title', 'Power (W): Conventional vs SmartSense');

% ── Scope 3: Cumulative Energy curves ────────────────────────────────────
add_block('simulink/Sinks/Scope', ...
    [MODEL '/Scope_Energy'], ...
    'Position',      [830, 270, 900, 320], ...
    'NumInputPorts', '3', ...
    'Open',          'off');
set_param([MODEL '/Scope_Energy'], ...
    'Title', 'Energy (Wh): Conv / Smart / Savings');

% ── Display: live cumulative savings value (Wh) ───────────────────────────
add_block('simulink/Sinks/Display', ...
    [MODEL '/Display_Savings_Wh'], ...
    'Position', [830, 340, 1020, 380], ...
    'Format',   'short');

% ── To Workspace: export data for post-processing / plotting ─────────────
add_block('simulink/Sinks/To Workspace', ...
    [MODEL '/Log_PIR'], ...
    'Position',     [40, 340, 130, 370], ...
    'VariableName', 'log_PIR', ...
    'SaveFormat',   'Array');

add_block('simulink/Sinks/To Workspace', ...
    [MODEL '/Log_IR'], ...
    'Position',     [40, 390, 130, 420], ...
    'VariableName', 'log_IR', ...
    'SaveFormat',   'Array');

add_block('simulink/Sinks/To Workspace', ...
    [MODEL '/Log_State'], ...
    'Position',     [290, 340, 380, 370], ...
    'VariableName', 'log_State', ...
    'SaveFormat',   'Array');

add_block('simulink/Sinks/To Workspace', ...
    [MODEL '/Log_P_Smart'], ...
    'Position',     [560, 340, 660, 370], ...
    'VariableName', 'log_P_Smart', ...
    'SaveFormat',   'Array');

add_block('simulink/Sinks/To Workspace', ...
    [MODEL '/Log_P_Conv'], ...
    'Position',     [560, 390, 660, 420], ...
    'VariableName', 'log_P_Conv', ...
    'SaveFormat',   'Array');

fprintf('    Dashboard: 3 Scopes, 1 Display, 5 To-Workspace loggers\n\n');

%% =========================================================================
%%  SECTION F ─ TOP-LEVEL WIRING
%%  Connect all subsystem ports together
%% =========================================================================

fprintf('Wiring top-level connections...\n');

% ── OccupancySignalGen → OccupancyFSM ─────────────────────────────────────
add_line(MODEL, 'OccupancySignalGen/1', 'OccupancyFSM/1', 'autorouting','on');  % PIR
add_line(MODEL, 'OccupancySignalGen/2', 'OccupancyFSM/2', 'autorouting','on');  % IR

% ── OccupancyFSM → ApplianceController ────────────────────────────────────
add_line(MODEL, 'OccupancyFSM/1', 'ApplianceController/1', 'autorouting','on'); % ctrl_state

% ── ApplianceController → EnergyCalculator ────────────────────────────────
add_line(MODEL, 'ApplianceController/1', 'EnergyCalculator/1', 'autorouting','on'); % P_smart
add_line(MODEL, 'ApplianceController/2', 'EnergyCalculator/2', 'autorouting','on'); % P_conv

% ── Scope_Sensors_FSM: PIR, IR, State ─────────────────────────────────────
add_line(MODEL, 'OccupancySignalGen/1', 'Scope_Sensors_FSM/1', 'autorouting','on');
add_line(MODEL, 'OccupancySignalGen/2', 'Scope_Sensors_FSM/2', 'autorouting','on');
add_line(MODEL, 'OccupancyFSM/1',       'Scope_Sensors_FSM/3', 'autorouting','on');

% ── Scope_Power: Conventional (port 2), SmartSense (port 1) ───────────────
add_line(MODEL, 'ApplianceController/2', 'Scope_Power/1', 'autorouting','on'); % Conv
add_line(MODEL, 'ApplianceController/1', 'Scope_Power/2', 'autorouting','on'); % Smart

% ── Scope_Energy: E_conv, E_smart, Savings ────────────────────────────────
add_line(MODEL, 'EnergyCalculator/2', 'Scope_Energy/1', 'autorouting','on');   % E_conv
add_line(MODEL, 'EnergyCalculator/1', 'Scope_Energy/2', 'autorouting','on');   % E_smart
add_line(MODEL, 'EnergyCalculator/3', 'Scope_Energy/3', 'autorouting','on');   % Savings

% ── Display: live savings (Wh) ────────────────────────────────────────────
add_line(MODEL, 'EnergyCalculator/3', 'Display_Savings_Wh/1', 'autorouting','on');

% ── To-Workspace loggers (branched from main signals) ─────────────────────
add_line(MODEL, 'OccupancySignalGen/1', 'Log_PIR/1',     'autorouting','on');
add_line(MODEL, 'OccupancySignalGen/2', 'Log_IR/1',      'autorouting','on');
add_line(MODEL, 'OccupancyFSM/1',       'Log_State/1',   'autorouting','on');
add_line(MODEL, 'ApplianceController/1','Log_P_Smart/1', 'autorouting','on');
add_line(MODEL, 'ApplianceController/2','Log_P_Conv/1',  'autorouting','on');

fprintf('    All connections established.\n\n');

%% =========================================================================
%%  SECTION G ─ ANNOTATIONS (descriptive labels in the model canvas)
%% =========================================================================

Simulink.Annotation([MODEL '/ann_title'], ...
    'Text', ...
    ['SmartSense Hostel EMS  |  MATLAB R2024  |  ' ...
     'PIR+IR Fusion → Stateflow FSM → Appliance Control → Energy Dashboard'], ...
    'Position', [40, 20]);

Simulink.Annotation([MODEL '/ann_states'], ...
    'Text', ...
    'FSM: 0=EMPTY  1=ENTERING  2=OCCUPIED  3=VACANT_DELAY', ...
    'Position', [290, 240]);

Simulink.Annotation([MODEL '/ann_loads'], ...
    'Text', ...
    sprintf('Loads: Light=%dW  Fan=%dW  AC=%dW  |  Conventional=%dW always-on', ...
            LIGHT_W, FAN_W, AC_W, TOTAL_W), ...
    'Position', [560, 240]);

%% =========================================================================
%%  SECTION H ─ SAVE & AUTO-LAYOUT
%% =========================================================================

% Apply Simulink auto-layout to clean up routing
Simulink.BlockDiagram.arrangeSystem(MODEL);

save_system(MODEL);

fprintf('╔══════════════════════════════════════════════════════╗\n');
fprintf('║   MODEL BUILD COMPLETE                               ║\n');
fprintf('╠══════════════════════════════════════════════════════╣\n');
fprintf('║  File  : %s.slx\n', MODEL);
fprintf('║  Press : Ctrl+T to simulate (24 hours)\n');
fprintf('╠══════════════════════════════════════════════════════╣\n');
fprintf('║  SCOPE GUIDE                                         ║\n');
fprintf('║  Scope_Sensors_FSM  →  PIR / IR pulses + FSM state  ║\n');
fprintf('║  Scope_Power        →  %4dW flat vs smart curve     ║\n', TOTAL_W);
fprintf('║  Scope_Energy       →  Wh curves + savings gap      ║\n');
fprintf('║  Display_Savings_Wh →  live cumulative savings (Wh) ║\n');
fprintf('╠══════════════════════════════════════════════════════╣\n');
fprintf('║  WORKSPACE LOGS (after simulation)                   ║\n');
fprintf('║  log_PIR, log_IR, log_State, log_P_Smart, log_P_Conv ║\n');
fprintf('╠══════════════════════════════════════════════════════╣\n');
fprintf('║  ESTIMATED SAVINGS                                   ║\n');
fprintf('║  Conventional  : ~%.1f kWh/day                       ║\n', TOTAL_W*24/1000);
fprintf('║  SmartSense    : ~%.1f kWh/day  (60%% occ.)          ║\n', TOTAL_W*24*0.6/1000);
fprintf('║  Savings       : ~%.1f kWh/day  (~40%%)              ║\n', TOTAL_W*24*0.4/1000);
fprintf('╚══════════════════════════════════════════════════════╝\n');

%% =========================================================================
%%  SECTION I ─ POST-SIMULATION PLOTTING  (run after Ctrl+T)
%%
%%  After the simulation finishes, call SmartSense_PostPlot() to generate
%%  a clean MATLAB figure dashboard from the To-Workspace logs.
%% =========================================================================

% ── Inline post-plot function ─────────────────────────────────────────────
% Save to a separate file so it can be called after sim completes
post_plot_code = [
"function SmartSense_PostPlot()" newline ...
"% Call after simulating SmartSense_EMS to plot results from workspace logs" newline ...
"t = (0:length(log_PIR)-1)';" newline ...
"t_h = t/3600;" newline ...
"E_smart = cumsum(log_P_Smart)/3600;" newline ...
"E_conv  = cumsum(log_P_Conv)/3600;" newline ...
"E_saved = E_conv - E_smart;" newline ...
"figure('Name','SmartSense EMS Dashboard','Color','k','Position',[50 50 1400 800]);" newline ...
"tiledlayout(3,1,'TileSpacing','compact','Padding','compact');" newline ...
"ax1=nexttile; hold on; grid on;" newline ...
"plot(t_h,log_PIR,'b','LineWidth',1,'DisplayName','PIR (Motion)');" newline ...
"plot(t_h,log_IR,'g','LineWidth',1,'DisplayName','IR (Seated)');" newline ...
"plot(t_h,log_State/3,'r--','LineWidth',1,'DisplayName','FSM State (norm.)');" newline ...
"legend('TextColor','w','Color','k'); title('Occupancy Sensors & FSM State','Color','w');" newline ...
"ylabel('Level','Color','w'); set(ax1,'Color','#0d1117','XColor','w','YColor','w');" newline ...
"ax2=nexttile; hold on; grid on;" newline ...
"plot(t_h,log_P_Conv, 'r','LineWidth',1.5,'DisplayName',sprintf('Conventional (%dW)',sum(log_P_Conv(1))));" newline ...
"plot(t_h,log_P_Smart,'c','LineWidth',1.5,'DisplayName','SmartSense');" newline ...
"legend('TextColor','w','Color','k'); title('Instantaneous Power (W)','Color','w');" newline ...
"ylabel('Watts','Color','w'); set(ax2,'Color','#0d1117','XColor','w','YColor','w');" newline ...
"ax3=nexttile; hold on; grid on;" newline ...
"area(t_h,E_saved,'FaceColor','#00c853','FaceAlpha',0.3,'DisplayName','Savings (Wh)');" newline ...
"plot(t_h,E_conv, 'r','LineWidth',2,'DisplayName',sprintf('Conventional (%.0fWh)',E_conv(end)));" newline ...
"plot(t_h,E_smart,'c','LineWidth',2,'DisplayName',sprintf('SmartSense (%.0fWh)',E_smart(end)));" newline ...
"legend('TextColor','w','Color','k'); title(sprintf('Cumulative Energy  |  Savings: %.1f Wh (%.0f%%)',E_saved(end),E_saved(end)/E_conv(end)*100),'Color','w');" newline ...
"ylabel('Wh','Color','w'); xlabel('Time (hours)','Color','w');" newline ...
"set(ax3,'Color','#0d1117','XColor','w','YColor','w');" newline ...
"set(gcf,'Color','#0d1117');" newline ...
"end"
];

fid = fopen('SmartSense_PostPlot.m','w');
fprintf(fid, '%s\n', post_plot_code{:});
fclose(fid);

fprintf('\nPost-plot function saved as SmartSense_PostPlot.m\n');
fprintf('After simulation: type  SmartSense_PostPlot()  in Command Window\n\n');
