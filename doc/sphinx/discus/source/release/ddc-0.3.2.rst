
The Disciplined Disciple Compiler 0.3.2 (2013/07/26)
====================================================

DDC is a research compiler used to investigate program transformation in the
presence of computational effects. This is a development release. There is
enough implemented to experiment with the language, but not enough to solve
actual problems...        (unless you're looking for a compiler to hack on).

DDC compiles several related languages:

 * Disciple Core Lite (Module.dcl)

   Explicitly typed System-F2 style core language with region, effect and
   closure typing. Evaluation is left-to-right call-by-value by default.
   There is also a capability system to track whether objects are mutable or
   constant, and to ensure that computations that perform visible side effects
   are not reordered inappropriately. The Lite language supports higher order
   functions, algebraic data types and unboxed primitive types.
   (not all features are supported by the code generators yet, see below)

 * Disciple Core Tetra (Module.dct)

   Like Disciple Core Lite but using the 'S' computation type to encode
   effects rather than having a latent effect on the function type constructor.
   (does not yet compile to C or LLVM)

 * Disciple Core Flow (Module.dcf)

   Language with builtin support for Series expressions and Data Flow Fusion.
   This core language fragment and its associated transforms is used by
   the repa-plugin available on Hackage.

 * Disciple Core Salt (Module.dce)

   A cut-down version of Disciple Core Lite that can be easily mapped onto
   C or LLVM code. The Salt language is first-order and does not support
   partial application. DDC transforms Lite code to Salt code and uses Salt as
   an intermediate representation. You can also write programs in it directly.

 * Disciple Core Eval (Module.dcv)

   Similar to Disciple Core Lite, except without unboxed primitive types.
   This language is accepted by the interpreter.

All core languages share the same abstract syntax tree (AST), type checker,
and are amenable to the same program transformations. They differ only in the
set of allowable language features, and which primitive types and operators
are included.


What Works in this Release
--------------------------

 * Parsing and type checking for the Lite, Tetra, Flow, Salt and Eval languages.

 * Compilation via C and LLVM for first-order Lite and Salt programs.

 * Interpreter for the full Eval language.

 * Data Flow Fusion for the Flow language.

 * Cross module inlining.

 * Rewrite rules.

 * Generation of LLVM aliasing and constancy meta-data.

 * Several standard program transformations:
    Anonymize (remove names), Beta (substitute), Bubble (move type-casts),
    Elaborate (add witnesses), Flatten (eliminate nested bindings),
    Forward (let-floating), Namify (add names), Prune (dead-code elimination),
    Snip (eliminate nested applications).


What Doesn't
------------

 * No source locations in error messages.

   The messages themselves are ok, but you don't get a line-number.

 * No storage management.

   There is a fixed 64k heap and when you've allocated that much space the
   runtime just calls abort().

 * No type inference.

   You have to write all your own type applications, including effect and
   closure annotations, which isn't much fun.

 * No multi-module compilation driver.

   DDC isn't restricted to whole-program compilation, but the --make driver
   doesn't handle multiple modules. You'd need to do the linking yourself.

 * No user defined data types.

   Pairs and Lists are baked in, but we don't handle data type declarations.

 * No code generation for lazy evaluation.

   The language semantics and interpreter support it, but the C and LLVM
   code generators do not.

 * No code generation for partial application.

   likewise.


Previous Releases
-----------------

 * 2012/12 DDC 0.3.1: Added Lite fragment, compilation to C and LLVM.

 * 2012/02 DDC 0.2.0: Project reboot. New core language, working interpreter.

 * 2008/07 DDC 0.1.1: Alpha compiler, constructor classes, more examples.

 * 2008/03 DDC 0.1.0: Alpha compiler, used dependently kinded core language.


Immediate Plans
---------------

 1) Implement a local type inferencer. The type inferencer will fill in type
    applications as well as effect and closure annotations, but will not
    perform let-generalisation. This is similar the local type inference used
    to support implicits in Coq/Gallina.

 2) Flesh out the Tetra fragment of the language, using the new approach to
    representing effects with computation types.

How you can help
----------------

 1) Work through the tutorial on the web-site and send any comments to the
    mailing list.

 2) Send bug-reports to the mailing list, or get an account on the trac.

 3) Fix bugs on the trac.

 4) Say hello on the mailing list and we can help you get started on any of
    the main missing features. These are all interesting projects.

 5) Tell your friends.


People
------

 The following people contributed to DDC since the last release:

 * Amos Robinson          - Rewrite rule system and program transforms.

 * Ben Lippmeier          - Code generators, framework, program transforms.

