import os
import re
import time
import csv
import shutil
from datetime import datetime
import numpy as np
from multiprocessing.pool import ThreadPool
from jinja2 import Environment, FileSystemLoader

from pymoo.algorithms.moo.nsga2 import NSGA2
from pymoo.optimize import minimize
from pymoo.core.problem import Problem
from pymoo.operators.crossover.pntx import PointCrossover
from pymoo.operators.sampling.rnd import IntegerRandomSampling
from pymoo.termination import get_termination
from pymoo.core.mutation import Mutation
from pymoo.core.repair import Repair
import threading

# -----------------------------------------------------------------------------
# BOOTH-only auto-aspect-ratio NSGA flow for reconfig_bmm_64.
# The XML must contain only the BOOTH hard block. ADDER and BRAM are not evolved
# and are not emitted in the layout; add/sub logic maps to LUT/CLB fabric.
# -----------------------------------------------------------------------------
VTR_PATH = '/home/ihs12/chandan/vtr-verilog-to-routing/'
BENCHMARK = os.environ.get('BENCHMARK', 'reconfig_bmm_256')
TASK = BENCHMARK
LAYOUT = 20
ROOT_DIR = os.path.abspath(os.getcwd())
PROJECT_DIR = os.path.join(ROOT_DIR, 'project')
FRAMEWORK_PATH = PROJECT_DIR + os.sep
RESOURCE_BLOCK = os.path.join('project', 'resourceBlocks')
EVOLUTION_PATH = os.path.join('architectureEvolution', BENCHMARK)
TEMPLATE_FILE = os.environ.get('TEMPLATE_FILE', 'customFPGATemplate_bmm64_128_256.xml')

# Only BOOTH is a hard block now.
BLOCKS = ['BOOTH']
DEFAULT_FALLBACK_BOOTH = int(os.environ.get('DEFAULT_FALLBACK_BOOTH', '81'))
AUTO_SAFE_BOOTH_SITE_COUNT = int(os.environ.get('AUTO_SAFE_BOOTH_SITE_COUNT', '256'))
BLOCK_HEIGHT = 4
BLOCKS_COUNT = {}
MAX_BLOCKS_COUNT = {}
RESOURCE_USAGE_CACHE = {}

OVERLAP_LIMIT_Y = 4
OVERLAP_LIMIT_X = 1
PRIORITY_H_BLOCKS = 20
PRIORITY_CLBS = 10
GENERATIONS = int(os.environ.get('GENERATIONS', '10'))
POP_SIZE = int(os.environ.get('POP_SIZE', '30'))
PARALLEL_WORKERS = int(os.environ.get('PARALLEL_WORKERS', '30'))
GEN = 0
CURRENT_GEN = 0
_eval_lock = threading.Lock()
pool = ThreadPool(PARALLEL_WORKERS)

CLB_TYPES = {
    0: 'CLB_LUT4',
    1: 'CLB_LUT5',
    2: 'CLB_LUT6',
    3: 'CLB_LUT7',
    4: 'CLB_LUT8',
    5: 'CLB_HYBRID_4_5_6_7_8',
}
NUM_CLB_TYPES = len(CLB_TYPES)

for d in [
    f'project/metrics/{BENCHMARK}',
    f'project/architectureEvolution/{BENCHMARK}',
    f'project/architecture/{BENCHMARK}',
    'project/fitness',
    f'project/best_configurations/{BENCHMARK}',
    f'project/individual_metrics/{BENCHMARK}',
    'project/template',
    'project/resourceBlocks',
]:
    os.makedirs(d, exist_ok=True)

class ProgressTracker:
    def __init__(self, benchmark):
        self.benchmark = benchmark
        self.total_evaluated = 0
        self.total_vtr_ran = 0
        self.total_vtr_failed = 0
        self.total_above_target = 0
        self.total_feasible = 0
        self.gen_log = []
        self._cgs = {}
        self.summary_path = f'project/individual_metrics/{benchmark}/progress_summary.txt'
        with open(self.summary_path, 'w') as f:
            f.write(f'FPGA Evolution Progress Log - {benchmark}\n')
            f.write('=' * 72 + '\n\n')

    def start_generation(self, gen_number, pop_size):
        self._cgs = dict(generation=gen_number, pop_size=pop_size, vtr_ran=0,
                         vtr_failed=0, above_target=0, feasible=0,
                         best_delay=float('inf'), best_power=float('inf'))

    def record_vtr_result(self, vpr_ok, within_target, delay, power):
        self._cgs['vtr_ran'] += 1
        self.total_vtr_ran += 1
        self.total_evaluated += 1
        if not vpr_ok:
            self._cgs['vtr_failed'] += 1
            self.total_vtr_failed += 1
        elif not within_target:
            self._cgs['above_target'] += 1
            self.total_above_target += 1
        else:
            self._cgs['feasible'] += 1
            self.total_feasible += 1
            self._cgs['best_delay'] = min(self._cgs['best_delay'], delay)
            self._cgs['best_power'] = min(self._cgs['best_power'], power)

    def finish_generation(self):
        s = self._cgs
        self.gen_log.append(dict(s))
        vtr = max(s['vtr_ran'], 1)
        best_d = f"{s['best_delay']:.4f}" if s['best_delay'] != float('inf') else '-'
        best_p = f"{s['best_power']:.6f}" if s['best_power'] != float('inf') else '-'
        summary = (
            f"\n{'-'*72}\n"
            f"  Generation          : {s['generation']}\n"
            f"  Population size     : {s['pop_size']}\n"
            f"  VTR runs total      : {s['vtr_ran']:>4}\n"
            f"  VPR failed          : {s['vtr_failed']:>4} ({100*s['vtr_failed']/vtr:.1f}%)\n"
            f"  Feasible            : {s['feasible']:>4} ({100*s['feasible']/vtr:.1f}%)\n"
            f"  Best this gen       : delay={best_d} ns, power={best_p} W\n"
            f"{'-'*72}\n"
            f"  CUMULATIVE          : evaluated={self.total_evaluated}, vtr_ran={self.total_vtr_ran}, "
            f"vtr_failed={self.total_vtr_failed}, feasible={self.total_feasible}\n"
        )
        print(summary)
        with open(self.summary_path, 'a') as f:
            f.write(summary)

    def write_final_report(self):
        total = max(self.total_evaluated, 1)
        report = (
            f"\n{'='*72}\n"
            f"  FINAL SUMMARY\n"
            f"  Total VTR runs  : {self.total_vtr_ran}\n"
            f"  VPR failures    : {self.total_vtr_failed}\n"
            f"  Above target    : {self.total_above_target}\n"
            f"  Feasible        : {self.total_feasible} ({100*self.total_feasible/total:.1f}%)\n"
            f"{'='*72}\n"
        )
        print(report)
        with open(self.summary_path, 'a') as f:
            f.write(report)

VPR_OUT_METRICS = [
    'io_blocks', 'clb_blocks', 'booth_blocks',
    'lut_count', 'ff_count', 'post_packed_blocks', 'post_packed_nets',
    'device_grid_tiles',
]
PARSE_METRICS = [
    'critical_path_delay', 'total_power',
    'routing_power_perc', 'clock_power_perc', 'tile_power_perc',
    'routed_wirelength', 'min_chan_width',
    'logic_block_area_used', 'min_chan_width_routing_area_total',
]
ALL_METRICS = VPR_OUT_METRICS + PARSE_METRICS

def metric_count(value, default=0):
    if value in (None, '', 'N/A', '-1'):
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        try:
            return int(float(value))
        except (TypeError, ValueError):
            return default

def parse_vpr_out(vpr_out_path):
    result = {k: 'N/A' for k in VPR_OUT_METRICS}
    if not os.path.exists(vpr_out_path):
        return result
    with open(vpr_out_path, 'r', encoding='utf-8', errors='replace') as f:
        text = f.read()
    for line in text.splitlines():
        line_s = line.strip()
        m = re.match(r'IO\s+implemented as IO\s*:\s*(\d+)', line_s)
        if m:
            result['io_blocks'] = m.group(1)
        m = re.match(r'(CLB\S*)\s+implemented as \1\s*:\s*(\d+)', line_s)
        if m:
            prev = 0 if result['clb_blocks'] == 'N/A' else int(result['clb_blocks'])
            result['clb_blocks'] = str(prev + int(m.group(2)))
        m = re.match(r'BOOTH\s+implemented as BOOTH\s*:\s*(\d+)', line_s)
        if m:
            result['booth_blocks'] = m.group(1)
        m = re.match(r'booth\s*:\s*(\d+)', line_s)
        if m and result.get('booth_blocks') in ('N/A', None, ''):
            result['booth_blocks'] = m.group(1)
        m = re.match(r'Total number of Logic Elements used\s*:\s*(\d+)', line_s)
        if m:
            result['lut_count'] = m.group(1)
            result['ff_count'] = m.group(1)
        m = re.match(r'Netlist num_blocks\s*:\s*(\d+)', line_s)
        if m:
            result['post_packed_blocks'] = m.group(1)
        m = re.match(r'Netlist num_nets\s*:\s*(\d+)', line_s)
        if m:
            result['post_packed_nets'] = m.group(1)
        m = re.match(r'FPGA sized to \d+ x \d+:\s*(\d+)\s+grid tiles', line_s)
        if m:
            result['device_grid_tiles'] = m.group(1)
    return result

def parse_results_txt(result_path):
    extracted = {m: 'N/A' for m in PARSE_METRICS}
    try:
        with open(result_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        if len(lines) < 2:
            return extracted
        headings = lines[0].strip().split('\t')
        values = lines[-1].strip().split('\t')
        for idx, h in enumerate(headings):
            if h.strip() in PARSE_METRICS and idx < len(values):
                extracted[h.strip()] = values[idx].strip()
    except Exception as e:
        print(f'  [parse_results_txt] error: {e}')
    return extracted

def read_resource_block_limits(resource_dir, benchmark):
    path = os.path.join(resource_dir, benchmark + '.txt')
    counts = {'BOOTH': 0}
    if not os.path.exists(path):
        print(f'[WARN] Resource file not found: {path}. Using DEFAULT_FALLBACK_BOOTH={DEFAULT_FALLBACK_BOOTH}.')
        return {'BOOTH': DEFAULT_FALLBACK_BOOTH}
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            if re.match(r'\s*BOOTH\b', line):
                m = re.search(r'\d+', line)
                if m:
                    counts['BOOTH'] = int(m.group())
    if counts['BOOTH'] <= 0:
        print('[WARN] BOOTH count is 0. No BOOTH locations will be emitted unless profiling can parse a count.')
    return counts

def build_allowed_locations(layout):
    """Return BOOTH placement sites that are safe for VPR auto_layout.

    For bmm_128 the design uses 27 booth cells. The earlier bmm_64-only
    pool had only 12 locations and used y=10/19, which became illegal when
    VPR auto-layout initially had vertical range [0,9]. This pool keeps all
    BOOTH sites on y=1 and gives a long x row, so BOOTH 9, 27, 30, etc. can
    be emitted without y-range failures.
    """
    n_sites = max(AUTO_SAFE_BOOTH_SITE_COUNT, 1)
    return [[x, 1] for x in range(1, n_sites + 1)]

def hard_block_conflicts(coord_a, coord_b):
    xa, ya = coord_a
    xb, yb = coord_b
    if xa == xb and ya == yb:
        return True
    if xa == xb and abs(ya - yb) < (OVERLAP_LIMIT_Y + BLOCK_HEIGHT):
        return True
    if ya == yb and abs(xa - xb) < OVERLAP_LIMIT_X:
        return True
    return False

def pick_non_overlapping_sites(count, allowed_locations):
    selected = []
    for loc in allowed_locations:
        if all(not hard_block_conflicts(loc, other) for other in selected):
            selected.append(loc)
            if len(selected) == count:
                break
    if len(selected) < count:
        print(f'[WARN] Requested {count} BOOTH sites but only {len(selected)} fit.')
    return selected

def render_architecture_xml(xml_path, aspect_ratio, clb_name, booths):
    env = Environment(loader=FileSystemLoader('project/template/'))
    template = env.get_template(TEMPLATE_FILE)
    content = template.render(
        aspectRatio=aspect_ratio,
        clbPriority=PRIORITY_CLBS,
        clbName=clb_name,
        BOOTHS=booths,
        ADDERS=[],
        BRAMS=[],
    )
    with open(xml_path, 'w', encoding='utf-8') as f:
        f.write(content)

def write_vtr_task_config(task_name, xml_filename):
    task_dir = os.path.join(VTR_PATH, 'vtr_flow', 'tasks', 'power', task_name)
    os.makedirs(os.path.join(task_dir, 'config'), exist_ok=True)
    configuration = (
        'script_params=-power \n'
        'cmos_tech_behavior=PTM_45nm/45nm.xml\n'
        'circuits_dir=benchmarks/verilog/\n'
        f'archs_dir={FRAMEWORK_PATH}architectureEvolution/{BENCHMARK}/\n'
        f'circuit_list_add={BENCHMARK}.v\n'
        f'arch_list_add={xml_filename}\n'
        'sdc_dir=sdc\n'
        'parse_file=vpr_power.txt\n'
        'pass_requirements_file=pass_requirements_power.txt\n'
        'qor_parse_file=qor_standard.txt\n'
        'script_params_common = -track_memory_usage --device auto\n'
        'script_params_list_add = --RL_agent_placement off \n'
    )
    with open(os.path.join(task_dir, 'config', 'config.txt'), 'w', encoding='utf-8') as f:
        f.write(configuration)
    return task_dir

def run_vtr_task(task_name):
    return os.system(VTR_PATH + f'vtr_flow/scripts/run_vtr_task.py power/{task_name}')

def parse_task_outputs(task_dir):
    delay = 100.0
    power = 10.0
    metrics = {m: 'N/A' for m in ALL_METRICS}
    if not os.path.exists(task_dir):
        return delay, power, metrics
    folders = [d for d in os.listdir(task_dir) if os.path.isdir(os.path.join(task_dir, d))]
    run_nums = [int(f[3:]) for f in folders if f.startswith('run') and f[3:].isdigit()]
    if not run_nums:
        return delay, power, metrics
    run_dir = os.path.join(task_dir, f'run{max(run_nums):03d}')
    result_path = os.path.join(run_dir, 'parse_results.txt')
    vpr_out_path = None
    for root, dirs, files in os.walk(run_dir):
        if 'vpr.out' in files:
            vpr_out_path = os.path.join(root, 'vpr.out')
            break
    if vpr_out_path:
        metrics.update(parse_vpr_out(vpr_out_path))
    else:
        print(f'  [WARN] vpr.out not found under {run_dir}')
    if os.path.exists(result_path) and os.path.getsize(result_path) > 0:
        pr = parse_results_txt(result_path)
        metrics.update(pr)
        if pr.get('critical_path_delay') not in ('N/A', '-1', '', None):
            delay = float(pr['critical_path_delay'])
        if pr.get('total_power') not in ('N/A', '-1', '', None):
            power = float(pr['total_power'])
    return delay, power, metrics

def build_booth_list(ind_data, booth_count):
    """Build BOOTH singles from evolved genes and repair duplicates/conflicts."""
    allowed = build_allowed_locations(LAYOUT)
    selected = []
    for i in range(1, 1 + booth_count):
        if i < len(ind_data) and isinstance(ind_data[i], (list, tuple)):
            cand = [int(ind_data[i][0]), int(ind_data[i][1])]
        else:
            cand = allowed[(i - 1) % len(allowed)]
        if all(not hard_block_conflicts(cand, other) for other in selected):
            selected.append(cand)
            continue
        replacement = None
        for loc in allowed:
            if all(not hard_block_conflicts(loc, other) for other in selected):
                replacement = loc
                break
        if replacement is None:
            raise RuntimeError(f'Cannot place {booth_count} BOOTH blocks; increase AUTO_SAFE_BOOTH_SITE_COUNT.')
        selected.append(replacement)
    return [[int(x), int(y), PRIORITY_H_BLOCKS] for x, y in selected]

def profile_required_hard_blocks():
    """Use resource file as an upper bound, then profile exact BOOTH usage.

    If reconfig_bmm_128.txt says BOOTH 30, this emits 30 legal BOOTH sites,
    runs the profile task, and parses the actual booth count. The uploaded
    bmm_128 design reports 27 booth cells, so NSGA continues with 27 sites.
    """
    upper = read_resource_block_limits(RESOURCE_BLOCK, BENCHMARK)
    upper_count = max(0, int(upper.get('BOOTH', 0)))

    allowed = build_allowed_locations(LAYOUT)
    if upper_count > len(allowed):
        print(f'[WARN] Resource file asks for BOOTH {upper_count}, but placement pool has only {len(allowed)} sites. Increase AUTO_SAFE_BOOTH_SITE_COUNT.')
    profile_site_count = min(upper_count, len(allowed))

    booths = [[x, y, PRIORITY_H_BLOCKS] for x, y in pick_non_overlapping_sites(profile_site_count, allowed)]

    xml_filename = f'{BENCHMARK}ProfileRequirements.xml'
    xml_path = os.path.join('project', 'architectureEvolution', BENCHMARK, xml_filename)
    render_architecture_xml(xml_path, 0.1, 'CLB_LUT6', booths)

    task_name = f'{TASK}_resource_profile'
    task_dir = write_vtr_task_config(task_name, xml_filename)
    status = run_vtr_task(task_name)

    # Parse even when VPR returns non-zero; vpr.out often still contains booth usage.
    delay, power, metrics = parse_task_outputs(task_dir)
    parsed = metric_count(metrics.get('booth_blocks'), 0)

    if parsed > 0:
        required_count = min(upper_count, parsed) if upper_count > 0 else parsed
    else:
        if DEFAULT_FALLBACK_BOOTH > 0:
            required_count = min(upper_count, DEFAULT_FALLBACK_BOOTH) if upper_count > 0 else DEFAULT_FALLBACK_BOOTH
        else:
            required_count = upper_count
        print(f'[WARN] Could not parse BOOTH usage from profiling output. Using BOOTH {required_count}.')

    if status != 0:
        print('[WARN] Resource profiling VPR returned non-zero, but parsed BOOTH usage will still be used if available.')
    if upper_count > 0 and required_count < upper_count:
        print(f'[INFO] Resource file BOOTH {upper_count} is only an upper bound; profiled design requires BOOTH {required_count}.')
    if parsed > upper_count > 0:
        print(f'[WARN] Design appears to require BOOTH {parsed}, but resource upper bound is BOOTH {upper_count}. Using {upper_count}.')

    required = {'BOOTH': required_count}
    print(f'Upper-bound hard blocks from resource file: {upper}')
    print(f'Profiled required hard blocks for current design: {required}')
    return upper, required

class MetricsLogger:
    def __init__(self, benchmark):
        self.benchmark = benchmark
        self.csv_path = f'project/individual_metrics/{benchmark}/all_individuals.csv'
        self.best_dir = f'project/best_configurations/{benchmark}/'
        self.best_pareto = []
        with open(self.csv_path, 'w', newline='') as f:
            csv.writer(f).writerow(['individual_id', 'generation'] + ALL_METRICS +
                                   ['delay_norm', 'power_norm', 'combined_fitness',
                                    'constraint_violation', 'status', 'aspect_ratio', 'clb_type_used'])

    def log(self, individual_id, generation, metrics, delay, power, delay_norm,
            power_norm, fitness, violation, status, aspect_ratio=0.0, clb_type='N/A'):
        row = [individual_id, generation] + [metrics.get(m, 'N/A') for m in ALL_METRICS] + \
              [f'{delay_norm:.6f}', f'{power_norm:.6f}', f'{fitness:.6f}', violation,
               status, f'{aspect_ratio:.3f}', clb_type]
        with open(self.csv_path, 'a', newline='') as f:
            csv.writer(f).writerow(row)

    def update_best_pareto(self, individual_id, delay, power, arch_xml_path, metrics,
                           aspect_ratio=0.0, clb_type='N/A'):
        entry = dict(id=individual_id, delay=delay, power=power, xml=arch_xml_path,
                     metrics=metrics, aspect_ratio=aspect_ratio, clb_type=clb_type)
        dominated = False
        remove = []
        for e in self.best_pareto:
            if e['delay'] <= delay and e['power'] <= power:
                dominated = True
                break
            if delay <= e['delay'] and power <= e['power']:
                remove.append(e)
        if dominated:
            return
        for e in remove:
            self.best_pareto.remove(e)
        self.best_pareto.append(entry)
        dest = os.path.join(self.best_dir, f'pareto_ind{individual_id}_d{delay:.4f}_p{power:.6f}.xml')
        if os.path.exists(arch_xml_path):
            shutil.copy2(arch_xml_path, dest)

    def write_pareto_summary(self):
        path = os.path.join(self.best_dir, 'pareto_front_summary.txt')
        with open(path, 'w') as f:
            f.write('Pareto-front solutions, sorted by delay\n')
            f.write('=' * 90 + '\n\n')
            for rank, e in enumerate(sorted(self.best_pareto, key=lambda x: x['delay']), 1):
                m = e.get('metrics', {})
                f.write(f"Rank                       : {rank}\n")
                f.write(f"Individual ID              : {e['id']}\n")
                f.write(f"Critical Delay (ns)        : {e['delay']:.6f}\n")
                f.write(f"Total Power (W)            : {e['power']:.6f}\n")
                f.write(f"BOOTHs                     : {m.get('booth_blocks', 'N/A')}\n")
                f.write(f"LUTs                       : {m.get('lut_count', 'N/A')}\n")
                f.write(f"CLBs                       : {m.get('clb_blocks', 'N/A')}\n")
                f.write(f"CLB Type                   : {e.get('clb_type', 'N/A')}\n")
                f.write(f"Aspect Ratio               : {e.get('aspect_ratio', 'N/A')}\n")
                f.write(f"Device grid tiles          : {m.get('device_grid_tiles', 'N/A')}\n")
                f.write('-' * 90 + '\n')
        print(f'\n[MetricsLogger] Pareto summary -> {path}')
        print(f'[MetricsLogger] Pareto-front solutions: {len(self.best_pareto)}')

def write_clb_usage_report(generation, pop_clb_info, report_path):
    sep = '-' * 80
    rows = [f"\n{sep}\n  CLB USAGE REPORT - Generation {generation}\n{sep}\n"]
    rows.append(f"  {'Ind':>6}  {'AspRatio':>9}  {'CLB Type':>8}  {'CLB Name':>24}  {'Delay (ns)':>11}  {'Power (W)':>11}  Status\n")
    counter = {}
    for info in pop_clb_info:
        name = info['clb_name']
        counter[name] = counter.get(name, 0) + 1
        delay_s = f"{info['delay']:.4f}" if info['delay'] < 99 else 'FAILED'
        power_s = f"{info['power']:.6f}" if info['power'] < 9.9 else 'FAILED'
        rows.append(f"  {info['ind_id']:>6}  {info['aspect_ratio']:>9.3f}  {info['clb_type']:>8}  {name:>24}  {delay_s:>11}  {power_s:>11}  {info['status']}\n")
    rows.append('\n  CLB-type distribution this generation:\n')
    for cname in sorted(counter):
        rows.append(f'    {cname}: {counter[cname]} individual(s)\n')
    rows.append(sep + '\n')
    with open(report_path, 'a') as f:
        f.writelines(rows)
    print(''.join(rows))

_tracker = None
_mlogger = None
_clb_report_path = None

class IntegerMutation(Mutation):
    def __init__(self, prob_var=0.15):
        super().__init__()
        self.prob_var = prob_var
    def _do(self, problem, X, **kwargs):
        X = X.copy().astype(float)
        for i in range(X.shape[0]):
            for j in range(X.shape[1]):
                if np.random.random() < self.prob_var:
                    X[i, j] = float(np.random.randint(int(problem.xl[j]), int(problem.xu[j]) + 1))
        return np.round(X).astype(int)

class OverlapRepair(Repair):
    MAX_ATTEMPTS = 200
    def __init__(self, allowed_locs, variables, overlap_y, overlap_x):
        super().__init__()
        self.allowed_locs = allowed_locs
        self.variables = variables
        self.overlap_y = overlap_y
        self.overlap_x = overlap_x
        self.n_locs = len(allowed_locs)
    def _conflicts(self, idx_a, idx_b):
        return hard_block_conflicts(self.allowed_locs[idx_a], self.allowed_locs[idx_b])
    def _repair_individual(self, x):
        x = x.copy()
        n_blocks = self.variables - 1
        for i in range(1, n_blocks + 1):
            for j in range(i + 1, n_blocks + 1):
                if not self._conflicts(int(x[i]), int(x[j])):
                    continue
                fixed = [int(x[k]) for k in range(1, n_blocks + 1) if k != j]
                for _ in range(self.MAX_ATTEMPTS):
                    c = np.random.randint(0, self.n_locs)
                    if all(not self._conflicts(c, f) for f in fixed):
                        x[j] = c
                        break
        return x
    def _do(self, problem, X, **kwargs):
        X = np.round(X).astype(int)
        for i in range(X.shape[0]):
            X[i] = self._repair_individual(X[i])
        return X

class MyCallback:
    def __init__(self):
        self.data = []
    def __call__(self, algorithm):
        self.data.append(algorithm.pop.get('F'))

class FPGA_Architecture(Problem):
    def __init__(self, **kwargs):
        self.CLB = CLB_TYPES.copy()
        self.determine_variables()
        self.determine_valid_locations()
        self.limit_values()
        super().__init__(n_var=self.variables + 1, n_obj=2, n_ieq_constr=1,
                         n_constr=0, elementwise_evaluation=False,
                         xl=self.xl, xu=self.xu, vtype=int, **kwargs)

    def determine_variables(self):
        self.variables = 1 + BLOCKS_COUNT.get('BOOTH', 0)
        print('Active hard blocks after profiling: ' + str(BLOCKS_COUNT))
        print('variables: ' + str(self.variables))

    def determine_valid_locations(self):
        self.allowedLocations = build_allowed_locations(LAYOUT)
        self.xl = np.array([1] + [0] * (self.variables - 1) + [0])
        self.xu = np.array([10] + [len(self.allowedLocations) - 1] * (self.variables - 1) + [NUM_CLB_TYPES - 1])

    def limit_values(self):
        self.delay = 420.0
        self.power = 3.0
        self.fitness = 2 ** 0.5

    def checkValidity(self, x):
        x = np.array(x, dtype=float)
        x[0] = max(1, min(10, abs(int(round(x[0])))))
        for i in range(1, self.variables):
            x[i] = max(self.xl[i], min(self.xu[i], int(round(x[i]))))
        x[self.variables] = max(0, min(NUM_CLB_TYPES - 1, int(round(x[self.variables]))))
        return x.astype(int)

    def convertCoordinates(self, x):
        converted = [int(x[0])]
        for i in range(1, self.variables):
            loc_idx = max(0, min(int(x[i]), len(self.allowedLocations) - 1))
            converted.append([int(self.allowedLocations[loc_idx][0]), int(self.allowedLocations[loc_idx][1])])
        converted.append(int(x[self.variables]))
        return converted

    def checkOverlapViolation(self, block_coords):
        violations = 0
        for i in range(len(block_coords)):
            for j in range(i + 1, len(block_coords)):
                if hard_block_conflicts(block_coords[i], block_coords[j]):
                    violations += 1
        return violations

    def evaluateArchitecture(self, x_raw, Z):
        global _tracker, _mlogger, CURRENT_GEN, RESOURCE_USAGE_CACHE
        print(f'--- Starting VTR Evaluation for Individual {Z} ---')
        x_valid = self.checkValidity(x_raw)
        x = self.convertCoordinates(x_valid)
        aspect_ratio = x[0] / 10.0
        booth_coords = x[1:self.variables]
        clb_type_idx = x[self.variables]
        clb_name = self.CLB.get(clb_type_idx, 'CLB_LUT4')
        overlap = self.checkOverlapViolation(booth_coords)
        if overlap > 0:
            print(f'  [REPAIR] Residual overlap ({overlap}) for individual {Z}; repairing BOOTH coordinates instead of discarding')
        BOOTHS = build_booth_list(x, BLOCKS_COUNT.get('BOOTH', 0))
        xml_filename = f'{BENCHMARK}Architecture_{Z}.xml'
        xml_path = f'project/architectureEvolution/{BENCHMARK}/{xml_filename}'
        current_task = f'{TASK}_{Z}'
        task_dir = write_vtr_task_config(current_task, xml_filename)
        render_architecture_xml(xml_path, aspect_ratio, clb_name, BOOTHS)
        status = run_vtr_task(current_task)
        if status != 0:
            delay, power, metrics = 100.0, 10.0, {m: 'N/A' for m in ALL_METRICS}
        else:
            delay, power, metrics = parse_task_outputs(task_dir)
        vpr_ok = (delay > 0) and (power > 0) and not (delay == 100.0 and power == 10.0)
        print(f'  Individual {Z} -> Delay: {delay:.4f} ns  Power: {power:.6f} W  '
              f'AspectRatio: {aspect_ratio:.3f}  CLBType: {clb_name}  '
              f'CLBs: {metrics.get("clb_blocks", "?")}  '
              f'BOOTHs used/declared: {metrics.get("booth_blocks", "?")}/{len(BOOTHS)}  '
              f'LUTs: {metrics.get("lut_count", "?")}  VPR_ok: {vpr_ok}')
        delay_norm = delay / self.delay if vpr_ok else 100.0 / self.delay
        power_norm = power / self.power if vpr_ok else 10.0 / self.power
        fitness_val = (delay_norm ** 2 + power_norm ** 2) ** 0.5
        violation = float((1 if (not vpr_ok or delay > self.delay) else 0) +
                          (1 if (not vpr_ok or power > self.power) else 0) +
                          (1 if fitness_val > self.fitness else 0))
        within_target = violation == 0
        status_str = 'feasible' if within_target else ('vpr_failed' if not vpr_ok else 'above_target')
        with _eval_lock:
            RESOURCE_USAGE_CACHE[tuple(x_valid.tolist())] = {'BOOTH': len(BOOTHS)}
            if _tracker:
                _tracker.record_vtr_result(vpr_ok, within_target, delay, power)
            if _mlogger:
                _mlogger.log(Z, CURRENT_GEN, metrics, delay, power, delay_norm, power_norm,
                             fitness_val, violation, status_str, aspect_ratio, clb_name)
                if within_target:
                    _mlogger.update_best_pareto(Z, delay, power, xml_path, metrics, aspect_ratio, clb_name)
        clb_info = dict(ind_id=Z, aspect_ratio=aspect_ratio, clb_type=clb_type_idx,
                        clb_name=clb_name, delay=delay, power=power, status=status_str)
        return [delay_norm, power_norm], [violation], clb_info

    def _evaluate(self, X, out, *args, **kwargs):
        global GEN, CURRENT_GEN, _tracker, _clb_report_path
        CURRENT_GEN = GEN
        os.makedirs(f'project/{EVOLUTION_PATH}', exist_ok=True)
        with open(f'project/{EVOLUTION_PATH}/generation.txt', 'w') as gf:
            gf.write(str(CURRENT_GEN))
        print(f"\n{'='*60}\n  GENERATION {CURRENT_GEN}  |  Population: {len(X)}\n{'='*60}")
        if _tracker:
            _tracker.start_generation(CURRENT_GEN, len(X))
        X_int = np.round(X).astype(int)
        for i in range(len(X_int)):
            print(f'  Ind {i}: genes[:10]={X_int[i][:10].tolist()} ...')
        params = [(X_int[k], CURRENT_GEN * 1000 + k) for k in range(len(X_int))]
        result = list(pool.starmap(self.evaluateArchitecture, params))
        out['F'] = np.array([r[0] for r in result])
        out['G'] = np.array([r[1] for r in result])
        if _clb_report_path:
            write_clb_usage_report(CURRENT_GEN, [r[2] for r in result], _clb_report_path)
        if _tracker:
            _tracker.finish_generation()
        GEN += 1

def runFramework():
    global _tracker, _mlogger, _clb_report_path
    _tracker = ProgressTracker(BENCHMARK)
    _mlogger = MetricsLogger(BENCHMARK)
    _clb_report_path = f'project/individual_metrics/{BENCHMARK}/clb_usage_per_generation.txt'
    with open(_clb_report_path, 'w') as f:
        f.write(f'CLB Usage Report - {BENCHMARK}\n' + '=' * 80 + '\n')
    RESOURCE_USAGE_CACHE.clear()
    upper, required = profile_required_hard_blocks()
    MAX_BLOCKS_COUNT.clear(); MAX_BLOCKS_COUNT.update(upper)
    BLOCKS_COUNT.clear(); BLOCKS_COUNT.update(required)
    problem = FPGA_Architecture()
    callback = MyCallback()
    repair = OverlapRepair(problem.allowedLocations, problem.variables, OVERLAP_LIMIT_Y, OVERLAP_LIMIT_X)
    algorithm = NSGA2(pop_size=POP_SIZE, sampling=IntegerRandomSampling(),
                      crossover=PointCrossover(n_points=2),
                      mutation=IntegerMutation(prob_var=0.20), repair=repair)
    res = minimize(problem, algorithm, get_termination('n_gen', GENERATIONS),
                   save_history=False, callback=callback, verbose=True)
    pool.close()
    _tracker.write_final_report()
    _mlogger.write_pareto_summary()
    print('\n===== FINAL SOLUTIONS =====')
    if res.F is not None:
        print('F (objectives):', res.F)
    if res.X is None:
        print('No feasible solution found.')
        if res.pop is not None:
            print(f'Final population size: {len(res.pop)}')
            print('Best CV values:', res.pop.get('CV').min(axis=0))
        return
    np.save(f'project/fitness/fitness_{BENCHMARK}.npy', np.array(callback.data, dtype=object))
    final_gen = max(GEN - 1, 0)
    for j, sol in enumerate(res.X.astype(int)):
        validated = problem.checkValidity(sol)
        ind_data = problem.convertCoordinates(validated)
        aspect_ratio = float(ind_data[0]) / 10.0
        clb_type_idx = ind_data[problem.variables]
        clb_name = problem.CLB.get(clb_type_idx, 'CLB_LUT4')
        usage = RESOURCE_USAGE_CACHE.get(tuple(validated.tolist()), {'BOOTH': BLOCKS_COUNT.get('BOOTH', 0)})
        BOOTHS = build_booth_list(ind_data, usage.get('BOOTH', BLOCKS_COUNT.get('BOOTH', 0)))
        env = Environment(loader=FileSystemLoader('project/template/'))
        template = env.get_template(TEMPLATE_FILE)
        content = template.render(aspectRatio=aspect_ratio, clbName=clb_name,
                                  BOOTHS=BOOTHS, ADDERS=[], BRAMS=[], clbPriority=PRIORITY_CLBS)
        file_name = f'{BENCHMARK}Arch_Gen{final_gen}_Ind{j}.xml'
        arch_path = f'project/architecture/{BENCHMARK}/{file_name}'
        with open(arch_path, 'w', encoding='utf-8') as af:
            af.write(content)
        best_copy = f'project/best_configurations/{BENCHMARK}/final_sol_Gen{final_gen}_Ind{j}.xml'
        shutil.copy2(arch_path, best_copy)
        print(f'Saved: {file_name} (CLB type: {clb_name}, aspect ratio: {aspect_ratio:.3f}, BOOTH={len(BOOTHS)})')

if __name__ == '__main__':
    start_time = time.time()
    start = datetime.now()
    print('=== Starting FPGA Evolution Framework ===')
    runFramework()
    elapsed = time.time() - start_time
    end = datetime.now()
    print('=== Finished FPGA Evolution Framework ===')
    print(f'Total runtime: {elapsed:.2f} seconds')
    print('Started at:', start)
    print('Ended at:', end)
    print('Elapsed:', end - start)

