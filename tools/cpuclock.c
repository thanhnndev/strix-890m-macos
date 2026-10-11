// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Effective core clock of one CPU thread, measured with a chain of dependent integer adds (1 cycle each on Zen/Intel cores).
// sysctl hw.cpufrequency / machdep.tsc.frequency report the TSC (reference clock), not what the core runs at, so they cannot
// show a P-state that is stuck low. Build and run (macOS or Linux, x86_64):
//   clang -O1 -o /tmp/cpuclock tools/cpuclock.c && /tmp/cpuclock [seconds, default 10]
// Prints one line per 0.5 s: GHz and the spread. Run it idle, then with "yes > /dev/null" on other cores, to see boost behaviour.
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

static double now(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}

// 100 dependent adds per call = 100 cycles on a core that retires one dependent add per cycle.
static inline uint64_t chain(uint64_t x)
{
#define A4 __asm__ volatile("add $1, %0\n\tadd $1, %0\n\tadd $1, %0\n\tadd $1, %0" : "+r"(x));
#define A20 A4 A4 A4 A4 A4
    A20 A20 A20 A20 A20
    return x;
}

int main(int argc, char **argv)
{
    double total = argc > 1 ? atof(argv[1]) : 10.0;
    if (total < 1) total = 1;
    uint64_t x = 0;
    double t0 = now();
    while (now() - t0 < total) {
        double a = now();
        uint64_t n = 0;
        while (now() - a < 0.5) {
            for (int i = 0; i < 20000; i++) x = chain(x);
            n += 20000;
        }
        double dt = now() - a;
        printf("t=%5.1fs  %.2f GHz  (%llu M dependent adds)\n", now() - t0, (double)n * 100.0 / dt / 1e9,
               (unsigned long long)(n * 100 / 1000000));
        fflush(stdout);
    }
    return x == 12345 ? 1 : 0;      // keeps x live
}
