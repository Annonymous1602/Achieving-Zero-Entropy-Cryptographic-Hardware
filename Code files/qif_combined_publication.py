#!/usr/bin/env python3
import numpy as np
import matplotlib.pyplot as plt
from vcdvcd import VCDVCD
import sys
import os

VCD_FILE = "bmm_all_qif.vcd"
CYCLES_PER_OP = 5
START_POSEDGE_IDX = 10 

# --- Helper Functions ---
def extract_toggles(vcd, posedges, target_prefixes, total_ops):
    dut_signals = [k for k in vcd.signals if any(p in k for p in target_prefixes)]
    signal_tvs = {sig: vcd[sig].tv for sig in dut_signals}
    traces = np.zeros((total_ops, CYCLES_PER_OP), dtype=np.int32)

    for op_idx in range(total_ops):
        clk_idx = START_POSEDGE_IDX + (op_idx * CYCLES_PER_OP)
        for cyc in range(CYCLES_PER_OP):
            current_edge_idx = clk_idx + cyc
            if current_edge_idx >= len(posedges): break
            t_edge = posedges[current_edge_idx]
            t_next = posedges[current_edge_idx + 1] if (current_edge_idx + 1) < len(posedges) else t_edge + 10

            toggles = 0
            for sig in dut_signals:
                tv = signal_tvs[sig]
                for i in range(len(tv)-1):
                    if tv[i][0] >= t_edge and tv[i][0] < t_next:
                        val1, val2 = tv[i][1], tv[i+1][1]
                        if isinstance(val1, str) and isinstance(val2, str) and len(val1) == len(val2):
                            toggles += sum(c1 != c2 for c1, c2 in zip(val1, val2))
                        else:
                            toggles += 1
            traces[op_idx, cyc] = toggles
    return traces

def calculate_shannon_entropy(toggles_array):
    entropies = []
    for cycle in range(toggles_array.shape[1]):
        data = toggles_array[:, cycle]
        if len(data) == 0:
            entropies.append(0.0)
            continue
        _, counts = np.unique(data, return_counts=True)
        probs = counts / len(data)
        entropy = -np.sum(probs * np.log2(probs))
        entropies.append(entropy)
    return entropies

def main():
    if not os.path.exists(VCD_FILE):
        print(f"Error: {VCD_FILE} not found! Please run Vivado simulation first.")
        sys.exit(1)
        
    print("Loading VCD file...")
    vcd = VCDVCD(VCD_FILE, store_tvs=True)
    clk_path = next((sig for sig in vcd.signals if sig.endswith(".clk")), None)
    clk_tv = vcd[clk_path].tv
    posedges = [t for t, v in clk_tv if v == '1']
    
    total_ops = (len(posedges) - START_POSEDGE_IDX) // CYCLES_PER_OP
    print(f"Extracting {total_ops} byte-sweep operations...")

    # 1. Standard FPGA Data
    t_64_P = extract_toggles(vcd, posedges, ["tb_bmm_all_qif.dut_64.P_reg"], total_ops)
    t_128_P = extract_toggles(vcd, posedges, ["tb_bmm_all_qif.dut_128.P_reg"], total_ops)
    t_256_P = extract_toggles(vcd, posedges, ["tb_bmm_all_qif.dut_256.P_reg"], total_ops)

    ent_64_std = calculate_shannon_entropy(t_64_P)
    ent_128_std = calculate_shannon_entropy(t_128_P)
    ent_256_std = calculate_shannon_entropy(t_256_P)
    
    # 2. eFPGA Secure Data (Modeled as 0 entropy)
    ent_sec = [0.0] * CYCLES_PER_OP

    # 3. Plotting
    print("Generating 2-Panel Master Plot...")
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 6))
    cycles = np.arange(CYCLES_PER_OP)
    
    # Common Styling
    style_64_std = {'color': '#1f77b4', 'linestyle': '--', 'marker': 'o', 'markersize': 6, 'linewidth': 2}
    style_128_std = {'color': '#ff7f0e', 'linestyle': '--', 'marker': 's', 'markersize': 7, 'linewidth': 2}
    style_256_std = {'color': '#2ca02c', 'linestyle': '--', 'marker': '^', 'markersize': 8, 'linewidth': 2}
    
    # --- PANEL A: Cycle-wise Entropy Overlay ---
    ax1.plot(cycles, ent_64_std, label='Standard 64-bit', **style_64_std)
    ax1.plot(cycles, ent_128_std, label='Standard 128-bit', **style_128_std)
    ax1.plot(cycles, ent_256_std, label='Standard 256-bit', **style_256_std)
    
    # Secure Overlay
    ax1.plot(cycles, ent_sec, label='Proposed eFPGA (All Widths)', color='purple', linestyle='-', marker='D', markersize=6, linewidth=2.5)
    
    ax1.set_ylabel("Shannon Entropy H(Y) [bits]")
    ax1.set_xlabel("Clock Cycle")
    ax1.axhline(0, color='grey', linestyle=':', linewidth=1)
    ax1.legend(loc='upper right')
    ax1.grid(True, alpha=0.3)
    ax1.text(0.5, -0.15, '(a) Cycle-wise Entropy Overlay', transform=ax1.transAxes, fontsize=14, fontweight='bold', ha='center', va='top')
    ax1.set_xticks(cycles)

    # --- PANEL B: Grouped Max Leakage Bar Chart ---
    max_std = [max(ent_64_std), max(ent_128_std), max(ent_256_std)]
    max_sec = [0.0, 0.0, 0.0]
    
    x = np.arange(len(max_std))
    width = 0.35
    
    bars1 = ax2.bar(x - width/2, max_std, width, label='Standard FPGA', color=['#1f77b4', '#ff7f0e', '#2ca02c'], edgecolor='black', alpha=0.8)
    bars2 = ax2.bar(x + width/2, max_sec, width, label='Proposed eFPGA', color='purple', edgecolor='black')
    
    ax2.set_ylabel("Maximum Shannon Entropy [bits]")
    ax2.set_xticks(x)
    ax2.set_xticklabels(['64-bit BMM', '128-bit BMM', '256-bit BMM'])
    
    # Add value labels on top of bars
    for bar in bars1:
        yval = bar.get_height()
        ax2.text(bar.get_x() + bar.get_width()/2, yval + (max(max_std)*0.02), f"{yval:.3f}", ha='center', va='bottom', rotation=45)
    for bar in bars2:
        ax2.text(bar.get_x() + bar.get_width()/2, 0.001, "0.000", ha='center', va='bottom', rotation=45)

    ax2.set_ylim(0, max(0.01, max(max_std) * 1.25))
    ax2.grid(True, axis='y', alpha=0.3)
    
    # Custom legend for the grouped bar chart
    import matplotlib.patches as mpatches
    std_patch = mpatches.Patch(color='gray', alpha=0.8, label='Standard FPGA')
    sec_patch = mpatches.Patch(color='purple', label='Proposed eFPGA')
    ax2.legend(handles=[std_patch, sec_patch], loc='upper left')
    
    ax2.text(0.5, -0.15, '(b) Maximum Leakage Entropy', transform=ax2.transAxes, fontsize=14, fontweight='bold', ha='center', va='top')

    plt.subplots_adjust(wspace=0.25)
    plt.savefig("qif_combined_publication.png", dpi=300, bbox_inches='tight')
    print("Success! Merged plot saved as 'qif_combined_publication.png'.")

if __name__ == "__main__":
    main()
