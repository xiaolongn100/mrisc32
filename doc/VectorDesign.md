# Vector Design (SIMD)

## Description

The MRISC32 approach to Single Instruction Multiple Data (SIMD) operation is very similar to the early [vector processors](https://en.wikipedia.org/wiki/Vector_processor) (such as the [Cray-1](https://en.wikipedia.org/wiki/Cray-1)):
* There are 32 vector registers, V0-V31, with *at least* 16 elements in each register.
* All vector elements are the same size (32 bits), regardless if they represent bytes, half-words, words or floats.
* A Vector Length (VL) register controls the length of the vector operation.
* There are vector,vector and vector,scalar versions of most integer and floating point operations.
* Vector loads and stores can either be stride-based or gather-scatter (see [addressing modes](AddressingModes.md) for more details).
* Folding operations are provided for doing horizontal vector operations (e.g. sum, min/max).
* Each vector register has a Register Length (RL) state.
  - Writing to a register updates the Register Length to the operation Vector Length.
  - Elements with an index >= RL are zero.
  - Clearing all Register Lengths to zero reduces stack overhead.


## Motivation

The dominating SIMD solution today (SSE, AVX, NEON) is based on an ISA that is largely separate from the scalar ISA of the CPU. That model, however, comes with relatively high costs for hardware and software:
* All SIMD instructions operate on fixed width registers (you have to use all elements or nothing).
* A completely separate instruction set and separate execution units are used for operating on the SIMD registers.
* Each register is split into different number of elements depending on the type (i.e. the data is packed in the registers).
* It is hard to write software that utilizes the SIMD hardware efficiently, partially because compilers have a hard time to map traditional software constructs to the SIMD ISA, so you often have to hand-write code at a very low level.
* In order to exploit more parallelism in new hardware generations, new instruction sets and registers have to be added (e.g. MMX vs SSE vs AVX vs ...), leading to a very complex software model.

In comparison, the MRISC32 vector model is easier to implement in hardware and easier to use in software. For instance:
* The same execution units can be used for both vector operations and scalar operations, meaning less hardware.
* The software model maps better to traditional software patterns, and it should be easier for compilers to auto-vectorize code.
* The same ISA can be used for many different levels of hardware parallelism. In other words, the vector model scales well from very simple, scalar architectures, all the way up to highly parallel superscalar architectures.


## Examples

Consider the following C code:

```C
void abs_diff(float* c, const float* a, const float* b, const int n) {
  for (int i = 0; i < n; ++i) {
    c[i] = fabs(a[i] - b[i]);
  }
}
```

Assuming that the arguments (c, a, b, n) are in registers S1, S2, S3 and S4 (according to the [calling convention](Registers.md)), this can be implemented using scalar operations as:

```
abs_diff:
  bz      s4, #done    ; n == 0, nothing to do

  ldhio   s12, #0x7fffffff

  ldi     s11, #0
loop:
  add     s4, s4, #-1  ; Decrement the loop counter

  ldw     s9, s2, s11  ; s9  = a
  ldw     s10, s3, s11 ; s10 = b
  fsub    s9, s9, s10  ; s9  = a - b
  and     s9, s9, s12  ; s9  = abs(a - b) (i.e. clear the sign bit)
  stw     s9, s1, s11  ; c   = abs(a - b)

  add     s11, s11, #4 ; Increment the array offset
  bgt     s4, #loop

done:
  j       lr
```

...or using vector operations as:

```
abs_diff:
  add     sp, sp, #-4
  stw     vl, sp, #0

  bz      s4, #done    ; n == 0, nothing to do

  ldhio   s10, #0x7fffffff

  ; Prepare the vector operation
  cpuid   s11, z, z    ; s11 is the max number of vector elements
  lsl     s12, s11, #2 ; s12 is the memory increment per vector operation

loop:
  min     vl, s4, s11  ; vl = min(s4, s11)

  sub     s4, s4, s11  ; Decrement the loop counter

  ldw     v9, s2, #4   ; v9  = a
  ldw     v10, s3, #4  ; v10 = b
  fsub    v9, v9, v10  ; v9  = a - b
  and     v9, v9, s10  ; v9  = abs(a - b) (i.e. clear the sign bit)
  stw     v9, s1, #4   ; c   = abs(a - b)

  add     s1, s1, s12  ; Increment the memory pointers
  add     s2, s2, s12
  add     s3, s3, s12
  bgt     s4, #loop

done:
  ldw     vl, sp, #0
  add     sp, sp, #4
  j       lr
```

Notice that the same instructions are used in both cases, only with vector operands for the vector version. Also notice that it is easy to mix scalar and vector operands for vector operations.


## Implementations

It is possible to implement vector operations in various different ways, with different degrees of parallelism and different levels of operation throughput.

### Scalar CPU

In the simplest implementation each vector operation is implemented as a pipeline interlocking loop that executes a single vector element operation per clock cycle. This is essentially just a hardware assisted loop.

Even in this implementation, the vectorized operation will be faster than a corresponding repeated scalar operation for a number of reasons:
* Less overhead from loop branches, counters and memory index calculation.
* Improved throughput thanks to reduced number of data dependency stalls (vector operations effectively hide data dependencies).

Low-hanging fruits:
* Deep pipelining:
  - Long pipelines (e.g. for division instructions) can be blocking/stalling in scalar mode, but fully pipelined in vector mode, without breaking the promise of in-order instruction retirement.
* Improved cache performance:
  - With relatively little effort, accurate (non-speculative) data cache prefetching can be implemented in hardware for vector loads and stores.

### Scalar CPU with parallel loops

An extension to the simplest model is to keep two (or more) vector loops running in parallel, which would enable a single-issue CPU (fetching only a single instruction per cycle) to execute multiple operations in parallel.

This is similar to the concept of "chaining" in the Cray 1, which allowed it to do 160 MFLOPS at 80 MHz.

This requires slightly more hardware logic:
* Duplicated vector loop logic.
* Duplicated register fetch and instruction issue logic.
* More register read ports (with some restrictions it may be possible to rely entirely on operand forwarding though).
* Logic for determning if two vector operations can run in parallel, and how.
* Possibly more execution units, in order to maximize parallelism.

One advantage of this implementation is that the instruction fetch pipeline can be kept simple, and the logic for running multiple instructions in parallel is simpler than that of a traditional [superscalar architecture](https://en.wikipedia.org/wiki/Superscalar_processor).

Another advantage, compared to implementing a wider pipeline (see below), is that you can improve parallelism wihout adding more execution units.

### Multiple elements per cycle

Instead of processing one element at a time, each vector loop iteration can process multiple elements at a time. For instance, if there are four identical floating point units, four elements can be read from a vector register and processed in parallel per clock cycle.

This is essentially the same principle as for SIMD ISAs such as SSE or NEON.

It puts some more requirements on the hardware logic to be able to issue multiple elements per vector operation. In particular the hardware needs:
* A sufficient number of execution units.
* Wider read/write ports for the vector registers and the data cache(s).
* More advanced data cache interface (e.g. for wide gather-scatter operations).

