#set text(region: "gb")
#set par(justify: true)

#import "@preview/codly:1.3.0": *
#show: codly-init
#import "@preview/codly-languages:0.1.10": *
#codly(languages: codly-languages)

#show title: set text(size: 17pt)
#show title: set align(center)

#let todo(b) = text(red, [TODO: ] + b)

#set heading(numbering: "1.")
#show bibliography: set heading(numbering: "1.")

#show heading.where(level: 1): it => {
  set text(24pt)
  block[
    #{ if it.numbering != none { counter(heading).display() } }
    #{it.body}
    #v(8pt)
  ]
}

#set document(
  title: "Editing the editor: proposing an extensible language extension for Agda",
  author: "Job Vonk",
  description: []
)

#stack(spacing: 1fr)[
  #align(center)[#image("uu.png", width: 45%)]
][
  #show title: set text(size: 24pt)
  #line(length: 100%)
  #title()
  #v(14pt)
  #line(length: 100%)
][
  #grid(columns: (1fr, 1fr), column-gutter: auto, align: (left, right))[
    *Author:*\
    #context document.author.at(0)
    ][
    *First Supervisor:*\
    Dr. W. S. Swierstra

    *Second Supervisor:*\
    I. G. de Wolff MSc.

    *Daily Supervisor:*\
    L. B. Chonavel MSc.
  ]
][
  #align(center, datetime.today().display("[month repr:long], [year]"))
]

#pagebreak()

#show outline.entry.where(level: 1): set text(weight: "semibold")
#outline(title: "Table of Contents", depth: 3)

#pagebreak()

#counter(page).update(1)
#set page(numbering: "1")

= Introduction
 
Dependently-typed programming languages provide a means to prove that software meets its specification. This gives rise to software that is completely verified; that is, it is proven that a library or a program behaves in accordance to its defined specification. Dependent types can be much more precise about the programs they describe. The type can encode invariants that must hold during the function's execution, or preconditions on the parameters.

Even though complete verification sounds ideal, there is one major flaw: using formal methods, like dependently-typed languages and theorem provers, to verify code can be labour intensive. It takes mathematically skilled developers, and quite some time (compared to informal quality assurance methods like testing) to fully verify a system @galois. Good tooling in dependently-typed languages can lift some of the burden of verifying a system: many dependently-typed languages need interactive development environments (IDEs) to facilitate the incremental construction of correct software.

Additionally, dependently-typed languages are also often used as theorem provers. However without tooling, such a system can be hard to prove theorems in, especially since normalisation of the system can be hard to reason about without querying the system. Additionally, these systems benefit even more from an IDE -- for theorem provers often called an _interactive theorem prover_ (ITP) -- since proofs are written as an interactive dialogue between the theorem prover and the developers.

#figure(caption: [Example of using Lean4, an interactive theorem prover, to prove a theorem. The panel on the right shows information about the current state of the proof and what remains to be done at the location of the cursor.], image("itp.png")) <itp>

Juhošová et al. @learning-obstacles have investigated what obstacles students experience when learning to use Agda as an interactive theorem prover. Their advice is to improve robustness and accessibility, where one point they mention for both improvement areas is polishing and improving the existing tooling.

Juhošová et al. @juhovsova2026way also conducted a study about type driven development. The participants of the study were asked to suggest improvements to languages that offer type-driven development and their tooling. Some of the improvements the participants suggested were "wider editor support for interactive modes", "better IDE support for large-scale proof engineering" and more support for refactoring. Backx @dtitp-study has also investigated how (novice) dependently-typed language programmers write code. He, too, saw that users experience a lack of tooling support for refactorings, and also recommends authors of dependently-typed interactive theorem provers to improve the editor tooling with, for example, a search feature for lemmas, or refactoring features that can also be found in non-dependently typed languages.

In Agda we see little innovation in editor features, even though there is strong incentive from users to develop new features. All of the current extensions for Agda support roughly the same feature set. These editor features are provided by the compiler, and the extensions all merely implement an interface to these compiler features. One reason for the lack of innovation might be that extending this feature set is quite difficult: the features are implemented within the Agda compiler, which is a large Haskell code base, which is hard to extend. Additionally, these features are quite tightly coupled to Agda's elaborator and unification system, which are complex systems that are hard interact with without much prior experience.

Another reason for the little innovation might be the fact that none of the extensions are written in Agda itself, rather they are implemented in various languages like ReScript, Haskell or Emacs Lisp. This raises the barrier of entry for people familiar with Agda wanting to contribute a new extension feature.

These two observations motivate the following research questions:
+ *Is Agda a suitable language to write practical programs with?* \
  Current big Agda projects are libraries like the standard library, unimath #footnote(link("https://unimath.github.io/agda-unimath/")) and cubical #footnote(link("https://github.com/agda/cubical")), which highlight Agda's strength as a theorem prover. However, at the Agda wiki's home page, the language is introduced as a dependently-typed _programming language_ before being introduced as a proof assistant #footnote(link("https://agda.readthedocs.io/en/latest/getting-started/what-is-agda.html")). Strangely, there does not seem to be a big practical programming project showing Agda's viability as a programming language. By writing a language extension in Agda, we aim to assess whether or not Agda is a viable programming language as opposed to a theorem prover. After the development, we can reflect on issues in the language or its tooling, and report a list of improvements to make Agda more suitable for practical applications. 

+ *Is it possible to make an extensible Agda extension written in Agda itself?* \
  We will answer this question by writing an Agda language extension for Visual Studio Code in Agda -- called Avea. The goal is to explore whether we can leverage Agda's meta-programming capabilities to allow developers to write their own sophisticated tooling in Agda itself. This process of extending Agda's tooling should be easier than the current process of extending the Agda compiler, and updating every extension to use the new tooling feature.

#pagebreak()

= Background

Before discussing Avea's implementation,
- we need to familisarise ourselves with the available features of Visual Studio Code, the editor Avea will operate in.
- Then we will discuss features in existing Agda extensions, and how they interact with the Agda compiler.
- Lastly, we will discuss metaprogramming in several dependently-typed languages, which is foundational for Avea's extensibility.

== Visual Studio Code <vscode>

Visual Studio Code (VS Code) is an open-source code editor developed by Microsoft. According to last year's StackOverflow Developer survey, 79.6% of the respondents used Visual Studio Code regularly in 2025 @StackOverflow2025. While the editor ships with support for Javascript/Typescript support out of the box, it has a robust extension system and a marketplace with extensions for many other programming languages. This includes extensions for mainstream languages like C++, C\#, Rust, etc. However, Visual Studio Code has also been target for dependently-typed languages. For example, Rocq and Lean4 have sophisticated language extensions.

#figure(image("vscode.png"), caption: [Screenshot of Visual Studio Code, the numbers correspond to the enumeration in the paragraph below.]) <vscode-fig>

Extensions can be written in Javascript or Typescript. When VS Code executes the code for an extension, it provides an API which allows extensions to interface with the different parts of the editor. The components relevant to Avea's development are highlighted in @vscode-fig and discussed below.
+ The API allows extension developers to create panels, these are implemented as an HTML `iframe`. This means that the panel can display arbitrary HTML, CSS and Javascript. Additionally, the extension can send and receive messages to and from the panel using the `window`'s `postMessage` method and the `window`'s `message` event. This panel is used by the `lean4-vscode` extension as the info view, where information about the proof state is displayed (as seen in @itp), in Agda this window is called the display buffer.
+ The editor itself can also be interacted with. Extension developers can request parts of the buffer based on positions within the document. Or the buffer can be programmatically edited, or decorated using syntax highlighting.
+ Extensions can also log information to VS Code's output window. The API for this looks like a simple logging library, with different levels of logs. The logs can be viewed in the ouput window per extension, and can also be exported from there. This is especially useful during debugging.
+ There is a status bar at the bottom of the screen that displays small amounts of information -- typically single words or icons. Commonly, the status bar contains the the location of the cursor, how many errors the project contains or the language of the currently active buffer.

// == Language Server Protocol <lsp-bg>

// The Language Server Protocol (LSP) is a protocol developed by Microsoft that aims to standardise the communication between language tooling and integrated development environments (IDEs) @LSP. The purpose of the protocol is to solve the $M times N$ problem for language extensions. The essence of this problem is that language tooling developers need to implement a separate extension for each editor they want to support. As shown in @m-times-n, given $N$ languages and $M$ editors, this results in $M times N$ extensions in total. LSP simplifies this by letting language tooling developers only implement the language side of LSP, and editor developers implement the editor side of LSP. This reduces the total number of extension down to just $M+N$, which is significantly less burden on tooling developers.

// #figure(caption: [Visualisation of how LSP solves the $M times N$ problem for language editors: each language tooling author needs to support just LSP instead of every single editor.])[
//   #columns(2)[
//     #image("before-lsp.png")
//     #colbreak()
//     #image("after-lsp.png")
//   ]
// ]<m-times-n>

// In more technical detail, the editor sends notifications to the language tool about actions the user has done, e.g. opening or closing a document, changing the source code, or executing a code action. The language tool can respond to those notifications as well as send notifications to the IDE about warnings, errors or definition sites.

// The LSP protocol has been proven in practice by many main stream languages, among which C++, C\# and Rust. Even dependently-typed languages have implementations for the LSP protocol:
// - Idris has a Visual Studio Code extension that supports the LSP protocol @idris2-lsp. There is a package `idris2-lsp` that depends on the Idris compiler. Since both the LSP server and the compiler are implemented in Idris itself, the LSP can depend on the compiler directly. And therefore, the LSP can immediately invoke the type checking commands. The Idris LSP has some limitations, however. One of those is that hover actions only work if the entire file type checks.
// - Lean4 has an implementation of the LSP protocol with Lean-specific extensions. The implementation is written in Lean itself as part of the compiler @lean4. The Visual Studio Code extension, for example, can rely on the core LSP part for providing autocompletions and code actions. However, since the extensions are non-standard, they require implementations for every IDE separately. For example, the `vscode-lean4` extension has workspaces for setting up the LSP, as well as the infoview window, which displays context information, results of `#eval`s and goal types.
// - Rocq has two extensions for Visual Studio Code, each with their own implementation of the LSP protocol: `vsrocq` with the `vsrocq-language-server` @vsrocq, and `rocq-lsp` @rocq-lsp. The `rocq-lsp` GitHub repository describes that, in addition to the standard protocol, there are interactions specific to Rocq for, for example, displaying the proofs goals in tactic mode and file checking progress updates. Similar to Lean, both extensions also feature a infoview window where the proof goals, context and `Print` statements are displayed.

// The extensions these languages have made are all quite similar of nature, and Rask et al. @SLSP have therefore developed the Specification Language Server Protocol (SLSP) that aims to standardise extensions to the LSP protocol regarding theorem proving, providing goal info and translating to other languages. They have implemented a server for SLSP for the Vienna Development Method, which is a specification language that also features theorem proving.

== Existing Agda extensions <background-agda>

The Agda ecosystem has a number of extensions for different programming editors. All of these extensions behave very similarly and feature a similar set of tools:
// - There are numerous commands the developer can issue using key binds to navigate goals, request a goal's type and context or refine parts of the goal.
// - Additionally, the extensions are responsible for providing semantic syntax highlighting. That means that tokens are highlighted based on what they represent, for example, identifiers referring to functions are highlighted in blue, whereas identifiers for constructors are green.
// - Lastly, the extensions provide an input method for writing unicode characters in the Agda source files. The developer can type `"\"` and a identifier for the character (which is usually the latex code), to write characters that cannot be written using regular keyboards.

- Agda has many different *commands* that users can invoke using keybindings. These commands can be categorised in roughly three categories.
  #grid(columns: (1fr, 1fr), gutter: 16pt)[
    _Goal refinement commands_ allow the user to enter (parts of) expressions into a goal and Agda will type-check or refine them based on the goal's type. Examples of commands in this category are:
      - the refine command, which inserts question marks for every missing argument of the given expression;
      - the make case command, which creates exhaustive pattern matching clauses for a parameter, where possible (see @make-case).
  ][
    #align(
      horizon,
      [#figure(caption: [Example use of the make case command: in a goal the user can type `C-c C-c` in a goal (left image), and specify which parameters to case split on and all clauses appear (right image).])[
        #grid(columns: (auto, auto), column-gutter: 4pt, align(horizon, image("make-case1.png")), image("make-case2.png"))
      ]<make-case>]
    )
  ]
  _Goal display commands_ give information about the goal under the cursor, which is displayed in the display buffer. This information informs the user about what they need to prove and what variables are available in the current context. Examples of commands in this category are:
    - the infer command, which displays the inferred type of the goal within an expression;
    - and the context command, which displays the available local variables and their types, as illustrated in @display-buffer.
  _General Commands_ are commands that can be executed on a module or an arbitrary expression. Examples include
    - the load command, which type checks the current module and returns syntax highlighting information;
    - the search about command, which searches the current module scope for functions with signatures containing some key types;
    - the compile command, which compiles the current module using one of the available backends.
#grid(columns: (50%, 50%), gutter: 16pt)[
  - The *display buffer* is a panel accompanying the editing buffers, where information about the state of the extension is displayed. For example, when the load file command is invoked the compiler shares information about its progress type-checking the current file and its dependencies. After type-checking completed, the buffer can show either information about goals -- if the type-checking was successful -- or it can show information about any type errors it encountered.
][
  #align(horizon)[
    #figure(caption: [The output on the display buffer after invoking the context command (`C-c C-,`) in Avea.], image("display-buffer.png")) <display-buffer>
  ]
]
#grid(columns: (60%, 40%), gutter: 16pt)[
  - *Syntax highlighting*: Once the current file is successfully type-checked, the compiler also provides highlighting information to the extension. Agda provides _semantic highlighting tokens_, which means that the tokens are coloured based on what they represent. For example, instead of colouring a variable black regardless of its value -- Agda will colour a variable referencing a function blue. Additionally, Agda provides syntax highlighting for different error types and the locations of where they occur.
][
  #align(horizon, figure(caption: [Semantic syntax highlighting in Avea. For example, the colour of the constructor `u` is different from the type `t`, even though both are variables.], image("syntax-highlighting-example.png")))
]
- *Jump to error*: if the type-checking was not successful, then the compiler will point to the type-error it got stuck on. The extension receives information about where this error is located and moves the user's cursor to that file at the correct position.

- *Go to definition*: The extension answers go-to-definition requests from the editor, where definition site information is provided by the `HighlightingInfo` message. Visual Studio Code provides a position, and the extension has to query the tokens for the currently active file to find one which has the position in its range.
#grid(columns: (1fr, 1fr), gutter: 16pt)[
  - *Input mode*: All extensions have support for the unicode input mode to type unicode characters in Agda source code. This extension also has support for the input mode, in a similar fashion as the emacs-mode, where the status bar shows which characters can be typed next, the desired character can be selected using the arrow keys.
][
  #align(horizon)[
    #figure(
      image("inputmode.png"),
      caption: [The status bar during input mode shows which characters have been typed, which characters can be typed next, and which variants of the current character there are.]
    )
  ]
]

=== Implementations

There are various implementations of Agda extensions for different editors. These implementations can use the endpoints provided by the Agda compiler for external programs to call Agda internals. The compiler has flags which open a Read-Eval-Print-Loop (REPL) environment that extensions can use to issue commands and receive responses. In general every extension has a similar high-level architecture, which is illustrated in @general-arch.

Every extension spawns one or more processes of the REPL the Agda compiler provides. When the user interfaces with the editor, the extension is notified and sends requests to Agda. Agda responds and the extension makes sure the correct updates are done to the editor.

#figure(caption: [High level architecture of all Agda extensions. The extension is the mediator between the editor and the Agda compiler process.], image("agda-extension-general-arch.png")) <general-arch>

Below we discuss the existing Agda extension implementations for various editors, and highlight some differences in their implementation.

- emacs-mode is the first Agda extension, which was developed alongside the Agda compiler. The extension is divided into two parts:
  1. The user event listeners, these are functions triggered by command hooks within Emacs. At startup, the extension opens a handle to an Adga process with the `--interaction` flag. The event listeners send different commands to the Agda compiler via this process, depending on the type of action. 
  2. Agda responds with Emacs Lisp code that triggers response functions. These response functions are parameterised by data that is provided by the Agda compiler, which encodes the response data in Emacs Lisp data types.
#figure(caption: [Agda's `--interaction` flag responds with Emacs Lisp code, which is executed by the emacs-mode extension. The `agda2-info-action` function updates the display buffer with the parameters filled in by the Agda compiler.], image(width: 50%, "emacs-response.png"))
- Cornelis is an extension for Vim written in Haskell. As opposed as emacs-mode, it uses the the `--interaction-json` flag, which has the same API as the `--interaction` flag, but responds with a JSON format instead of Emacs Lisp code.

  Cornelis also has a different way of handling responses and managing the communication to the Agda compiler. It creates a process handle for each buffer, such that responses can be processed asynchronously, and disregard the editor's state.
- Agda-mode-vscode by banacorn is the original extension for Agda in Visual Studio Code. It is written in ReScript, an OCaml-like language that compiles to JavaScript. It uses the `--interaction` compiler flag, since it predates the `--interaction-json` flag.

  This extension tries to emulate the behaviour of the emacs-mode, but VS Code has less builtin machinery for tokenisation especially when the buffer has been edited. This means the extension listens for edits to the buffer, and recalculates the positions of the known tokens to keep the highlighting working for unchecked states. Additionally, the extension also features a system to facilitate the installation of Agda.

  The VS Code extension also has integration with the Agda Language Server (ALS). It is a language server for Agda created by the same author as the VS Code extension. The implementation currently only contains a hover functionality that shows the type of a term once the file has successfully been type-checked.
- Recently, a new VS Code extension for Agda has been released by Benjamin Driscoll#footnote(link("https://github.com/willtunnels/agda2-vscode")). This extension is written in Typescript -- the native language of the VS Code APIs. The functionality of this extension is mostly the same as the banacorn's VS Code extension, apart from some bug fixes and user interface changes.

== Meta-programming

Meta-programming refers to the process of writing programs that modify or generate other programs. In this thesis we focus on static meta-programming, that is, meta-programs that are evaluated at compile-time to produce syntax trees. These syntax trees are typically spliced into the current program. @metaprogramming-example shows a contrived example meta-program in Agda. The meta-program on the left builds up the syntax tree for an identity function, which can be spliced in using `unquote` as seen on the right.

#figure(caption: [Example of a meta-program in Agda. The function on the left defines how to build up the term for the identity function, the function on the right uses the meta-program to define the identity function.], grid(columns: (1fr, 1fr), gutter: 16pt)[
  ```agda
  mk-Id : TC Term
  mk-Id = returnTC
    (lam hidden
      (abs "A"
        (lam visible
          (abs "x"
            (var 0 [])))))
  ```
][#align(horizon)[
  ```agda
  id : {A : Set} → A → A
  id = unquote mk-Id
  -- Expands to the following
  -- at type-checking time
  id = λ {A} x → x
  ```
]
]) <metaprogramming-example>

=== In Idris1

#grid(columns: (1fr, 1fr), gutter: 8pt)[
Idris1 has static meta-programming @christiansen2016elaborator. Terms can be quoted, which converts the term to a Idris1 data type representing Idris1 terms. The data type for representing terms is called `TT` (@tt-def). This data type also has a constructor for binders, which can create let bindings to introduce new variables. There is also an inverse of quotation, called unquotation. The term `%runElab m`, where `m : Elab TT`, evaluates the meta-program. The term of type `TT` that is computed is converted back into a unquoted Idris1 expression, and spliced into the current program.

Meta-programs in Idris1 are written using an embedded domain specific language (EDSL). Functions in the reflection API update the "proof" state, which consists of among others, the hole queue and the incrementally built proof term. These functions are defined within the compiler and have the ability to invoke internal function in the type-checker. For example, the `fill` function used in @idris1-meta-example places another quoted expression in the first hole of the hole queue and unifies its type with the expected type of the hole. If this fails, the compiler presents the user with a type error.
][
#stack(spacing: 32pt)[
#figure(caption: [A snippet of the definition of the `Binder` and `TT` data types in Idris1. These are used to represent Idris1 terms and are the result of quoting regular Idris1 expressions.])[
```Idris1
data Binder
  : Type -> Type where
  Let (ty, val : a) -> Binder a
  ...
data TT = Bind TTName (Binder TT) TT
        | TConst Const
        | ...
```
] <tt-def>
][
#figure(caption: [An example taken from @christiansen2016elaborator. It demonstrates how to build up the expression `Z + S Z` using the meta-programming monad.])[
```Idris1
do
  [x, y] <- apply `(plus) [False, False]
  solve
  focus x; fill `(Z); solve
  focus y; fill `(S Z); solve
```
] <idris1-meta-example>
]
]

=== In Agda <agda-metaprogramming>

Similar to Idris1, Agda also has static meta-programming. Agda has data types for terms, clauses and definitions, among others. The `Term` data type reflects the structure of elaborated terms in Agda. For example, let and where bindings cannot be inspected or generated using meta-programming because they are already substituted during elaboration.

Meta-programs are written in the `TC` monad, which is defined within the compiler. This monad keeps tracks of, for example, the environment, and the meta-variable state. The reflection API that Agda exposes defines a number of primitive functions that all operate in the `TC` monad.

=== In Lean4 <lean4-meta>

Lean4 is another dependently-typed language and interactive theorem prover @lean4. The language allows meta-progamming in different ways:
- In Lean4, all top-level statements, including `def`, `inductive` are called commands. Besides these builtin commands, the user has the ability to define their own commands. The definition of a command includes a metaprogram of type `Syntax → CommandElabM Unit`. The function receives the abstract syntax tree of the argument to the command, and must produce some side effects, which include updating or querying the environment or performing `IO` operations. @lean-command illustrates these components using the `check` command as an example.
  #figure(caption: [An example command in Lean4, and how Lean4 calls the metaprogram associated with the command.], image("lean-command.png", width: 50%))
  // [
  // ```lean
  // #check 2 + 2
  // -- The syntax for "2 + 2" is the argument to the metaprogram.
  // -- The side effects are:
  // -- * the type of the term represented by the syntax is inferred, which is Nat;
  // -- * and "2 + 2 : Nat" is written to the infoview.
  // ```
  <lean-command>
- Macros can access the environment and the local meta-variables. Macros are very limited in terms of functionality, and can only be used to define syntactic sugars.
- Tactics can access the environment, local meta-variables and the proof state. The functionality of a tactic is defined using the `TacticM` monad, which expands directly upon the `TermElabM` monad. Custom tactics act like macros, but can be used to inspect and change the proof state in a tactic-based proof.

A meta-program in Lean4 looks similar to one in Agda, where you can call functions in a monadic non-tactic style. Whereas Agda only allows functions to be called from the reflection API, the Lean4 compiler allows meta-programs to directly call any function defined in the compiler, since it is written in Lean itself. This means that meta-programs in Lean4 can use any part of Lean4's type checker.

Lean4 also has extensible user interface inspired by Korkut et al. @extensible-editor, which allows user to execute meta-programs at edit-time and display their results in a visualisation in the infoview @proofwidgets. Widgets consist of a React component that is used to render in the info view. React#footnote(link("https://react.dev/")) is a popular web framework for Javascript, which is used to implement `lean4-vscode`'s info view. The component can call meta-programs using special hooks provided by the `lean4-vscode` info view API.

For example, @proofwidget-demo shows an alternative implementation for the `#check` command, where the user can type an expression in the infoview (on the right), after which the type of the expression is inferred and displayed. When the user puts their cursor on a `#widget` command in the source file, the `lean4-vscode` extension loads the widget's React code into the infoview.

#figure(caption: [One of the example widgets defined on the Lean4 widgets documentation page#footnote(link("https://lean-lang.org/examples/1900-1-1-widgets/")). The widget allows the user to enter an expression in the infoview and its inferred type is displayed.], image("proofwidget.png")) <proofwidget-demo>

#pagebreak()

= Building Avea <building-avea>

One result of this thesis is Avea: a Visual Studio Code extension written in Agda -- which compiles to Javascript -- that supports the same set of features other Agda extensions also have. This chapter will discuss its implementation, and highlight some design decisions.

Avea acts as the mediator between Agda and VS Code. Agda exposes an process-based API with which Avea communicates, and Avea communicates with VS Code through the use of their Javascript API. @high-level-arch shows the high-level architecture of the extension and how the different parties communicate with each other.

#figure(caption: [Communication patterns within the high-level architecture of the extension.])[
  #image("overview.png", width: 100%)
]<high-level-arch>

In order, the extension operates as follows:

+ The user makes an edit in the buffer in VS Code or triggers an action using a particular keybinding.
+ VS Code listens for keybindings configured by the extension -- as discussed in @activation -- and invokes the handler that is registered in the extension.
+ In the handler, the extension defines what to send to the Agda process -- which typically includes which file the interactions works on, and how Agda should respond -- and awaits the response. This is discussed in @sending-interactions.
+ Agda responds with many different responses to the interaction that was sent. Responses can contain new highlighting tokens, information about the progress of type-checking, or formatted errors and warnings.
+ Each response is decoded into Javascript objects. Each of the parsed responses is then handled individually. This typically involves updating the internal caches, or updating VS Code's editor buffer. @receiving-handling goes into how this is done.
+ After the caches are updated, the extension updates the editor or updates the display buffer via the VS Code API.

== Running a Visual Studio Code extension <activation>

// A Visual Studio Code extension should be written in Javascript. The package.json file lists the dependencies and the entry point file. The entry point file should contain two exported functions: an `activate` function and a `deactivate` function. The activate function is called once when the extension's configured activation events is triggered. For Avea specifically, it is configured to activate the extension once an Agda file is opened by the user.

VS Code provides ways to run your extension both in debug mode as in production mode. The debug mode can be triggered from VS Code's debug menu, which opens a new window with the extension loaded into it. To publish an extension for use in production, VS Code has a tool called `vsce`, which can package all the files needed to run the extension into a compressed binary VSIX file. This file is then published to the marketplaces.

One issue is that `vsce` only packages the files you tell it to package. Additionally, even though the `vsce` utitily already compresses the extension files, VS Code recommends to keep the source code for the extension itself as small as possible. Following these guidelines, we cannot use put the `node_modules` folder -- the folder containing all dependencies, both runtime and buildtime -- in the extension package. For Avea, this folder can easily grow as large as a hundred megabytes, most of which is dedicated to build time tools. To remove the build time dependencies in the package, Avea uses another tool called `esbuild` -- a bundler for Javascript -- to combine the generated Javascript source code by Agda with the source code of just the runtime dependencies in `node_modules`. @js-infra shows a diagram of how the tools call each other.

#figure(caption: [A high-level overview of the infrastructure required to run Avea, both in debug and production mode.], image("js-infra.png", width: 80%)) <js-infra>

Once the extension is loaded -- either in a debug window or using the production extension package -- the code in the entry file is executed. The entry file sets up the dependencies -- discussed in more detail in @libraries -- and then calls Avea's activation function. This activation function has two purposes: it creates all of the resources that need to be created in an `IO` context, and it registers all of the handlers for keybindings, commands, the hover provider, the semantic token provider and the defintion provider. The `activate` function serves a very similar purpose as the `main` function does in regular Agda programs, where all `IO` operations have to happen in `activate` or a function called from there.

// The handlers for the keybindings and commands keep listening until they are explicitly deactivated. It is the extension's responsibility to shut them down every time a long-running event handler or process is started. When creating handlers for events in the VS Code API, they return a `Disposable`. `Disposable`s can be registered in the extension's context object so that VS Code will dispose of them at _deactivation_. Deactivation happens just before the extension should no longer be active, for example, when a non-Agda file is opened, or the extension is uninstalled or disabled.

== Sending interactions <sending-interactions>

// #figure(caption: [Implementation of the handler for the `make-case` command in Avea's `activate` function. It sends an interaction to the Agda process containing the current file and the location of the goal under the cursor.])[
// ```agda
// register-command "avea.make-case" $ do
//   model ← IO.Ref.get model-ref
//   just intr ← AgdaInteraction.under-cursor-command model AgdaCommand.make-case
//     where _ → pure tt
//   AgdaProcess.send-command output-chan intr agda
// ```
// ] <command-register>

// Using the implementation of the make-case command in Avea shown in @command-register as an example, a command registration consists of 3 parts:
// + The `register-command` (line 1) function calls the VS Code API to register a new handler under a given name.
// + In the `package.json` file, it should be declared what keybindings or commands should call the handler by name.
// + In the handler, we define what the keybinding or command should actually do. Depending on the kind of command, the handler does the following:
//   - If the command only updates the internal cache (called `model-ref` in @command-register), or needs to communicate to VS Code, then the handler can use the API directly.
//   - If the command needs to interact with Agda, then an AgdaInteraction should be created and this can be sent to the Agda process (line 3-5). The handling of an Agda interaction is done in Response modules (described in more detail in @receiving-handling).

To send an interaction to Agda, a child process must be set up first. Avea makes sure to have one child process running at all times, so that Agda can keep its internal state about, for example, previously loaded modules. To start and manage the process, the following steps are involved:
+ Before the process is spawned, Avea needs to read the settings via the VS Code API, to read the path to the currently activated Agda binary. // The user can configure multiple paths to different Agda binaries, which can be selected using a keybinding within Avea. For each of the binaries, the version is requested, which is used for display and to check whether the binary exists. When the user selects one of the binaries, the Agda path setting is set to that path, which is used when spawning the child process.
+ A child process is spawned running Agda's `--interaction-json` mode.
+ Once the process is spawned, Avea attaches different handlers. A data handler receives the output from the Agda process, which does the parsing and processing (detailed in @receiving-handling). An error handler listens for unexpected closes of the process. This handler reports the error to the user, with the ability to restart the process.

#figure(caption: [High-level diagram of all systems involved with the Agda process. It expects serialised interactions as input via stdin, and outputs responses to a configured data handler. The process manager makes sure the correct binary is started, and stopped or restarted when the user requests it.], image("process-management.png", width: 60%)) <process-management>

When a user invokes a command that needs to communicate with the Agda compiler, the first step is to create an interaction. Interactions are encoded as stringified Haskell expressions that contain the file that is currently opened and a command. The command can also take arguments, which determines the level of normalisation, for example. @example-interaction shows how a stringified interaction looks like.

#figure(caption: [Example of a stringified interaction sent to the Agda process when a file is loaded with `C-c C-l`.])[```haskell
IOTCM
  "/.../Avea/Extension.agda"                -- Path to the current file
  NonInteractive Direct                     -- How should Agda respond
  (Cmd_load "/.../Avea/Extension.agda" [])  -- The command
```] <example-interaction>

// #figure(caption: [Definitions of `AgdaInteraction.t` and `AgdaCommand.t`. These are used to encode interactions that need to be sent to Agda.])[
//   #grid(columns: (1fr, 1fr), column-gutter: 8pt)[
//     #codly(display-icon: false, display-name: false)
//     ```agda
//     module AgdaInteraction where
//       record t : Set where
//         constructor iotcm
//         field
//           file : TextDocument.t
//           command : AgdaCommand.t
//     ```
//     #codly(display-icon: true, display-name: true)
//   ][
//     ```agda
//     module AgdaCommand where
//       data t : Set where
//         load : t
//         give refine-or-intro
//           : Bool → InteractionPoint.t → t
//         {- Other commands are elided -}
//     ```
//   ]
// ]

// The `AgdaInteraction.t` and `AgdaCommand.t` data types mirror the Haskell definitions in the Agda compiler. These data types describe what commands are available to run and what information is required to run them. They have serialisation functions that generate the stringified Haskell expressions that evaluate to the Haskell version of the data types. The Agda interaction mode uses some `Read` instances to read the string into the data type.

// An `AgdaInteraction.t` is created through the use of two functions: `from-AgdaCommand` or `under-cursor-command`. `from-AgdaCommand` creates an interaction from a complete `AgdaCommand.t`, and `under-cursor-command` is a specialisation of `from-AgdaCommand` that uses the model and the cursor position to determine the goal under the cursor and pass that to a partially applied `AgdaCommand.t`.

== Receiving and handling responses <receiving-handling>

// The extension relies on the Agda compiler's interaction mode. This mode has two response formats: Emacs Lisp -- which was initially made for the Emacs-mode -- and JSON designed for non Emacs-Lisp extensions. Given that Javascript has a builtin function for parsing JSON, which the extension can make great use of during the prototyping phase, the extension uses the JSON-based interaction mode.

// Below we will describe how the "load file" command is handled as an example of how interactions with the interaction mode go. Given this is the only command the extension currently supports, it showcases well how all of the components in the architecture work.

// #grid(columns: (40%, 60%), gutter: 16pt, [
//   The user has to initiate interactions with the extension. That is, the extension is idle as long as the user does not issue any commands. Once the user uses the `C-c C-l` keybind, the extension receives a message and immediately issues the `Cmd_load` command to the Agda compiler.
  
//   The Agda compiler initially responds with messages for clearing the token cache the extension internally keeps track of, empty the display buffer, and clear the status bar items.
  
//   After the initial messages, the compiler sends updates while it is type-checking the requested module and its dependencies. The `RunningInfo` message appends new lines to the display buffer. The `DisplayInfo` message replaces the display buffer's content completely.

//   Once the compiler finishes type-checking, it responds either with error messages, or with highlighting info. The error message redirects the user's cursor to the line where the error occurs, and set the error in the display buffer. The highlighting message contains a list of tokens and their semantic token type, as well as information of definition sites which can be used in the go-to-definition feature.

//   The extension notifies Visual Studio Code that there is new highlighting information, and Visual Studio Code sends a token request to which the extension responds with the newly retrieved information. When the user edits the buffer, Visual Studio Code requests new token information, even though the compiler has not provided any new tokens.
// ], [
//   #figure(image("load.png"), caption: [Initial requests and responses when the user issues the "load file" command.])
//   #figure(image("webview.png"), caption: [The responses from the Agda compiler updating the display buffer.])
//   #figure(image("highlighting.png"), caption: [When the file type-checks, the compiler responds with highlighting information. When the user edits the buffer, Visual Studio Code requests new tokens.])
// ])

Once we have an `AgdaInteraction.t`, Avea sends it to the Agda process. Agda responds with many JSON messages delimited by newlines per interaction. The child process data handler receives buffers of data from the standard output. These buffers may contain parts of the responses for an interaction, or multiple interactions even. Additionally, the last response might not even be complete too. The data handler therefore has the task to collect as many complete responses, and handle them. @unbuffering shows the steps in this process.

#figure(caption: [The "unbuffering" of Agda's responses: Avea parses as many responses as possible and any unparsed responses are prepended to newly received buffers.], image("unbuffering.png")) <unbuffering>

After the data handler has collected a number of responses and parsed them to JSON, it remains to parse the JSON responses to specific data types which have more specific information about the response type. These data types can be passed to a handler which calls the relevant functions from the VS Code API. // @handle-agda-message shows how the handlers are called from the JSON parsers: each decoder function parses their corresponding kind of response and passes a data type to the handler function.

// #figure(caption: [JSON decoder for the responses Agda sends. The handlers receive the current model and return an updated model.])[
// ```agda
// handle-agda-message : (AgdaInteraction.t → IO ⊤) → Ref.t Model → Model
//                     → Decoder (IO Model)
// handle-agda-message send-command model-ref model =
//   (| (handle-highlighting-info model) highlighting-info-decoder
//    | (handle-interaction-points model) interaction-points-decoder
//    | (handle-give-action send-command model) give-action-decoder
//    | ...
//    |)
// ```
// ] <handle-agda-message>

Each handler may cause edits to the buffer or perform other asynchronous actions. However, if the handlers are invoked immediately from the data handler, then there is no guarantee that the actions are executed in a deterministic order. This is because each handler acts as separate thread, which can introduce a number of concurrency problems.  To mitigate these concurrency problems, Avea uses a queue to make sure only one response is handled at a time. This prevents edits from being made in the wrong order, or two edits being made at the same time, causing VS Code to throw an error.

This section will continue to describe how the handlers for three response types work to illustrate what response handlers do, and the constraints they are subject to.

#heading(numbering: none, depth: 4)[Handling highlighting information] <highlighting-handling-section>

The highlighting information response contains semantic tokens. The tokens are sorted according to their positions in the source file, and then set in the internal cache. The internal cache keeps track of the latest tokens and interactions points per file. The sorting is important for the change handler to be able to efficiently search through the tokens, as will be described in @change-responses.

#figure(caption: [Diagram describing the handling of highlighting tokens. The user can request new highlighting either by making edits in the buffer (red path) or by invoking the load interaction (blue path). Avea can supply highlighting tokens on VS Code's request via the tokens handler.], image("highlighting-handling.png", width: 60%)) <highlighting-handling>

Once the tokens are updated in the internal cache, the handler will send a notification to VS Code for it to retrieve new tokens. VS Code will also automatically request new semantic tokens after a small batch of edits are made.

When VS Code requests new semantic tokens, the tokens handler registered in the `activate` function will fire. This handler simply looks for the saved tokens in the internal cache, and return semantic tokens for the tokens, and editor highlighting for errors, warnings, and interaction points. Errors and warnings are typically displayed as a change in background behind the code it applies to. For this reason, Avea has to apply editor highlighting separately for those tokens, because semantic tokens cannot be used to control the background of a piece of text.

#heading(numbering: none, depth: 4)[Handling updates to interaction points]

The interaction points response is included as a response to any interaction that can change the size or number of interactions points. Common interactions that returns interactions points are give (`ctrl+c ctrl+spc`), refine (`ctrl+c ctrl+r`) and load (`ctrl+c ctrl+l`). // However, the interaction points each interaction returns can vary. In particular, newly introduced question marks by the refine command have invalid source locations (0-wide), and therefore have to be discarded.
Agda sends this response to let Avea know where the latest interaction points are. Each interaction point has an id and source locations of their start and end. The id can be used to refer to a specific interaction point in subsequent interactions. The source locations are used to highlight the interaction point, and to retrieve the expression contained within. Avea keeps track of interaction points in its own local cache, and the main purpose for the interaction points handler is to update this cache with the latest information from Agda.

These interaction points can come in two kinds:
- Question marks are one character wide interaction points. The user can place a question mark in an expression to initiate a hole. It is the extension's responsibility to expand the question mark into hole, as illustrated in @hole-expansion. It is therefore convenient that Agda includes question marks in the interaction points response, since these can be filtered out and expanded in the buffer. 

#figure(caption: [Illustration of question mark expansion: when the user types a question mark in an expression (left image), Agda will signify using an interaction points response where the question marks are, so that Avea can expand it in the buffer to a hole (right image).], grid(columns: (auto, auto), gutter: 16pt, image("expand1.png"), image("expand2.png"))) <hole-expansion>

- Holes are interaction points that are at least four characters wide. Holes contain a potentially incomplete expression, which is delimited by goal markers `{!` and `!}`. The location of these can be put into the cache without additional processing. // The expression in the hole need not be a valid Agda expression, both in terms of syntax or in terms of type. Other interactions can operate on the hole, by inspecting the inner expression. Interactions operating on holes require the latest content in them, since Agda does not actively keep track of a hole's contents.


// After discarding, the question marks are filtered out and are expanded. Expansion involves updating the local cache that saves the location of the start and end markers of holes, as well as replacing the question mark with goal markers (`{!  !}`) in the buffer, and horizontally shifting the position any interactions points on the same line in the buffer.

#heading(numbering: none, depth: 4)[Handling give actions]

// #grid(columns: (50%, 46%), gutter: 16pt)[
  This response is specific to the give and refine interactions. It contains a give result -- which is either a new expression, or the expression in the goal is parenthesised, or the expression is let as-is. // See @give-result for the definition in Avea.
// ][
//   #align(horizon, [#figure(caption: [Definition of the `GiveResult.t` data type, which describes how a give action should replace its associated hole.])[```agda
//   module GiveResult where
//     data t : Set where
//       parens no-parens : t
//       str : String → t
//   ```]<give-result>])
// ]
This handler performs the following steps:
  + Depending on the give result, the handler queries the VS Code buffer to retrieve the contents of the hole.
  + The replacement expression may also contain new interaction points, which the handler needs to expand. Agda gives the new interaction points in a separate in interaction points response, which is not accessible from the handler of the give action response. However, even if it was available in the give action response, Agda returns incomplete information about the newly inserted question marks.

    This requires Avea to do a manual search through the give result for expandable question marks, and replace those in the expression string to empty holes. The algorithm for this makes use of regex search to categorise parts of an expression within which a question mark should not be expanded. In particular, question marks that are part of identifiers, appear within a string, or appear within comments should not be expanded, as illustrated in @difficult-expansion. 

    #figure(caption: [Expansion of question marks after a refine interaction. The left image is before the refinement, the right image shows that only the first question mark is expanded.], grid(columns: (auto, auto), gutter: 16pt, image("difficult-expansion1.png"), image("difficult-expansion2.png"))) <difficult-expansion>
  + All expansions are collected into a list of edits that are made to the VS Code buffer. // Additionally, if any expansion have been performed, the cursor is moved to the first new hole, to improve developer experience. 
  + A load interaction is issued. This means that the internal cache need not be updated since the load interaction will elicit an interation points response that contains the most up-to-date locations of the just expanded interaction points.

== Reacting to changes from the user <change-responses>

// As mentioned earlier, Agda responds with a list of semantic tokens as a response to some interactions. A semantic token consists of a start and end location, as well as, what Agda calls _primary_ and _secondary aspects_. Primary aspects are used to display the function of a token to the user. For example, variables with function types are coloured blue, whereas variables of type `Set` are coloured yellow. Secondary aspects contain additional information about tokens, for example, whether the token's usage causes an error or warning, or whether a it is part of a pattern that is non-exhaustive.

The semantic tokens provider is queried by VS Code, every time an edit has been made or when Avea requests VS Code to request new tokens (after a `C-c C-l`, for example). VS Code requests new tokens after edits, since there could be new tokens, or old tokens could have been invalidated. However, since Avea only receives the most up to date highlighting information after a load command, it needs to update the positions of the tokens it has in cache to provide the most accurate highlighting. Additionally, if the edits replace (parts of) tokens with new content, then tokens should be removed from the cache completely. @shift-highlighting shows the difference between not shifting and shifting the tokens.

// The semantic tokens provider is queried by VS Code whenever the user has edited a buffer. Though, what has changed is not communicated to the semantic tokens handler: that needs external listeners to receive updates. The reason these edits are needed in the first place is that Avea saves the locations of all tokens and interaction points. However, when the user edits the buffer these locations might change. Sending the same locations for all tokens will result in pieces of code being highlighted with wrong or incomplete information, for example, identifiers with two colours or missing colours, see @shift-highlighting.

#figure(caption: [Illustration of syntax highlighting in Avea: the left image is a loaded file. The middle image shows an edited buffer when no shifting is performed, whereas the right image shows the same edited file with shifting enabled.], grid(columns: (1fr, 1fr, 1fr), gutter: 16pt, image("pre-highlighting.png"), align(horizon, image("no-shift-highlighting.png")), align(horizon, image("shift-highlighting.png")))) <shift-highlighting>

Initially, Avea stored the tokens as Agda gives them. This means that no processing needs to be done when receiving the tokens, but shifting the tokens requires iterating over the entire list. Typically, a buffer is edited more times than it is loaded, so this approach can cause visual slow downs if the buffer has a large number of tokens. Another approach, which Avea uses now, is to store the tokens in sorted order. This means that the received tokens after loading need to be sorted in $cal(O)(n log(n))$ time. However, this means that after edits, Avea can find the first token that needs to be shifted using binary search in $cal(O)(log(n))$ time. After finding the first affected token, the change handler shifts the remaining tokens until the end of the line. The key observation is that only tokens on the same line after the edit need to be shifted. This prevents the visual slow downs while editing, at the cost of making the load times slightly longer.

== Input mode <input-mode>

The input mode is one component of the extension that operates completely separately from the compiler. In fact, the input mode could even run as its own extension, since it shares no resources with the rest of Avea: it does not require access to Avea's internal caches.

Avea is bundled with a file containing a mapping from character sequences to their corresponding unicode characters. This mapping is saved in a trie structure. A trie, or prefix tree, is a search tree where each edge defines a character in the prefix of the search string. At activation, Avea converts the trie into a trie zipper, which is a trie with a focus on one node (indicated by the orange arrow in @input-mode-state). When the user types a character the focus changes to a node downwards, or when the user hits backspace, the focus moves upwards. When a character sequence has multiple associated unicode characters, the arrow keys move the focus in a list zipper to left or right.

While the user is typing characters, the trie is traversed until no character matches anymore. Then the sequence of characters is replaced in the buffer by the unicode character under focus, and the input mode stops listening for new characters. @input-mode-state illustrates what happens to the trie zipper as the user interacts with the input mode.

#figure(caption: [The changes to the input mode's trie zipper as the user types characters.], image("input-mode-state.png", width: 80%)) <input-mode-state>

The reason for using a trie zipper is that zipper structures are easy to implement for traversing a tree-like structure up and down in a functional language. In imperative languages, a tree can be defined using pointers, but since these are not available in Agda, a tree zipper must instead be used.

#pagebreak()

= Challenges with programming in Agda <challenges>

To be able to answer the first research question "Is Agda a suitable language to write practical programs with?", we have to reflect on some of the major challenges we faced during Avea's development. In this chapter, we will discuss those challenges, and the solutions we have applied in Avea. We will also generalise these solutions to other types of programs, and use that as an argument to answer the first research question.

== Importing Javascript libraries <libraries>

Avea uses some external Javascript libraries that need to be imported, in order to function. Usually in Javascript, the `import` statement is used to import libraries. However, the current release of the Agda compiler does not provide a way to import Javascript libraries. Instead, Avea relies on a separate Javascript file to set the dependencies in a global variable available across all modules, and then call the `activate` function, as shown in @entry-js.

#figure(caption: [A Javascript file importing libraries and making them globally available before running the Agda code.])[
  ```javascript
  import Main from "./jAgda.Avea.Extension.mjs";
  import * as vscode from "vscode";
  
  export function activate() {
    Object.assignProperty(globalThis, "AveaImports", {
      value: { vscode, /* and some other libraries */ }
    });
    Main(); // Call the main function from the extension manually
  }
  ```
]<entry-js>

While this approach works in the current version of Agda, it must be noted that it is not fully safe to use everywhere. To illustrate, the code in @imports-toplevel-error below throws an error at runtime. This is because the evaluation of `imported-string` for the value of `s` happens before the `activate` function is called. This means that `AveaImports` is not defined when `imported-string` is evaluated, and therefore `someString` cannot be accessed, throwing a runtime error.

#figure(caption: [Illustration of using `AveaImports` at the top-level, which causes runtime errors.])[
```agda
postulate imported-string : String
{-# COMPILE JS imported-string = AveaImports.someString #-}
s = imported-string <> "!"
```
]<imports-toplevel-error>

This issue can be solved by wrapping `imported-string` into `IO` as illustrated in @import-toplevel-io. This delays the evaluation of `AveaImports` until it can be used, which, in the extension, is guaranteed to be after `AveaImports` is defined. Even though this approach works, it only allows top-level definitions to be used in effectful functions, even if the values themselves might be pure. This leads to unnecessary colouring of functions to be `IO`, or passing the top-level definitions as parameters to functions that need them, undermining the use of the top-level definition.

#figure(caption: [Using `AveaImports` at the top-level without causing runtime errors by delaying the access to `someString` through the use of `IO`.])[
```agda
postulate imported-string : IO String
{-# COMPILE JS imported-string = async () => AveaImports.someString #-}
s = fmap (_<> "!") imported-string
```
]<import-toplevel-io>

A similar issue has already been solved for the Haskell backend through the `FOREIGN GHC` pragma. The `FOREIGN GHC` pragma allows the user to insert arbitrary code at the top of the output files. However, the Javascript version of this pragma, `FOREIGN JS`, is still unimplemented at the time of writing.  Implementing the `FOREIGN JS` pragma requires very few changes to the Agda compiler, and we created a fork of the Agda compiler that includes support for the pragma#footnote(link("https://github.com/agda/agda/issues/8429")). An example use of the pragma is shown in @foreign-js.

#figure(caption: [Using the `FOREIGN JS` and `COMPILE JS` pragmas to import a variable from a Javascript library.])[
  ```agda
  {-# FOREIGN JS import { someString } from "library" #-}
  postulate imported-string : String
  {-# COMPILE JS imported-string = someString #-}
  s = imported-string <> "!"
  ```
]<foreign-js>

The `FOREIGN JS` pragma allows the modules to import their Javascript dependencies without requiring a separate file to bind them to the global scope, and allows these dependencies to be used at the top-level without requiring `IO`. This is because it allows the import of `someString` in the same file where the `imported-string` variable is defined. Given that the `FOREIGN JS` is placed before `imported-string` is used, `someString` can be correctly resolved, and the code runs without any errors. Unfortunately, since the implementation of the `FOREIGN JS` pragma has not been finalised and released yet, Avea still makes use of the imports object approach.
  
== Handling asynchronicity <async>

By default Agda code compiled to Javascript expects IO operations to use continuation-passing style, though the builtin module does not provide the monadic operations: `pure` and `_>>=_`. When compiling, the Agda compiler looks for a `main` function, and if it exists, it inserts `main(() => {})` at the end of the file. The standard library author, therefore, has a choice how to implement these functions as long as calling the function starts the `IO` operation.

Initially, the extension made use of continuation-passing style for `IO` (provided by the Iepje library#footnote(link("https://github.com/lawcho/iepje"))). However, the VS Code API exposes some functions that return promises: a type that modern Javascript uses to handle asynchronous computations. A promise represents a computation that has already started and will return a value in the future, an example of which can be found in @promise.

#figure(
  caption: "Example function that uses promises that delay a computation and waits for the computation to finish to print the result."
)[
  ```js
  const delay = (time, f) => new Promise((resolve, reject) =>
    setTimeout(
      () => resolve(f()),
      time
    ));
  delay(1000, () => 10).then(n => console.log(n)); // Prints 10 after 1 second
  ```
]<promise>
  
To be able to use these functions from the VS Code API, Avea requires a different definition for `IO`, where instead of compiling to continuation passing style, we use lazy promises. Using just promises for the `IO` monad -- with the `new` constructor as `pure`, and `.then` for `_>>=_` -- means that any term of type `IO A` has already started executing. Since Avea's implementation makes abundant use of "lazy" `IO`, where storing the `IO` action does not mean it has already started executing, we have decided to define `IO` as functions of Typescript type `<T>() => Promise<T>`.

However, in order to avoid stack overflows when, for example, traversing large lists with the `IO` monad, we need to make use of the syntax sugar that Javascript has for promises: `async`/`await`. As seen in @bind, an implementation with `async`/`await` is a little more verbose, but reduces the stack depth of nested `IO` operations compared to using `.then` directly -- which adds a stack frame every time it is called.

#figure(
  caption: [Juxtaposition of an implementation of `_>>=_` with stack depth linear to the nesting depth of the `_>>=_` operations (left), and an implementation with stack depth linear to the number of evaluated `_>>=_` calls (right).]
)[
  #columns(2)[
    #codly(display-icon: false, display-name: false)
    ```js
    ma => f => async () => {
      const a = await ma();
      return await f(a)();
    }
    ```
    #codly(display-icon: true, display-name: true)
    #colbreak()
    #v(16pt)
    ```js
    ma => f => () =>
      ma().then(a => f(a)())
    ```
  ]
]<bind>

While Avea's definition of `IO` works, it could still be generalised. Instead of defining all `IO` to be asynchronous, it is possible to subdivide `IO` into `SyncIO` and `AsyncIO`. `SyncIO` would be `IO` using the continuation passing style, only allowing synchronous operations. `AsyncIO` would use promises. This means that any `SyncIO` operation could be lifted to a `AsyncIO` operation quite trivially. Conversely, the concurrent queue used to force sequential evaluation of `AsyncIO` operations could be seen as a way to run `AsyncIO` actions in a `SyncIO` environment.

// === Passing messages to the webview safely <webview-messages>

// As mentioned in @vscode, Visual Studio Code has the ability to open a panel in which any webpage can be displayed. Internally, Visual Studio Code has a wrapper API around an `iframe` HTML element. This API includes the ability to send and receive messages between the webview and the extension. There is one caveat mentioned in the documentation of Visual Studio Code: the objects sent to and from the webview must be JSON-serialisable#footnote(link("https://code.visualstudio.com/api/extension-guides/webview#passing-messages-from-an-extension-to-a-webview")). This means that only objects that can be serialised to and deserialised from JSON can be passed. Even though this limitation is not statically enforced by Visual Studio Code's Typescript API, it can be enforced in the Agda API as shown in @cloneable.

// #figure(caption: [Encoding of the JSON-serialisable property in Agda: a type is JSON-serialisable when it can be encoded to and decoded from JSON, and the data is unchanged after encoding and decoding it.])[
//   #columns(2)[
//     #codly(display-icon: false, display-name: false)
//     ```agda
//     -- Class of JSON-serialisable types
//     record Cloneable (A : Set)
//       : Set where field
//         encode : A → JSON 
//         decode : JSON → Maybe A
//         encode-decode-dual : ∀ a →
//           decode (encode a) ≡ just a
//     ```
//     #codly(display-icon: true, display-name: true)
//     #colbreak()
//     ```agda
//     data JSON : Set where
//       j-null : JSON
//       j-string : string → JSON
//       j-bool : boolean → JSON
//       j-number : number → JSON
//       j-array : List JSON → JSON
//       j-object : StringMap.t JSON → JSON
//     ```
//   ]
// ]<cloneable>

// The `JSON` data type has a custom foreign function interface, where each constructor of the data type is represented by its JSON primitive in the Javascript runtime. This means that any term of type `JSON` can be passed as a message to a webview, and as such anything that can be serialised (via `encode`) and deserialised (via `decode`) correctly (formulated as `encode-decode-dual`) to and from `JSON` can also be passed using these functions.

// What remains is to use this type class in the `Panel` foreign function interface, as shown in @panel. The `Panel` type becomes polymorphic over the message type in Agda, and when creating an instance (via `create`), it is required that the message type is `Cloneable`. It is worth pointing out that in the Visual Studio Code documentation the `Webview` type (the type `Panel` is modelled after) is not polymorphic and any object is allowed to be passed, resulting in unexpected data at the receiving end#footnote(link("https://code.visualstudio.com/api/references/vscode-api#2438")).

// #figure(
//   caption: [Using polymorphism and the `Cloneable` type class to ensure messages are JSON-serialisable -- a constraint that is not enforced statically by the Typescript API.]
// )[
//   ```agda
//   module Panel where
//     postulate t : Set → Set
//     create : { A : Set } {{ Cloneable A }} → String → String
//            → ShowOptions.t → WebviewOptions.t → IO (t A)
//     send-message : { A : Set } {{ Cloneable A }} → t A → A → IO ⊤
//   ```
// ]<panel>

== Mitigating stack overflows <stack-overflow>

The Agda compiler does not support tail-call optimisation by itself. Compilation of Agda programs to Haskell is usually faithful enough that tail-call recursive programs in Agda are also tail-call recursive in Haskell. GHC can then do its tail-call optimisation, and by extension, the Agda can use tail-call recursion without stack overflows.

However, most major Javascript engines do not support tail-call optimisation. Since recursion is the only method of traversing a data structure in pure Agda, this means that the stack size determines how deep we can traverse a data structure in one pass. For Avea's implementation this poses a serious problem, since the responses from Agda containing the highlighting tokens grow linearly with the size of the source file that is being checked. For relatively small source files, we already run into the stack limit.

To mitigate this, we need to use the JavaScript FFI to define "stack-safe" functions that can traverse large data structures without increasing the stack depth per element. Agda allows us to provide a definition that is used by the type-checker, and another separate one that is used in the compiled output. This means we retain the ability to reason over the functions, as well as removing the worries about the stack depth.

#figure(
  caption: [The implementation of the `reduce-right` function both for Agda's elaborator and for the compiled output. The Javascript definition offers stack-safety.]
)[
```agda
reduce-right : B → (B → A → B) → List A → B
reduce-right b f [] = b
reduce-right b f (x ∷ xs) = f (reduce-right b f xs) x

{-# COMPILE JS reduce-right = a => A => b => B => b => f => xs =>
  xs.reduceRight((ac, e) => f(ac)(e), b) #-}
```
]

While this method does resolve stack-safety issues, we do have another problem. Agda takes the `COMPILE JS` pragma and inserts it unchecked in the compiled output. Therefore, there is no guarantee that the definition in the pragma adheres to the type declaration, and that the pragma definition has the same semantics as the Agda definition.

A pragmatic solution to this "consistency checking" problem is to create a separate program that does the following:
1. For each test case, the program requests a fully qualified function name, and test inputs for each relevant parameter. The program will compile the library and find the correct Javascript definition in the compiled output.
  #figure()[
    ```coffee
    run_consistency_tests
      name: "Data.List.map"
      inputs: cartesian_product test_functions, test_lists
      erased_params: 4
      meta_information: "{A = Nat} {B = Nat}"
    ```
  ]
2. The given inputs are applied to the function, taking the erased parameters into account, and then they are serialised together with the output for the next step. 
3. The outputs from the compiled JavaScript code are inserted into a temporary Agda module that prompts the elaborator whether the the same function call gives the same output. In particular, the tester creates Agda source files with the structure described in @consistency. 

  #figure(
    caption: "Agda file for checking consistency once the output of the JS definitions is collected."
  )[
  ```agda
  module Test where
  -- Import the module containing the function we want to check.
  open import Data.List
  open import Agda.Builtin.Equality
  -- For each test case, there is an assertion that the Agda definition
  -- normalises to the same output as the JavaScript definition did. 
  _ : map (λ x → x + 1) (1 ∷ 2 ∷ 3 ∷ []) ≡ (2 ∷ 3 ∷ 4 ∷ [])
  _ = refl
  ```
  ]<consistency>

  If this file type checks, it means that for each test case, the Agda definition is return the same results as the Javascript definition. Otherwise there might be issues in i.a. the number of parameters, different semantics, or type errors in the Javascript definition.
  
With well-chosen test cases, there is a reasonable degree of consistency between the Agda and Javascript definitions. There are some limitations to this tool, however, especially when testing functions operating on more complex data types, or functions using type classes. Data types and type classes are compiled to more complex objects, and may make use of external functions whose structure and generated names are quite hard to predict.

The solution to this would be to would be to write the consistency tests in Agda. We can take inspiration from Haskell's tasty testing framework#footnote(link("https://hackage.haskell.org/package/tasty")). We define an Agda program that contains (grouped) consistency tests. For example, we want to check consistency for `map`. We define a test case consisting of an input function `f` and an input list `xs`. Then we evaluate `map f xs` using the reflection API, the result of which is `ys`. Then we compile the expression `map f xs` to Javascript. Running the compiled Javascript code, will evaluate `map f xs` using the `COMPILE JS` version of `map`. The result of this is checked for equality to `ys` (using some user-defined equality function) and report back to the user. @consistency-checker shows the commutative diagram that is checked.

#figure(caption: [Commutative diagram for consistency checking the expression `map f xs`. The goal is to verify that the Agda definition and the `COMPILE JS` definition of `map` produce the same result `ys` for the given inputs `f` and `xs`.], image("consistency-checker.png"))<consistency-checker>

// #heading(numbering: none, depth: 4)[Parsing objects from JSON]

// #context {
//   let n = counter(figure.where(kind: raw)).get().at(0) + 1
//   set figure(numbering: str(n) + "a")
//   let c = counter(figure.where(kind: raw))
//   c.update(0)
//   show ref: it => { it.element.supplement + " " + c.display(at: it.element.location()) }

//   [To effeciently parse strings to JSON objects, and JSON objects to Agda data types, Avea makes use of the builtin support for JSON in Javascript. In Javascript, JSON objects can be parsed to Javascript objects using the `JSON.parse` function, which takes in a JSON string and produces Javascript objects, arrays and primitives corresponding to the JSON structure. In the Agda code, there is a `JSON` data type that has constructors for each type of JSON object. The FFI makes sure that the Agda data type constructors represent the primitive JSON objects returned by `JSON.parse`. @json-data-type describes the JSON primitives, whereas @json-pattern-match and @json-constructors implement the bridge between the Agda data type and the Javascript objects.]

//   grid(
//     columns: (40%, 60%),
//     gutter: 8pt,
//     [#figure(caption: [Agda data type with a constructor for each JSON primitive.])[
//       ```agda
//       data JSON : Set where
//         j-null   : JSON
//         j-string : string → JSON
//         j-bool   : boolean → JSON
//         j-number : number → JSON
//         j-array  : List JSON → JSON
//         j-object : StringMap.t JSON
//                  → JSON
//       ```
//     ] <json-data-type>],
//     [#figure(caption: [FFI code for the pattern matching on the data type.])[
//       ```agda
//       {-# COMPILE JS JSON = ((x, v) =>
//           x === null             ? v["j-null"]()
//         : typeof x === "string"  ? v["j-string"](x)
//         : typeof x === "boolean" ? v["j-bool"](x)
//         : typeof x === "number"  ? v["j-number"](x)
//         : Array.isArray(x)       ? v["j-array"](x)
//                                  : v["j-object"](x))
//         #-}
//       ```
//     ] <json-pattern-match>],
//     grid.cell(colspan: 2, [#figure(caption: [FFI code to create a constructor of the JSON data type.])[
//       ```agda
//       {-# COMPILE JS j-null = null #-}
//       {-# COMPILE JS j-string = s => String(s) #-}
//       {-# COMPILE JS j-bool = b => Boolean(b) #-}
//       {-# COMPILE JS j-number = n => Number(n) #-}
//       {-# COMPILE JS j-array = l => [...l] #-}
//       {-# COMPILE JS j-object = kvs => kvs #-}
//       ```
//     ] <json-constructors>])
//   )

//   c.update(n)
// }

// The benefit of using the FFI is that parsing JSON is also stack-safe. Implementing a string to JSON parser using recursion will quickly run into the stack depth limit, especially since some of the Agda responses can contain a sizable number of characters -- e.g. the length of highlighting response grows linearly with the source file's size. Javascript's `JSON.parse` is stack-safe, and performs better, since its imeplementation is written in C++ using the Node.JS FFI#footnote(link("https://github.com/v8/v8/blob/main/src/json/json-parser.cc")).

// The parsing from JSON objects to Agda data types is done in a separate step. Avea contains a simple parser combinator library that 
 
== Evaluation
 
// In the previous sections, we have discussed the changes in the infrastructure to run Agda code, as well as changes in writing programs in general. Having this infrastructure in place, and the adjusted code style avoiding recursion, we believe that Agda can be used as a practical programming language.

// Avea serves an example of what Agda can do in terms of practical use. Its Foreign Function Interface is already flexible enough to set up infrastructure to import and use dependencies. And with some small changes in the Agda compiler, the use of external Javascript dependencies can be safe in all circumstances. These dependencies can be pure or perform side effects, using a synchronous or asynchronous `IO` monad.

With the major implementation challenges discussed, we can answer the first research question: "Is Agda a suitable language to write practical programs with?" Yes, we believe that it is. Our arguments are split over the target language a developer uses:

- Programs targetting Haskell can benefit from the relatively predictable compilation, which handles tail-call optimisation to do recursion over large data structures and imports. Additionally, the Foreign Function Interface with Haskell is easy to use through the use of the `FOREIGN GHC`, and `COMPILE GHC` pragmas.

- Targetting Javascript requires some additional infrastructure and programming disciplines. Imports need to handled outside of Agda currently. Though the `FOREIGN JS` pragma will solve the remaining issues that this approach to imports has. In general, we think more development on the Javascript backend is beneficial, for example, a simpler or more efficient encoding of data types and records. Javascript is a versatile language that can run in the browser, as well as in desktop applications. Compiling Agda to Javascript allows developers to combine formal reasoning with new practical use cases that Haskell cannot fulfil, for example, formally verifying parts of a web application.

  Furthermore, Javascript engines do not typically have tail-call optimisation, which means recursion should be used sparingly. Instead, developers should use functions such as `map` or `reduce` that are stack-safe.

  For more complex data types, developers should implement their own stack-safe traversal functions. The `COMPILE JS` pragma allows developers to define a stack-safe version of a function, and a regular Agda definition defines a version that can be reasoned about at the type-level. Using a consistency checker, we can give stronger guarantees about whether the two definitions behave the same in the given test cases.

#pagebreak()

= Adding extensibility

#context {
  let n = counter(figure.where(kind: raw)).get().at(0) + 1
  let c = counter(figure.where(kind: raw))
  c.update(0)

  let letters = ("a", "b", "c")
  show figure.where(kind: raw): set figure(numbering: (..nums) =>
    str(n) + nums.pos().map(num => letters.at(num - 1)).join(""))
  show ref: it => {
    if it.element == none or it.element.func() != raw { return it }
    it.element.supplement + " " + c.display(at: it.element.location())
  }

  [
    In this chapter, we will look into making Avea extensible. For this we have decided to heavily depend by previous work on editor reflection by Korkut and Christiansen @extensible-editor. They introduced the concept of editor reflection in Idris1 -- a language with a similar meta-programming library, and a similar compiler structure as Agda.

    #figure(caption: [Example use of the `idris-easy` editor action defined below. The action can be executed on a hole, and it is filled with the returned expression from the meta-program.], image(width: 60%, "idris1-editor-reflection.png")) <idris-easy-use>
    
    In brief, editor reflection allows users of Idris1 to write meta-programs that can be executed from the editor. Listing #{n} lists the code used to implement the example editor action taken from @extensible-editor, whose functionality is shown in @idris-easy-use. The meta-program in @idris1-example-editor-action has a goal name parameter and attempts to solve the goal by inspecting its type. If the type of the goal is unit, it will return unit (line 6), if the goal type is an equality type and the types and values are convertible, then the reflexivity constructor is returned (line 10), otherwise the goal is not trivially solvable and an error is returned. This rudimentary solver is invoked by the editor using the Emacs Lisp support code (also called extension code) in @idris1-example-support-code. This code defines the editor action and what arguments (line 6) to send to the meta-program.
  ]

  grid(
    columns: (1fr, 1fr),
    gutter: 8pt,
    [#figure(caption: [Idris1 meta-program that tries to solve a trivial goal.])[
      ```Idris1
      %editor
      easy : TTName -> Elab TT
      easy n = do
        ty <- getType n
        case ty of
          `(() : Type) => pure (() : ())
          `((=) {A=~a} {B=~b} ~x ~y) => do
              converts a b
              converts x y
              pure `(Refl {A=~a} {X=~x})
          _ => fail
            [TextPart "Cannot solve"]
      ```
    ] <idris1-example-editor-action>],
    [#align(horizon, [#figure(caption: [Emacs Lisp support code to call the meta-program on the left from within the Idris1 editor.])[
      ```Elisp
      (defun idris-easy ()
        "Example editor action"
        (interactive)
        (idris-elab-hole-arg
          "easy" (list
            (idris-name-at-point))))
      ```
    ] <idris1-example-support-code>])]
  )

  c.update(n)

  [
    While the design by Korkut and Christiansen makes for an extensible editor tooling, users of Idris1 still have to write Emacs Lisp code to create an interface between the editor action and the editor itself. This has two drawbacks:
    + There is a potential source of bugs where the editor action returns an unexpected data type from the Emacs Lisp support code's perspective, or the support code sends an unexpected data type in the editor action's perspective. There is no way currently to constrain both ends to use the same data types.
    + Users need to learn the Emacs Lisp DSL. This might not be a big problem for smaller editor actions, however, more advanced editor actions might require more processing on the editor side, which requires more advanced knowledge of Emacs Lisp.

    These drawbacks can be solved by allowing the support code to be written in the same language as the editor actions. Since Avea is written is Agda already, and Agda has similar meta-programming capabilities as Idris1, Agda is perfect candidate for this. The example from Listing #{n} would be translated to the Agda program in Listing #{n + 1}.
  ]
}

#context {
  let n = counter(figure.where(kind: raw)).get().at(0) + 1
  let c = counter(figure.where(kind: raw))
  c.update(0)

  let letters = ("a", "b", "c")
  show figure.where(kind: raw): set figure(numbering: (..nums) =>
    str(n) + nums.pos().map(num => letters.at(num - 1)).join(""))
  show ref: it => {
    if it.element == none or it.element.func() != raw { return it }
    it.element.supplement + " " + c.display(at: it.element.location())
  }

  grid(columns: (1fr, 1fr), gutter: 8pt)[
    #figure(caption: [Translation of the `easy` action descibed in Listing #{n - 1}a into Agda. Since Agda does not have attributes (such as `%editor`), the type signature is annotated.])[```agda
    easy : EditorAction.t
      (Term → TC Term)
    easy hole = editor-action $
      inferType hole >>= λ where
        (def (quote ⊤) []) →
          pure (quoteTerm tt)
        (def
          (quote _≡_)
          ( (arg _ _) ∷ (arg _ A)
          ∷ (arg _ x) ∷ (arg _ y)
          ∷ [])) → do
            A` ← unquoteTC {A = Set} A
            unify x y
            x` ← unquoteTC {A = A‵} x
            pure (quoteTerm $
              refl {A = A`} {x = x`})
        _ → typeError $
          strErr "Cannot solve" ∷ [])
    ```]
  ][
    #align(horizon)[#figure(caption: [Translation of the "glue" code connecting the editor action on the left with Avea. The special `registrations` variable will be loaded by Avea to discover all extensions.])[```agda
    agda-easy : AveaExtension.t ⊤
    agda-easy = do
      h ← hole-under-cursor
      term ← get-hole-content h
      new-term ← call-editor-action
        easy [ term ]
      fill-hole-with new-term h

    registrations : List Registration.t
    registrations
      = hole-cmd agda-easy
      ∷ []
    ```]]
  ]
}

// The first drawback is solved, because Agda data types can be shared between the editor action and support code, which can act as a checked contract between the two parties.

// Even though the second drawback would also be solved, it is important to note that the extension code is still executed in a different environment as the editor action. @agda-environment describes all environments the different pieces of Agda code can be executed in. It shows that extension code (yellow box) can call editor actions (blue box) through Avea's API (green box), however editor actions cannot call back into the extension code. Extension code can also run regular meta-programs (black box), which will be executed at the compile time of the extension code. There is a subset of Agda code that can be used in any environment (red box). The constraints for this is that this code can only make use of data types defined within Agda itself, or of builtin data types and primitive functions. Logically, this excludes any use of runtime-specific code, i.e. code using postulates and `COMPILE` pragmas.

// #figure(caption: [A diagram mapping out the different environments Agda code can be executed in. The arrows symbolise an environment calling Agda code written for another environment.], image(width: 80%, "runtimes.png")) <agda-environment>

To implement an editor with editor reflection fully in Agda, we can extend Avea and the Agda compiler to support editor reflection, and for this we identify the following stages of development. These stages are ordered such that each stage adds new functionality on top of the previous stages. Even though the implementation of these stages goes beyond the scope of this thesis, we will still describe a rough design for each stage.

- In @basic-avea-edsl, we will introduce a basic embedded domain specific language (EDSL) in Avea for listening for events in VS Code and handling them, and adding new edit-time functionality extensibly without making changes to the Agda language or the Agda compiler. We will call these *extensions* in Avea. The new functionality of this system will be rather limited: this API would allow people to write snippets or automate a sequence of hole commands for example in an extensible manner.

- In @edit-actions-agda, we will discuss being able to call meta-programs, which we call *editor actions*, in the Agda compiler. The implementation of this is mostly based on the work of Korkut and Christiansen, but applied on the Agda compiler. Adding editor reflection to the current version of the Agda compiler allows for non-syntactical expression manipulation in holes. Examples include, simplification of programs written in an EDSL, customised code snippets (e.g. generating boilerplate for type class instances), and proof search actions.

- In @changing-meta-language, we will dicuss why the current reflection API does not include many high-level language constructs (such as `let`, `where`, `do`) or provide source locations. Incorporating these into the reflection API would allow for syntactic changes and more precise edits in the buffer. This enables use cases such as lintings and warnings, which can be executed on every load of a file, and display squiggles in the buffer at exact locations.

- Finally, in @avea-widgets, we will briefly discuss the possibility of porting Lean4's widgets to Avea and Agda. This will allow more advanced user interfaces in the display buffer, while still not needing to leave the confines of Agda.

== Start of the Avea extension EDSL <basic-avea-edsl>

// Editor actions defined using the EDSL have no use if they cannot be executed. Ideally, the definitions of editor actions have the following properties:
// - They are _co-located_ with other Agda code. This means, for example, a library could provide editor actions alongside its regular functionality, or an editor action could make use of backend-agnostic Agda code.
// - And they are defined in an _extensible_ manner. That is, an Agda programmer should not have to modify or recompile Avea if they want to add or remove an editor action.

// *Co-locating Agda code from different runtimes*

// Allowing co-location of extension code with regular Agda code with potentially a different target language should not pose great challenges. Compiling an Agda module with the Javascript backend does the following:
// - Any definition with a `COMPILE JS` pragma will have its definition replaced in the Javascript output code with the Javascript code in the pragma.
// - Postulates are by default compiled to `undefined`.
// - Compile pragmas for the Haskell backend are ignored.

// This means that compiling Agda modules which are meant to be compiled with the Haskell backend in mind, containing Avea extension code, using the Javascript backend will compile all the extension code without trouble. That means it is possible to compile all modules containing extension code using the Javascript backend and let Avea pick out the extension code definitions. Given the file path to the module, Avea can spawn a new Agda instance to compile the module in a temporary folder and include dynamically load and execute the Javscript code.

// To allow extension code to be co-located with other Agda, the extension code needs to be able to be distinguished from the other code. The obvious difference between editor actions and other code is the type: every editor action must have type `ExtensionAction.t ⊤`. This means that given a way to query all top-level definitions with a type, it is possible to retrieve a list of all editor actions. However, currently there exists no way to query definitions using a type, or query all definitions at all. This means that we need to extend the compiler's interaction mode to have an endpoint that can search for editor actions. Later in @changing-meta-language, it is possible to replace this endpoint with an editor action itself.

// #todo[For each module, describe scope for finding editor actions]

// The indexing procedure in Avea is described below. Since indexing involves compiling modules, indexing is done relatively infrequently. This is not a problem, since extension code will also change infrequently. A user can request Avea to re-index an Agda project using a command or a keybind.
// + Call to Agda interaction mode endpoint to query for all top-level definitions of type `ExtensionAction.t ⊤`.
// + Each definition's source file is compiled and the names of the extension functions are used to lookup the Javascript definition in the compiled output.
// + A new state variable is created that collects the registrations of hooks. This is a mapping from the hook type to a list of Javascript functions to execute if that hook triggers. The Javascript definitions are executed with this state variable, so that after the final definition, the state variables contains a record of all actions that need to executed at a particular time.
// + Avea's model is updated with this new state variable, so that the Avea internals can invoke the hooks.
Users can always extend Avea by forking its source code, adding a new feature and recompiling the code into a VS Code extension. However, this is a tedious process, which is not very extensible. Instead, Avea needs a way to load extensions, without editing or recompiling Avea.

To do this, Avea can load a specific Agda project -- with a `.agda-lib` file to declare dependencies -- somewhere on the user's file system. This library requires one specific exported module, which Avea loads and executes. This special module contains all hooks and extension actions.

#figure(caption: [Startup file for Avea extensions. The registrations variable is a list that says when a function should be called after what event.])[```agda
module Avea.Extensions.Hooks where

registrations : List ExtensionRegistration.t
registrations = on-hook load ...  ∷ on-cmd ... ...  ∷ ...  ∷ []
```]

The hooks are registered by calling constructors of the `ExtensionRegistration.t` type. The hooks are defined in Avea, and listen for events from a number of relevant VS Code features. For example, extension code can register a command in the command palette in VS Code or listen to lifecycle hooks that are executed after a particular event, e.g. on a successful load of a file.

#figure(caption: [Definition of `ExtensionRegistration.t`, which is used to define hooks.])[```agda
module ExtensionRegistration where
  data t : Set where
    on-hook : AveaHook.t → ExtensionAction.t ⊤ → t
    on-cmd : AveaCommand.t → ExtensionAction.t ⊤ → t 
    on-menu-button : MenuButton.t → ExtensionAction.t ⊤ → t 
```]

The extension actions that are executed when a hook triggers, are programs written in the `ExtensionAction.t` monad. The `ExtensionAction.t` monad is a `State` monad where the state is Avea's model. However, the monad does not allow any field in the model to be modified: changes or accesses must be done through the defined functions in the Avea library. This way extensions cannot interfere with Avea's internal system, and potentially compromise its other functionality. So examples of functions that operate in this monad are described in @extension-functions.

#figure(caption: [Signatures of functions in the proposed Avea extension EDSL.])[```agda
hole-under-cursor : ExtensionAction.t Hole.t
get-hole-content : Hole.t → ExtensionAction.t HoleTerm.t
get-hole-range : Hole.t → ExtensionAction.t Range.t
replace-hole-with : HoleTerm.t → Hole.t → ExtensionAction.t ⊤
write-to-current-buffer : String → Range.t → ExtensionAction.t ⊤
send-agda-interaction : AgdaInteraction.t → ExtensionAction.t AgdaResponse.t
```] <extension-functions>

The implementation of extensions in Avea should not pose too many problems. It requires:
- Implementations of the functions described in @extension-functions. These functions already exist within the current implementation, but need to be adjusted to work within the `ExtensionAction.t` monad.
- Each hook should be triggered at the appropriate time. For registrations involving commands or buttons, they should first update the UI and let the callback call the `ExtensionAction.t`. Each life cycle hook just needs access to the registration list to call the functions subscribed to the hook in question.
- Adding a new "reload extensions" command in Avea, which recompiles the Agda project containing the registrations and loads the compiled Javascript code and updates the registrations in Avea's model. This is needed when an extension is added, removed or, while developing an extension, its code has changed.

*Use cases*

The extension EDSL does not unlock very powerful edit actions, apart from some automations of existing sequences of Agda interactions. However, there are still some edit actions that were not possible to implement before, which are listed below.

- _Caching for proofs by reflection_: proof by reflection is a technique where functions mechanically generate proofs for a theorem @proof-by-reflection. Computing these proofs for large proof trees can be expensive, especially considering that these proofs may not change often. Therefore, it might be more efficient to inline the proof tree in the source to avoid doing the proof by reflection at elaboration-time. Inlining the proof tree could be implemented as an editor action in our extension.

- _Record and replay_: Listening to hooks of all interactions, it is possible to record how a definition is "created" by recording the use of Agda interactions. These can be saved and serialised, and later on replayed on another definition to recreate it, or exported for didactical purposes.

== Edit-time actions in Agda <edit-actions-agda>

// Given a feature-complete extension, a natural question is are there any new features that can be implemented in this extension? The problem is that the current architecture for Agda extensions is rather limiting. With the current setup, we need to either implement the new features directly in the Agda compiler, or make a separate tool in Haskell that depends on the Agda compiler. Both approaches require us to learn the internals of the Agda compiler, which can pose a high barrier of entry for Agda programmers who want to make their own editor tooling.

Instead of modifying the compiler to add editor features, Korkut and Christiansen @extensible-editor have implemented an extensible editor for Idris1 where editor commands can be defined within Idris1 itself using the metaprogramming library. The procedure they used to implement the editor extensions can be translated quite well to Agda. As illustrated in @editor-reflection-complete, the procedure consists of designing a user-friendly API to call editor actions in a type-safe manner (Part 1), defining the communication protocol between the interaction mode and Avea (Part 2), and running editor actions in the compiler (Part 3).

#figure(caption: [Complete diagram showing the steps that are taken to call an editor action in the Agda compiler from an Avea extension.], image("editor-reflection-complete.png")) <editor-reflection-complete>

*1. Designing the API to call editor actions*

#grid(columns: (6fr, 4fr), gutter: 16pt)[#align(horizon)[
  We can extend the extension EDSL proposed in @basic-avea-edsl to include a way to call editor actions. Calling an editor action is done in a similar way to calling other commands in Agda's interaction mode. This means that it is possible to reuse a lot of the logic for sending interactions and receiving and handling responses in Avea, and the logic from @basic-avea-edsl for making the responses available in extensions.

  To call an editor action on a hook, one needs to register an extension on the hook (step 1 in @editor-reflection-1). Avea calls the extension (step 2) when the hook triggers, and the extension can call the editor action using by communicating with the interaction mode (step 3). The result is communicated back, and the extension can call Avea internals to display the returned data (step 10 and 11).
]][
  #align(horizon)[#figure(caption: [Diagram of Avea running extensions calling editor actions.], image("editor-reflection-1.png")) <editor-reflection-1>]
]

  // 1. Avea loads the registrations and registers the extensions to the hooks.
  // 2. When a hook is triggered, the extension's monadic code is executed. The extension can retrieve goal information from the state variable, and prepare data to send to the editor action.
  // 3. The extension can use a `call-editor-action` macro, which takes the name of the editor action and a list of arguments. This macro checks the arguments against the expected types of the editor action, and generates the code to send to the compiler.
  // 10. The macro also handles calls the parser of the serialised data once the data from the compiler comes back. After that, the extension can resume execution.
  // 11. The data from the editor action can be displayed in the display buffer, or used to fill a hole in the current buffer.

// An editor action consists of two parts: the (de)serialisation, and the actual metaprogamming logic. The `EditorAction.t` record contains the type of the metaprogram and the metaprogram augmented with the (de)serialisation steps. Augment the meta-program in this way, and saving its original type separately, will make the implementation of executing editor actions in the Agda compiler easier (as discussed in stage 3). Using meta-programming, it is possible to automatically convert a metaprogram to an `EditorAction.t`. This process is encoded using the `editor-action` macro, whose signature can be found in @EditorAction-def.

// #figure(caption: [Definition for `EditorAction.t` and the `editor-action` macro, which converts regular meta-programs to `EditorAction.t`s.])[```agda
// module EditorAction where
//   record t : Set₁ where field
//     action-type : Set
//     action : List String → TC String

// macro editor-action : (m : Term) (hole : Term) → TC ⊤
// ```] <EditorAction-def>

// The `editor-action` macro can infer the types for each parameter, and searches the correct `Encodable A TC` instances. Then it generates a new meta-program of type `List String → TC String`, that runs the deserialisation functions on the parameters, then runs the meta-program `m` with the deserialised arguments, and lastly, serialises the result of calling `m`.

// #figure(caption: [Example of reusing editor actions for use as regular meta-programs.])[```agda
// macro
//   execute-action : (Term → TC Term) → Term → TC ⊤
//   execute-action m hole = m hole >>= unify hole

// thm : 1 + 1 ≡ 2
// thm = execute-action easy
// ```]

// + Extend the interaction mode such that on a successful file load, all of the edit-time functions are listed. Within Visual Studio Code, these edit-time functions can be displayed as code actions, which are listed under the "refactorings" menu when right-clicking a piece of code. The benefit is that Visual Studio Code has additional features for refactorings that need not be implemented in the extension itself. For example, it allows programmers to bind specific code actions to a keybind using a workspace or global configuration file, or it allows programmers to preview refactorings before actually applying them to the buffer.
  
//   When a code action is invoked, a command must be sent to the interaction mode. This means, the interaction mode should also be extended with a new command that runs a edit-time function with arbitrary arguments supplied.

// Calling the interaction mode for an editor action can also be made easier through the use of meta-programming. The meta-program `call-editor-action` shown in @call-editor-action takes the name of the editor-action that should be invoked and a list of arguments to pass to the editor action.
// The `call-editor-action` macro can use meta-programming to infer the types of its arguments, request the parameter types from the editor action and try to unify them to provide a type-safe API for calling remote editor actions. The macro can generate code in the same monad as the EDSL, so that it can be easily integrated with extensions.
Editor actions are co-located with the Avea extensions. This means that we can write meta-programs that can inspect the type of the meta-program, and find type class instances at compile time, Therefore metaprogramming allows us to provide a type-safe API to call editor actions, even though they are executed in a different environment from the Avea extensions.

// #figure(caption: [Type signature for the `call-editor-action` macro. This macro is responsible for calling an editor action from the extension code.])[```agda
// macro call-editor-action
//   : (action-name : Name) (args : List Term) (hole : Term) → TC ⊤
// ```] <call-editor-action>

// This macro does the following steps:
// + Firstly, it fetches the type of `action-name`'s type signature from the environment, which should be of type `EditorAction.t`. The parameters of the type saved within the record is unified with the types of the corresponding given argument. This check gives type-safety when calling the editor action.
// + For each parameter and the return type, the instances for `Editorable` are searched and saved. These instances are used to generate the code to serialise each of the given arguments. If there exists no `Editorable` instance for a type, then a type error is raised.
// + The meta-program generates code of type `ExtensionAction.t (Either String B)` for the following steps:
//   + Serialise the arguments using the found `Editorable` instances for the parameters.
//   + The `action-name` and the serialised arguments are inserted into a `iotcm` call, which is sent to the Agda interaction mode handle that Avea keeps open.
//   + When Agda responds with the serialised result of the editor action, the result is deserialised using the `Editorable` instance for the return type, and this deserialised result is returned. The editor action might also fail, either because the editor action threw a type error, or because deserialisation failed (e.g. when an expression in a hole is not valid). For this reason the generated code returns either the stringified error or the expected result.
// + The generated program is unified with `hole`. Using the macro allows for seemless integration with the `EditorAction.t` monad defined earlier. An example usage of the `call-editor-macro` can be found in @example-call-editor-action.

// #figure(caption: [Example usage of the `call-editor-action` macro from the `EditorAction.t` monad, combining operators from @basic-avea-edsl with editor reflection.])[```agda
// editor-action : EditorAction.t
// editor-action term = editor-action ...

// extension-code : EditorAction.t ⊤
// extension-code = do
//   term ← hole-under-cursor >>= get-hole-content
//   call-editor-action editor-action [ term ] >>= λ where
//     (left err) → display-error err
//     (right new-term) → hole-under-cursor >>= fill-hole-with new-term
// ```] <example-call-editor-action>

// One last ingredient to make the example in @example-call-editor-action work is the serialisation of the term retrieved from the hole, and the term inserted into the hole. Avea cannot parse the expression in a hole (which might not even be a valid expression at all), and so it will return a string. However, the `editor-action` expects a `Term`. Instead of returning the hole contents as a `String`, Avea can return another data type `HoleTerm.t` containing a `String` with a custom `Editorable` instance from `HoleTerm.t`s to `Term`s. 

// #figure(caption: [Definition for `HoleTerm.t` which is a wrapper data type for `String` representing terms inside of holes. The wrapper type allows a custom `Editorable` instance to `Term`s from Agda's reflection library.])[```agda
// module HoleTerm where
//   record t : Set where field term : String

//   editorable : Editorable HoleTerm Term
//   editorable = record
//     { runtime = -- Encodable instance for HoleTerm
//     ; action  = Encodable-Term }

// get-hole-content : Hole.t → EditorAction.t HoleTerm.t
// ```]

// In addition to implementing edit-time functions in Agda with support from our extension à la Korkut and Christiansen, we can make use of the fact that our extension itself is also implemented in Agda. The edit-time function in Idris1 required some "glue" code written in Emacs lisp -- the language the editor extension is written in. Our extension supports Agda end-to-end: an Agda metaprogram is used to define the edit action, and the way to call the metaprogram and handle its response in the editor is also written in Agda. The benefit is that the edit action and handler can be co-located, and require understanding of only one language, which both help maintainability of extension features and a lower barrier of entry for Agda programmers to write their own features.

// This benefit can be fully exploited when the extension also provides an easy way for feature authors to integrate their feature into the extension, ideally without having to touch parts of the extension's source code. Therefore, after having completed the implementation of edit-time functions, it worth spending time improving their integration in the extension, with for example:
// - functions to gather input from the user: e.g. reading code from the goal the user's cursor is on, or querying the editor buffer for a whole line of code;
// - functions to handle output: e.g. displaying information in the display buffer or writing to the editor.

*2. Defining the communication protocol*

#grid(columns: (5fr, 5fr), gutter: 16pt)[
Editor actions are executed in the Agda compiler. However, they are triggered by the extension and receive arguments from there, and the result of the editor action also needs to be communicated back to the extension. As mentioned in @building-avea, Avea communicates to the Agda compiler through its interaction mode. Avea sends serialised Haskell expressions to the interaction mode (step 4 in @editor-reflection-2), and it responds with JSON objects (step 9).

This means that to send values to editor actions, it is easiest to serialise them to a string, and embed those strings in the Haskell expressions. And for receiving values, the reverse needs to happen: strings in the JSON responses need to be deserialised to a value in Avea. The serialisation and deserialisation of values of type `A` can be defined a type class: `Encodable A M`.

][
  #align(horizon, [#figure(caption: [High-level diagram of the communication between Avea and the compiler, where Avea is on the left and the Agda compiler on the right.], image("editor-reflection-2.png")) <editor-reflection-2>])
]

However, the representation in Avea of a type might not correspond well to what editor actions use. An example is expressions: Avea only has access to stringified high-level Agda source code, whereas meta-programs usually expect parsed and elaborated terms. The `Editorable` type class captures this convertibility between different types. It combines two `Encodable` instances: one for the representation in Avea (step 3 and 10 in @editor-reflection-2), and one for the representation in the Agda compiler (step 5 and 8).

#figure(caption: [Possible definition for the `Encodable` and `Editorable` type classes used for communication between Avea and the interaction mode.])[
  ```agda
  record Encodable (A : Set) (M : Set → Set) : Set₁ where field
    to   : A → String
    from : String → M A

  record Editorable (A B : Set) : Set₁ where field
    runtime : Encodable A Maybe
    action  : Encodable B TC
  ```
]

// The reason why `Editorable` has two type parameters `A` and `B` is that the type of values on the runtime and the editor action might differ. Take lines 14-16 in #text(red)[agda-easy] as an example. Line 14 requests the hole under the cursor and if it exists, then request its contents. However, a hole's contents might not resemble a valid Agda expression. Furthermore, parsing that expression in Avea requires embedding Agda's parser pipeline in Avea, which is difficult to do since the Agda parser is written in another language than Avea.

// For this reason, Avea keeps the hole's contents as a `String`, but it will be parsed to an Agda term in the editor action. To keep the API type-safe, the `Editorable` instance takes two parameters: one for the representation in Avea, and one for in the editor action. Calling the editor action, will pass along the serialiased data from `A` and the `Editorable A B` instance that is used to do it. This means the editor action can deserialise the data to the correct type, and serialise it back correctly.

// Even though, `Editorable` takes a source and target type, they can be the same. This also simplifies the construction of an `Editorable A A` instance, since there exists a simple translation from an `Encodable A Maybe` instance to an `Encodable A TC` instance. This is illustrated in @editorable-square.

// #figure(caption: [Diagram of an `Editorable A A` instance: it consists of two `Encodable A M` instances (red boxes), which each contain two functions. Given an `Encodable A Maybe` instance, we can complete the square through a simple transformation.], image("editorable-square.png", width: 50%)) <editorable-square>

// The definitions of `Encodable A M` and `Editorable A B` can be subject to some laws proving their correctness. The laws are shown in @editorable-laws. The red box shows an `Encodable` instance, where it should that deserialisation after serialisation should not change the result.  The same law holds for `Editorable` (shown in the green box), however, the serialisation and deserialisation are given by the transfer functions. The transfer functions are the composition of the serialisation and deserialisation via JSON. This law makes sure that, even though the individual transfers via JSON are sound, the overall conversion to and from `A` and `B` is also sound.

// #figure(caption: [Visualisation of the laws proving correctness of the communication. In an `Encodable A M` instance, `from` and `to` should be inverses. The same applies for `transferₐ` and `transferᵣ` in `Editorable A B` instances.], image("editorable.png", width: 80%)) <editorable-laws>


*3. Running editor actions in the compiler*

#grid(columns: (6fr, 4fr), gutter: 16pt)[
Two major changes are needed to the Agda compiler to add support for running editor actions.

- A new endpoint in the interaction mode needs to be implemented. As any endpoint, it always receives information about the file to operate on. Additionally, editor actions require the name of the action, and a list of serialised arguments.

  The handler of the endpoint, loads the requested module, searches for the editor action by name in the top-level scope, and then runs the metaprogram in the editor action (step 6 in @editor-reflection-3). The editor action is given the deserialised arguments, and produces a result (step 7). This result is serialised again and send back as an Agda response to Avea.

- The compiler needs to provide some privitives to implement some instances of `Encodable`. In particular, Avea can send high-level Agda code, that needs to be parsed and elaborated before it can be used in an editor action (step 5). Returning an Agda expression has to do the reverse: it should be delaborated and serialised before sending it to Avea (step 8). Parsing, elaborating, delaborating and serialising of Agda code within Agda is currently not possible, hence the need for the new primitives.
// Running the editor actions requires two changes in the compiler: the extension needs to be able to call an action using the a new endpoint in the interaction mode, and the editor action needs to be able to de-serialise its arguments and serialise its return value.

// The new endpoint in the interaction mode is relatively simple to add: the Agda compiler has an `Interaction` data type, where each constructor is an endpoint. It suffices to add a new constructor to this data type and implement the relevant `Read` instances. Every `Interaction` already receives information about the file it should operate on, so this need not be included in the parameters of the new constructor. What remains are parameters for the name of the editor action, the name of the Editorable instance and the serialised arguments. The new constructor definition can be found in @.
][
  #align(horizon)[#figure(caption: [High-level diagram of the system to execute editor actions in the Agda compiler.], image("editor-reflection-3.png", width: 75%))<editor-reflection-3>]
]

// #figure(caption: [Definition of the new interaction constructor for calling an editor function via Agda's interaction mode (top), and the response constructor for receiving its result (bottom).])[```hs
// data Interaction'
//   = ...
//   | Cmd_editor_action
//       String -- The name of the editor action
//       [String] -- List of serialised arguments
// ```
// ```hs
// data Response_boot tcErr tcWarning warningsAndNonFatalErrors
//   = ...
//   | Resp_EditorActionResult String -- Stringified result of the editor action
// ```
// ] <interaction-constructor>

// The semantics for the editor action endpoint have to be given in the `interpret` function in the compiler's `Agda.Interaction.InteractionTop` module. Firstly, this function should look up the editor action by the provided name, where the name should correspond to a value of type `EditorAction.t` accessible in the top-level of the module the interaction operates on. The `action` property in the `EditorAction.t` record is a meta-program that accepts a list of serialised arguments, parses them and then executes the action itself. This meta-program also serialises the result of the action, which is ultimately returned. This means that, after looking up the value of the name, the endpoint only needs to call the meta-program with the serialised arguments, and wrap its return value in a `Resp_EditorActionResult` constructor to return to Avea.

// Referencing the parsers in the meta-program itself allows the implementation of the endpoint to be quite simple, however it also has a limitation. The type of each parameter must be known at the definition of the meta-program. This means that meta-programs with dependent types, and by extension, polymorphism cannot be called using the approach described above. // Korkut and Christiansen already remarked that dependent types require more advanced `Encodable` instances, and a different encoding using universes a la Tarski.

// // #todo[Reference to Tarski]

// With the implementation of `interpret` in place, it remains to implement `Encodable` instances for the data types in the reflection library. Since the editor actions operate on the types in the reflection library and use its functions, it is therefore necessary to be able to deserialise and serialise values of these types. As remarked by Korkut and Christiansen, the extension has access to stringified concrete syntax, that is, the language the users write, whereas the editor action operates on abstract syntax. To convert stringified concrete syntax to abstract syntax, it needs to be parsed, scope-, and type-checked. The reflection API does not expose primitives for parsing or scope-checking, so it is not possible to write instances for `Encodable` for some types in the reflection library. Instead, it is possible to expose new primitives that can be used to define such an instance. Their signatures are described in @editor-reflection-primitives.

// #figure(caption: [Signatures for the `from` and `to` functions for the builtin reflection data types.])[
//   ```agda
//   data HasPrim : Set → Set where
//     has-Term : HasPrim Term
//     has-Definition : HasPrim Definition
//     -- Other types elided

//   primitive
//     primFromEditor : HasPrim A → JSON → TC A
//     primToEditor   : HasPrim A → A → TC JSON

//   instance
//     Term-Encodable : Encodable Term TC
//     Term-Encodable = record
//       { from = primFromEditor has-Term
//       ; to   = primToEditor has-Term }
//   ```
// ]<editor-reflection-primitives>

// The new primitives `primFromEditor` and `primToEditor` also require an implementation in the Agda compiler. The `primFromEditor` function should, given a JSON object, check the tag if it matches with the expected type, and then convert the data into the data types used in the elaborator. The `primToEditor` does the opposite, given some type, it will delaborate and serialise the value into a JSON object with the correct tag.

// The implementation of the primitives need to be completed in the compiler. Ultimately, the IDE user can call an edit-time function with some terms as arguments. @term-communication describes on a high-level the steps that need to be taken to run the edit-time function.

// #figure(image("editor-reflection.png", width: 80%), caption: [Visualisation of the pipeline to pass terms from an editor extension to the compiler to be used in an edit-time function.])<term-communication>

// In summary, the IDE user writes surface level terms, we can send those as strings to the compiler and let it parse it to `Concrete.Expr`s. The compiler can scope-check and type-check these `Concrete.Expr`s to `Internal.Term`s, which can be `quote`d and passed as arguments to edit-time function. The result goes through the inverse pipeline: the `Reflected.Term`s are unquoted, reified, pretty printed and sent back to the extension, which can insert the resulting term into the buffer.

*Use cases*

The editor reflection system as we have described it above allows for more powerful edit-time features. In particular, users can now combine the functionality of Avea's extension EDSL and the functionality of Agda's reflection API to write new tooling. This means that editor reflection allows users to transform expressions in holes or fill holes using a meta-program. Some examples include:

- _Hoogle-like lemma search_: this feature requests all names available in the current scope of the cursor and tries to unify them with a given type (or the requested type of the hole). This features needs to communicate a list of types back to the extension, which is then displayed in the display buffer.

- _Re-implementation of some existing interactions_: With the ability to inspect the local context, it is possible to replace interactions such as give (`C-c C-SPC`), refine (`C-c C-r`), goal environment (`C-c C-,`), infer (`C-c C-d`) and normalise (`C-c C-n`). These interactions can be implemented using the reflection API, and therefore their implementation can be moved from being in the compiler to being editor actions in a standard library.

- _Custom automatic proof search_: Kokke and Swierstra @kokke2015auto have implemented an extensible proof search mechanism using just Agda's reflection library. Editor reflection allows users to call this proof search library at edit-time, which has a number of advantages, as remarked by the authors in the discussion. Firstly, the proof search does not need to run every time the module is compiled, since its resulting program can be spliced into the source code of the program. Secondly, the resulting program can also contain new holes, which opens the possibility for the proof search mechanism to return incomplete terms.

== Changing Agda's meta-language <changing-meta-language>

Editor reflection unlocks allows users to reason about and change the semantics of their code at edit-time. However, the current reflection API in Agda does not allow for inspecting syntactic elements of their code. Recall from @agda-metaprogramming that let and where clauses are all substituted in reflected terms. The benefit of this is that it is closer to the internal representation of terms in the compiler, and that the data type describing needs less constructors. Additionally, because the compiler does a lot of substitutions, it is difficult to keep track of the source locations of reflected terms. The compiler changes the structure of the code from its concrete syntax, and therefore there exist many nodes in the abstract syntax tree that do not exist in the concrete syntax.

While for regular meta-programming, the semantics of the code is the only concern for programmers, because the generated code from the meta-programs is not typically displayed. This means that making changes to syntactical constructs of a program is futile, since in the eyes of the developer, nothing changes about the result of the final program. However, since editor reflection allows users to make change to the source code of their programs, being able to reason about and make changes to the concrete syntax becomes relevant.

Korkut and Christiansen also mention this in their future work in @extensible-editor: "In the future, it would be interesting to explore representations of the syntax of high-level Idris that are robust in the face of change and extension." With a representation of high-level Agda -- that includes source locations -- in the reflection API, it is possible to unlock a lot more potential of editor reflection. In particular, it would be possible to be more precise about the location of where edits should be applied or where warning squiggles should appear. This is the driving mechanism behind the following examples:

// - _Add Clause action_: Korkut and Christiansen implemented an "Add Clause" action, which, given a signature of a function, provides an initial skeleton for the definition of that function. The same would be possible with the change in the meta-language, now that the source location of the signature can be used to determine the insertion point for the definition.

//   #figure(caption: [Example of the code produced by the _Add Clause_ action, which could be implemented with the proposed editor reflecton system and meta-language upgrades.])[```agda
//   append : List A → List A → List A   -- Given signature
//   append a b = {! !}                  -- Definition provided by the extension
//   ```]

- _Unused variable linter_: This is a feature that many more mainstream languages have, where unused variables are greyed out or marked as a warning for being redundant. The editor action part of the linter can traverse the structure of the program, and keep track of usage per binder, when finally, it can return the locations of the unused binders. The extension code can trigger on every load, where it will call the editor action, and put squiggles under every returned source location with a hover information message.

- _Style checkers_: Taking the idea of the previous linter a step further, style checkers analyse the structure of the code for general _anti-patterns_, that is, obvious structures that can be improved. These style chekers can also make use of VS Code's suggested fix button in the hover view. This button can trigger another editor action, which replaces the code violating style rule with another piece of code with the preferred style.

- _Re-implementation of the case split interaction_: Given the possibility to reason about source locations, it is now possible to also re-implement the make case interaction (`C-c C-c`). In addition, it would also be possible to improve its functionality, by allowing it to create cases for lambda parameters for example.

- _Refactorings for dependently-typed programs_: We can also implement refactorings inspired from Barwell et al. @dependently-typed-refactorings. They introduce refactorings such as adding an index to a data type definition, or relating two constructor parameters using a dependent type. This feature could be used to its full potential with bindings to VS Code's refactorings menu. This menu allows the user to see a preview of the changes that a refactoring applies and to select multiple refactorings to see how they interact, and give the desired result.

// == Implementing/extending the LSP protocol for Agda <own-lsp>

// As mentioned earlier, existing Agda extensions all have custom logic for interfacing with the editors. The responses Agda provides are also custom. This means that if we want to support a new editor, then we need to write a lot of interfacing logic for that editor again. As mentioned in @lsp-bg, the LSP protocol aims to solve this problem. There already exist implementations for an Agda language server with varying degrees of completeness:
// - As mentioned in @background-agda, the Agda Language Server (ALS)#footnote[#link("https://github.com/agda/agda-language-server")] is a project by the author of the original Visual Studio Code extension for Agda. It is integrated with the extension, and therefore it only has functionality that is not already implemented in the extension. The current version only includes hover functionality for displaying types of terms.
// - For his Master's thesis, Stuijt Giacaman implemented agda-lsp -- a language server designed that aims to provide provide real-time feedback to the users @agda-lsp. Agda-lsp achieves this through the use of a custom scope-checker for Agda, and avoiding the use of the type-checker, which can be slow for bigger source files. The scope-checker provides sufficient information to provide basic LSP functionality such as semantic highlighting and go-to-definition, but also functionality currently not found in any Agda extensions making use of the interaction mode: finding references of a given symbol, and diagnostics for unused symbols.

// Even though there is plenty of future work that these projects suggest, it would be difficult to relate that work to the our non-LSP implementation for an Agda extension. We therefore deem this research direction out of scope for this thesis.

== Port of Lean4's user widgets to Avea and Agda <avea-widgets>

As mentioned in @lean4-meta, the `lean4-vscode` extension allows custom widgets to be embedded in the infoview. Widgets are defined using React -- a web framework in Javascript -- and allow any user interface to be displayed in the info view. Widgets in Lean4 can call meta-programs, which is how Lean4 has designed editor reflection. It is also possible to allow arbitrary user interfaces relying on meta-programs in Avea's display buffer.

#grid(columns: (55%, 45%), gutter: 16pt)[
  The architecture of Lean4's widgets can be described by the diagram in @pw-arch @proofwidgets. There are two points of special note:
  + Widgets can directly communicate via LSP to the Lean4 compiler. If the widgets want to evaluate metaprograms, then they can use the injected Lean4 RPC library to call metaprograms. The RPC library only allows function calls to meta-programs marked with the `@[server_rpc_method]` attribute.
  + The React code for the widgets in stored as a string in the Lean source file. When a widget should be loaded, this code is sent to the infoview, which embeds the React component into its own React app. The infoview manages all communication to and from the extension: if a message is native to the infoview, it handles it itself, otherwise it can dispatch the message to the widget.
][
  #align(horizon, [#figure(caption: [High-level architecture of Lean4's user widget system in `lean4-vscode`.], image("proofwidgets-arch.png", width: 80%)) <pw-arch>])
]

The same architecture can be taken inspiration from for Avea and Agda, a proposal for an architecture can be found in @avea-widgets-arch. The main component of this architecture is Iepje, an Elm-inspired web framework for Agda. Whereas widgets in Lean4 had to embed React code in the Lean source files, Avea would allow widgets to be written in Agda, maintaining all the aforementioned benefits of using one language.


#grid(columns: (55%, 45%), gutter: 16pt)[
The display buffer can be a new component implemented in Iepje, and its task will be to listen for new widgets and to handle all native messages from Avea (e.g. DisplayInfo and RunningInfo messages). The widgets themselves can also be implemented in Iepje.
+ If a widget should be loaded, Avea compiles the widget via the Agda handle.
+ Agda puts the compiled JS code in a temporary folder, which Avea communicates to the infoview.
+ The infoview can create a new DOM element for the new widget and loads the widget's compiled code from the temporary folder.
+ The widget is initialised with RPC controls by the infoview to have two-way communication with the extension, and is allowed to use the newly created DOM node to display.
][
#align(horizon, [#figure(caption: [Architecture proposal for a version of Lean4's user widgets in Avea and Agda.], image("avea-widgets.png")) <avea-widgets-arch>])
]

*Use cases*

There are numerous use cases for more complex visualisations in the display buffer:

- _Interactive dependency graphs_: A metaprogram can display an interactive dependency tree of a function to show information about the dependencies. This might include whether a dependency is a postulate without FFI definitions (useful for safety analysis).

- _References to symbols_: The results of a query on a program might return a list of symbols, or another expression. The display of symbols or expressions could be augmented by making them clickable, leading to the user to the definition of the symbols. For example, the safety analysis mentioend above could also list the postulates in the display buffer with clickable links to the declaration of the postulate.

- _Didactic purposes_: For example, an instructor could make an Agda file with coding exercises on graphs, and the graphs could be visualised in the display buffer to let students know what happens to the graphs while implementing graph operations.

#pagebreak()

= Discussion

// *Synopsis*

In this thesis, we have presented the functionality and implementation of a new Agda language extension for Visual Studio Code, called Avea. Avea is written in Agda, and is successful is functioning as well as other Agda language extensions. We have discussed what major challenges were found while developing a practical application in Agda compiling to Javascript, and discussed the solutions to them used in Avea.

Furthermore, we discussed how Avea can be made more extensible, drawing ideas from editor reflection proposed by Korkut and Christiansen @extensible-editor. However, given that Avea is written in Agda there are more opportunities to allow extensions to Avea to remain entirely written in Agda, while still allowing advanced tooling to be created.

// *Related work*

While the proposed design for editor reflection in Agda can be used by all other Agda language extensions, given that it extends the interaction mode used by all of them. Avea can levarage its implementation in Agda to provide a comprehensible and type-safe API to call editor actions. This is an edge that Avea holds over all other language extensions.

Taking a broader view to other languages, we see that using editor reflection to make extensible language extensions need not be exclusive to Agda. Languages with a reflection API similar to Agda, such as Idris2#footnote(link("https://github.com/stefan-hoeck/idris2-elab-util/blob/main/src/Doc/Index.md")) and Rocq (using MetaRocq#footnote(link("https://metarocq.github.io/"))), are also candidates for editor reflection. Editor reflection could boost development in editor tooling in any of those languages too. We want to give special notice to Lean4, which has already implemented editor reflection to some extent: proof widgets are allowed to call meta-programs at edit time. However, proof widgets need to be written in Javascript, and the API to call meta-programs is not type-safe. Our work shows that this API could be made type-safe if proof widgets could be written in Lean too.

// *Reflection*

Lastly, we want to answer the two research questions posed at the start of the thesis:

+ *Is Agda a suitable language to write practical programs with?* \
  Yes, we believe that it is. Programs targetting Haskell can benefit from the relatively predictable compilation, which handles tail-call optimisation to do recursion over large data structures and imports. Targetting Javascript requires some additional infrastructure and programming disciplines: Javascript engines do not typically have tail-call optimisation, which means recursion should be used sparingly, and imports need to handled outside of Agda currently. We think more development on the Javascript backend is beneficial since, Agda programs can tap into the vast ecosystem Javascript programs have access to.

+ *Is it possible to make an extensible Agda extension written in Agda itself?* \
  Even though this thesis does not provide an implementation of an _extensible_ language extension for Agda, we still think it is possible. Leveraging Agda's meta-programming capabilities provides a better developer experience while keeping the extensibility API type-safe. Tooling developers need not learn Emacs Lisp (or another language of choice for the extension) to interface with the editor, and Haskell to write new tooling in Agda compiler's code base. Instead they can write Agda code to extend Avea, and use the reflection API to interface with the compiler. This extensibility API still allows for many different use cases, and has sufficient expressibility for advanced tools to be created.

#pagebreak()

= Future work

Besides implementing extensibility into Avea, there are other interesting research or engineering directions that can be explored that we have not discussed in this thesis.

*Comparing runtime performance against other extensions*

In the conclusion, the question "is Agda a suitable language to write practical programs with?" has been answered by arguing that it is possible to write Avea close to completely in Agda. During the development of Avea, we have not encountered many instances of performance bottlenecks due to Agda's code generation, even though the current Javascript backend generates quite inefficient Javascript code. Further research could look into what Avea's performance limits are, what other extensions' performance limits are, what the performance limits of a hand-written extension in Javascript focussed on performance are, and what can be done in Agda's Javascript backend to possibly improve the runtime performance of generated Javascript programs out-of-the-box.

*Verifying parts of the extension*

Writing Avea in Agda has proven to be useful in terms of allowing users to extend the editor tooling in Agda itself. However, with Agda's ability as a theorem prover, it is also possible to verify parts of Avea's functionality. While the formalisation of Avea is interesting of itself, the effects of the formalisation on the runtime performance are equally interesting.

Agda promotes the "correct by construction" style of proofs, where the proof of a property is usually intertwined with the function or algorithm the property applies to. This might incur costs on the runtime performance, and therefore, it might be interesting to look into how much the performance changes, and what might be done in the Agda compiler or Avea's code to alleviate some of these performance costs.

*Making the extension editor-agnostic*

Looking at the implementations of existing Agda extensions, a lot of the infrastructure for handling user commands, and responses from the Agda process is quite similar (up to differences in programming language). Logically, there is no reason why Avea should only work in VS Code, since many of VS Code's features Avea uses are also available in other editors. Therefore some engineering effort might be worth putting into making Avea editor-agnostic. Some options to do this are:

- To compile the Avea's editor-agnostic part to WebAssembly, and let the extension for a new editor call functions from the WebAssembly module. The extension itself is then responsible for providing the bridge between Avea and the editor.

- Another possibility is to take inspiration from Rocq and Lean4, and to run Avea as a language server (with non-standard extensions for Agda interactions), with which a new editor extension can communicate with.
// - This "core" part of every extension can be extracted and generalised such that the editor interactions are abstract. With a working Visual Studio Code extension, we could try adding support for another IDE -- for example Atom#footnote[#link("https://flight-manual.atom-editor.cc/hacking-atom/")], whose packages also need to be written in Javascript -- to create an abstraction layer between the editor-specific implementations and the editor-agnostic Agda interfacing code. Additionally, if the "core" logic is designed in such a way that it can be compiled to both Haskell and Javascript, we could also add support for Neovim using the same library as Cornelis uses.

// There are multiple way to design an editor-agnostic extension:

// #grid(columns: (50%, 50%), gutter: 16pt)[
// We can implement a WebAssembly target to Agda's compilation stage. WebAssembly can be embedded in many different languages and runtimes, and therefore is an interesting target for the extension. For Visual Studio Code, we can use Node.JS's API for interfacing with WebAssembly. The architecture is described as a diagram in @wasm.

// The downside to this is that the interfacing to the editor must be done outside of Agda. That is, the Foreign Function Interface that is currently implemented in Avea using compiler pragmas, should partly be moved to the host language.

// Another option is to rework the extension to function as a language server. This means that it runs as a standalone program, which an editor-specific extension can spawn. The editor-specific extension only needs to implement the communication layer between the language server and the editor. The protocol used to communicate can be a custom protocol for Avea, or the custom extensions to LSP that Lean4 or Rocq have implemented could be implemented for Avea, as far as they make sense for Agda style interactions.
// ][
//   #align(horizon)[
// #figure(image("wasm.png", width: 80%), caption: [Hello world])<wasm>
// #figure(image("language-server.png", width: 80%), caption: [Hello world])<language-server>
//   ]
// ]

// == Improving Agda's Foreign Function Interface

// During the development of the extension prototype thusfar, one major point of setback has been using the FFI. Currently, the FFI only provides one language pragma: `COMPILE JS`. This pragma takes a name of a function and the Javascript implementation for that function, and pastes it without semantic modification into the compiled output. The compiler has a flag `--js-verify` that checks for syntax errors in the compiled output, but this gives very little correctness guarantees. This flag cannot, for instance, verify whether FFI functions have the correct number of parameters or the correct type.

// We propose to improve the FFI by making it directed by Typescript functions. We can take a Typescript file and generate an Agda type for each exported function of the module we import using the FFI tool. For each function, we can request the parameter types and return type from the Typescript compiler, then create a curried function call and curried function type, and insert those terms into an Agda file. When going into this direction, we can adopt Typescript types incrementally:
// 1. We can select a subset of Typescript's type system, for example akin to the types in System F limited to builtin types, that we want to convert to Agda. We would need to create an interface with the rather under-documented Typescript compiler API#footnote[#link("https://github.com/Microsoft/TypeScript/wiki/Using-the-Compiler-API")] to analyse source files and request the types of functions within.
// 2. Once the basis for the tool works, we can try expanding the tool's capabilities by generating ML-style modules for classes, and as such also try supporting types other than builtin types and type variables. This encoding for objects has been abundantly used in the extension already. @ML-objects shows roughly how a simple class in Typescript can be converted to a module in Agda. The constructor could be compiled to a function called `new`, every method to a function with the same name, and every type parameter to a declaration in a variable block.

//   #figure(caption: "Proposed translation of class definitions in Typescript to modules in Agda.")[
//     #columns(2)[
//       #v(16pt)
//       ```ts
//       class List<T> {
//         constructor(length: number) {}
//         public get(index: number): T {}
//       }
//       ```
//       #colbreak()
//       ```agda
//       module List where
//         private variable T : Set
//         postulate
//           t : Set → Set
//           new : Nat → t T
//           get : Nat → t T → T
//       ```
//     ]
//   ]<ML-objects>

// Typescript's type system has some features that Agda's type system does not. For example, Typescript has unlabelled sum types: `T | U`. With Agda's sum types (`T ⊎ U`), the left and right injection can still be discriminated, whereas in Typescript these types might not be discriminable. Another example is Typescript's intersection types: `T & U`, which creates a new object type that contain all fields that are common in `T` and `U`. Agda does not have row types, so finding the intersection of records is quite difficult. This leads us to believe that, even though research into this idea might be valuable, it is out of scope for this thesis.


#pagebreak()

#bibliography("sources.bib")