---
title: "Accelerating Dictionary Encoding Based Compression on GPU"
author: Edward
date: 2026-09-05
category: [Course Projects]
tags: [GPU, CUDA, Data Compression, Dictionary Encoding, Profiling]
---

# Introduction
This post is a short introduction to my course project in CMPT 984 (a graduate course on GPU) at Simon Fraser University: **accelerating a dictionary encoding based compression algorithm with CUDA**, together with an ablation study and kernel-level profiling. The full details can be found in the [project report (PDF)](/assets/files/gpu_compression_report.pdf) and the [presentation slides (PDF)](/assets/files/gpu_compression_slides.pdf).

**Why GPU + compression?** GPU enjoys massive parallelism (SIMT architecture) and an order-of-magnitude higher memory bandwidth than CPU, while the PCIe bus between host and device remains a narrow pipe. Data compression fits this picture nicely:
- many compression algorithms can be decomposed into independent per-chunk work, which is exactly what GPU is good at;
- moving *compressed* data across PCIe indirectly saturates the limited bus bandwidth with more useful payload.

# The Benchmark Algorithm
To keep the focus on GPU optimization itself, a **simple dictionary encoding** algorithm is used as the benchmark: 16 frequently shown characters (vowels, space, etc.) are preselected into a dictionary, so each of them can be encoded with 4 bits plus 1 flag bit (5 bits in total), while any other character costs 9 bits. The compression pipeline is:

1. Load the lookup dictionary and copy input data from host to device;
2. Divide the input stream into chunks (1024 characters each), one GPU thread encodes one chunk;
3. Compute the offset of each encoded chunk in the output byte stream (encoded chunks vary in size);
4. Assemble encoded chunks into the output buffer according to the offsets, and copy it back to host.

# Three GPU Optimizations
The project studies three features adopted on the GPU side.

## Lookup Dictionary (LD)
The character-to-bits mapping never changes during runtime, so it is loaded into the **constant memory** on device, which is cached and shared by all threads. Each lookup costs `O(1)`, instead of looping over a list to test membership.

## Memory Coalesced Access (MCA)
With the naive *horizontal partitioning*, each thread reads a consecutive range of characters, so addresses accessed by threads **within the same warp** at each step are scattered and cannot be coalesced:

![Horizontal Partitioning](/assets/img/gpu_compression/fig1_horizontal.png){: width="450" }
_Horizontal partitioning: consecutive addresses per thread, scattered across the warp_

A *vertical (columnar) partitioning* makes threads in a warp touch adjacent addresses simultaneously, so the hardware can combine them into one coalesced memory transaction:

![Vertical Partitioning](/assets/img/gpu_compression/fig2_vertical.png){: width="450" }
_Vertical partitioning: adjacent addresses across the warp at each step_

## Parallelized Assembly (PA)
After per-chunk encoding, the variable-length chunks must be stitched into one byte stream. Once the offset of every chunk is known, the total buffer size can be allocated immediately, and **each thread independently writes its own chunk to its destination offset** — the assembly becomes embarrassingly parallel:

![Assembly Process for Encoded Data](/assets/img/gpu_compression/fig3_assembly.png)
_The 4-step assembly process: compute offsets, allocate the byte stream buffer, assemble in parallel, copy back to host_

# Evaluation
The workload is the Wikipedia top-1000 most-viewed articles concatenated into one ~28 MB text file, running on a Nvidia GPU from free-tier Google Colab.

**Compression effectiveness.** CPU and GPU implementations achieve identical space saving (as expected — it only depends on the algorithm logic), around **28%** on average, thanks to the highly skewed character distribution in natural language:

![Histogram of Space Saving Ratio](/assets/img/gpu_compression/fig4_histogram.png){: width="550" }
_Space saving ratio distribution achieved by CPU and GPU implementations_

**Latency & ablation study.** The end-to-end latency breakdown (unit: ms):

| Stages | All ON | OFF: LD | OFF: LD&PA | CPU |
| :--- | ---: | ---: | ---: | ---: |
| Character Replacement | 92 | **132** | 132 | - |
| Assemble Data | 9 | 9 | **370** | - |
| **Compression Latency** | **157** | 191 | 552 | 816 |
| **Decompression Latency** | **118** | 117 | 117 | 586 |

Key observations:
1. GPU beats CPU by **~5x** on compression and on decompression;
2. Disabling *Lookup Dictionary* increases the encoding kernel latency from 92 ms to 132 ms;
3. Disabling *Parallel Assembly* is disastrous — assembly falls back to serialized execution and slows down by **40x** (9 ms → 370 ms);
4. *MCA* did not show measurable gain in this experiment, possibly because the chunk size / block size hyperparametres make the stride too big to trigger coalescing.

> Profiling with Nvidia **Nsight Compute** confirms what LD brings to the encoding kernel: 23% faster execution, 35% better memory throughput and 24% fewer elapsed cycles.
{: .prompt-info }

# Takeaways
- Dictionary encoding (bit-packing) is a concise yet effective compression scheme for text;
- The dominant win on GPU comes from **keeping every stage parallel** — one serialized stage (like naive assembly) immediately eats up the gains;
- Vendor profiling tools (Nsight Compute/System) are essential to verify whether an "optimization" actually lands on the micro-architecture level.

Future directions include tuning block/chunk sizes, exploiting shared memory to reduce DRAM traffic, and combining with technologies like [GPUDirect Storage](https://developer.nvidia.com/gpudirect-storage) to serve real query processing scenarios.
