# Avea: Another Visual studio code Extension for Agda

Avea is a Visual Studio Code extension meant to provide the same development experience as Agda's Emacs mode. What stands out about Avea compared to other vscode extensions is that Avea is written in Agda itself.

## Installation

The current version of the extension only supports Agda 2.9.0. You need to have [Agda](https://agda.readthedocs.io/en/latest/getting-started/installation.html) installed on your path, or set a custom path to the Agda binary in the vscode settings for the extension.

The extension itself can be installed via the official [Visual Studio Code marketplace](https://marketplace.visualstudio.com/items?itemName=stickypiston.avea), the [Open VSX Registry](https://open-vsx.org/extension/stickypiston/avea) (the vscodium marketplace) and via a manual installation of the VSIX file. VSIX files are built on every commit on the master branch, and can be found under the artifacts section of a workflow run on the [Github Actions page](https://github.com/stickyPiston/agda-mode-vscode/actions).

> [!WARNING]
> This extension has some conflicts with other extensions, most notably the Vim extension. Please disable the Vim extension to make sure this extension works without issues.

## Supported commands

Some commands can be prefixed by a number of <kbd>ctrl+u</kbd> to specify the level of normalisation of the output. One exception is the compute command (<kbd>ctrl+c ctrl+n</kbd>), where each <kbd>ctrl+u</kbd> switches between `DefaultCompute`, `IgnoreAbstract`, `UseShowInstance` and `HeadCompute`.
1. Without <kbd>ctrl+u</kbd> every command will return expressions as-is;
2. With one <kbd>ctrl+u</kbd>, expressions are evaluated to weak head normal form;
3. With <kbd>ctrl+u ctrl+u</kbd>, expressions are evaluated to their full normal form.

### Goal commands

All of these commands operate on a goal, however some commands also work outside of a goal and display an input prompt to ask for a term or variable name instead.

|Command|Keybind|Has <kbd>ctrl+u</kbd> prefixes?|Works outside goal?|
|-|-|-|-|
|Goal context|<kbd>ctrl+c ctrl+e</kbd>|✅|❌|
|Goal type|<kbd>ctrl+c ctrl+t</kbd>|✅|❌|
|Goal type and context|<kbd>ctrl+c ctrl+,</kbd>|✅|❌|
|Goal type, context and inferred type|<kbd>ctrl+c ctrl+.</kbd>|✅|❌|
|Goal type, context and checked term|<kbd>ctrl+c ctrl+;</kbd>|✅|❌|
|Refine|<kbd>ctrl+c ctrl+r</kbd>|✅|❌|
|Give|<kbd>ctrl+c ctrl+spc</kbd>|✅|❌|
|Auto solve|<kbd>ctrl+c ctrl+a</kbd>|✅|❌|
|Make case|<kbd>ctrl+c ctrl+c</kbd>|❌|❌|
|Infer|<kbd>ctrl+c ctrl+d</kbd>|✅|✅|
|Compute|<kbd>ctrl+c ctrl+n</kbd>|✅|✅|
|Module contents|<kbd>ctrl+c ctrl+o</kbd>|✅|✅|
|Why in scope|<kbd>ctrl+c ctrl+w</kbd>|❌|✅|
|Search about|<kbd>ctrl+c ctrl+z</kbd>|✅|✅|

### Non-goal commands

|Command|Keybind|Has <kbd>ctrl+u</kbd> modifiers?|
|-|-|-|
|Load file|<kbd>ctrl+c ctrl+l</kbd>|❌|
|Show all goals|<kbd>ctrl+c ctrl+?</kbd>|✅|
|Show constraints|<kbd>ctrl+c ctrl+=</kbd>|✅|
|Next goal|<kbd>ctrl+c ctrl+f</kbd>|❌|
|Previous goal|<kbd>ctrl+c ctrl+b</kbd>|❌|
|Toggle hidden arguments|<kbd>ctrl+c ctrl+x ctrl+h</kbd>|❌|
|Toggle irrelevant arguments|<kbd>ctrl+c ctrl+x ctrl+i</kbd>|❌|
|Restart Agda process|<kbd>ctrl+c ctrl+x ctrl+r</kbd>|❌|
|Compile file|<kbd>ctrl+c ctrl+x ctrl+c</kbd>|❌|
|Switch version|<kbd>ctrl+c ctrl+x ctrl+s</kbd>|❌|

## Unicode input

The unicode input works similarly to the one in the Emacs mode. Type `\` to enable input mode and then type the unicode characters code to input it into the buffer. There is a status bar at the bottom of the window which shows what characters can be inputted next, and which alternatives can be selected using the arrow keys.

## Development

Before running this extension make sure you have installed the following dependencies:
- [Agda](https://agda.readthedocs.io/en/stable/getting-started/installation.html)
- [Visual Studio Code](https://code.visualstudio.com)
- Node.js, which could be installed via [nvm](https://github.com/nvm-sh/nvm#readme)

To run the extension locally, open the cloned folder in vscode and execute the "Run Extension" debug profile.
This will open a new vscode window with the extension loaded into it.