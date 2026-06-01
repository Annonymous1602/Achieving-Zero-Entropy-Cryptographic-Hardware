# Achieving Zero-Entropy Cryptographic Hardware: Defeating Power Side-Channels via Dynamic eFPGA Morphing

As cryptographic protocols increasingly rely on
wide-operand modular arithmetic, hardware accelerators such
as the Barrett Modular Multiplier (BMM) have become critical.
However, deploying these highly active, reusable architectures
on standard FPGAs exposes severe side-channel vulnerabilities
driven by deterministic routing skew and predictable data-
dependent switching. To completely mitigate these spatial and
temporal leakages, this work proposes a dynamically morphing
BMM architecture implemented on an embedded FPGA (eFPGA)
fabric. By continuously swapping polymorphic architectural
variants during execution, the proposed design physically forces
symmetric signal routing, effectively decoupling the physical
power signature from the underlying data and blinding ad-
versaries to bit-level transitions. We rigorously evaluated 64-
bit, 128-bit, and 256-bit Karatsuba-based BMM datapaths using
fixed-versus-random Test Vector Leakage Assessment (TVLA)
and Quantitative Information Flow (QIF) analysis. While the
unprotected standard FPGA exhibited catastrophic first-order
leakage-peaking at TVLA t ≈ −660 and exposing 0.037 bits of
Shannon entropy for the 256-bit design, the proposed eFPGA
architecture collapsed all leakage to a strict 0.000 bits of
entropy, maintaining t-values safely within ±4.5 bounds across
all execution cycles. Furthermore, while disrupting predictable
timing paths incurs a deliberate latency penalty, the eFPGA
macro yields exceptional structural optimizations, achieving a
∼70% reduction in LUT utilization and drastically lowering
dynamic power consumption to 1.726 W for the 256-bit datapath.
Ultimately, this research proves that eFPGA morphing provides
a mathematically verifiable, highly area-efficient, and physically
secure execution environment for next-generation cryptographic
hardware.

