# KISS FOR KISS

`k4k` (KISS for KISS) is a coding agent focusing on building computer
programs that are kept stupidly simple (following the well-known KISS
principle) by itself being kept stupidly simple.

It aims to give programmers a simple and understandable AI-assisted
tool to build a specific class of applications based on a single core
principle:

Coding agents are stochastic processes that converge to valid answers if
provided a deterministic, efficient and complete harness, and enough time.

What is an harness? It is a system that is evaluating the gap between
the desired state of the computer program and the reality of the
current state of this computer program. This evaluation results in a
modification of the agents context aimed at making progress towards
reducing the gap to 0.

The harness must be deterministic in the following sense: for a given
behavior of the computer program (independently from its
implementation), the harness should always return the same evaluation.

The harness must be efficient in the following sense: the modification
of the agents context MUST reduce the gap.

The harness must be complete in the following sense: every aspect of
the desired state that matter for the user must considered by the
harness.

There are many known ways to implement such an harness, especially
depending on the class of computer programs we target. We choose to
rely on Mathematics to build POSIX-like computer programs. We call
POSIX-like computer programs command-line tools and libraries which
behavior is exclusively made of well-specified I/Os, and that is fully
determined by the command line arguments and the file system contents
they are executed on. We also focus on such computer programs that
follow the KISS design principle: their behavior needs to be
expressible with relatively short and general specification.

We therefore exclude a lot of computer programs from the scope of
`k4k`: complex user-facing applications, large webapps, huge software
stacks or other beasts are not part of our scope.

What do we mean when we say "We rely on Mathematics" to implement the
harness? Mathematics provide us unambiguous definitions of objects and
the ability to prove the properties of such objects thanks to rigorous
logical reasoning. Computer programs are mathematical functions and
can be characterized with rigor. Computer programs - even the ones
that satisfy the KISS principle - are *large* definitions for a
mathematician (in Algebra, groups only require 5 lines while even
something as simple as the "cd" command requires 10 times more lines
to be correctly defined [see the work we did in the PhD of Nicolas
Jeannerod]). Thus, building a computer program in one go is
difficult. However, one can decompose these definitions into smaller
pieces that can be formally related to the final object: one can know
with certainty that the development is going in the right direction.

The ideas of the previous paragraph lead us to the harness used by k4k:

The harness is a tool that charaterizes the missing aspects of the
mathematical characterization of the development in its current state
and its desired characterization.

This definition naturally induces the following workflow:

1. Do we have an up-to-date desired characterization D? 
   If yes => go to step 2.
   Else => build one first.
   
2. Do we have a characterization S of the current development?
   If yes => go to step 3.
   Else => characterize current software

3. What is missing to get an equivalence between S and D?
   Nothing => Done!
   There are P in Properties D \ S => Modify software to get P + S and go to step 2.

# How to build a desired characterization of D?

`k4k` uses a file to retrieve the user expectations. This file is NOT
a source file: it is an asynchronous interaction file. The user owns
sections in this file that k4k, the other sections are freely
modifiable by k4k and the user.

If this file umambiguously characterizes a computer program, it is
said to be stable. If not, it is said to be in an unstable state.

# How to characterize current software?

`k4k` uses a verifier to that end. A verifier allows `k4k` to get
confidence about the characterization of the software it has built.

Typical tools used by k4k: Rocq, Lean, Verus, Frama-C, AFL, ... and
well as programming languages that allow to get high-confidence about
the software built with them. 

k4k can also build it own verification tools: if a computer program
can be easily built with a DSL with clear reasoning principles, k4k
can decide to built a compiler for this DSL and a verification tool
(e.g., a certified Rocq library or a static analyzer)

k4k provides verifiable artefacts that can be audited to validate the
characterization it claimed.

# How to decide which P is relevant?

`k4k` follows a continuous delivery methodology: we build software to
surface unknowns-unknowns as early as possible: P is therefore chosen
to tackle the most risky aspects of the development.

# How does the user use k4k?

The user writes in an interaction file (e.g., `myproject.k4k`) and executes:

```
k4k myproject.k4k
```

`k4k` will display what it does (with `-v`, `-vv`, ... one can get
more details about it). By default, `k4k` only writes a high-level
explanation of what is does, in one line that is updated, it also
gives an ETA for completion. If the interaction file is unstable, it
displays a clear message for the user to provide more inputs in the
interaction file to unblock it.

# How does k4k work?

`k4k` works in the current directory. It maintains a knowledge base in
the file system as well as source code to build the artefacts it
needs. It follows a spec-driven development approach and calls coding
agents it has access to in an headless mode, either in long-running
session or in one shot.

`k4k` is model agnostic and never relies on the *judgment* of agents
to validate. The only judges are the human that validates the
characterization as acceptable and the verifiers that validate the
proof arguments.


# Why am I using "characterization" instead of "specification"?

Don't worry, there is no much difference between "specification" and
"characterization" when I use these words. I am using this word
because I want `k4k` to be as accurate as possible regarding the
behavior of the software we build: the devil is in the details and I
believe that most of the bugs found in "certified" software actually
comes from the distance between the model and the actual software: if
a specification is too abstract, proving that the implementation
respects it has little value if some observable "details" abstracted
by the specification actually matters in practice.
