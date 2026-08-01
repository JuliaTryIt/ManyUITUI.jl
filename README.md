# ManyUITUI.jl

**ManyUITUI** is the official Terminal User Interface (TUI) backend for the [ManyUI](https://github.com/s-celles/ManyUI.jl) framework.

It allows you to take any declarative domain model and widget tree written for `ManyUI`, and project it directly into a standard terminal emulator with full interactivity, rich colors, and complex layouts.

## Features

- **Terminal Driver & Raw Mode**: Safely captures keyboard and mouse inputs, and handles terminal resizing seamlessly.
- **Optimized Diffing Engine**: Only the parts of the screen that actually change are redrawn, utilizing minimal ANSI escape sequences. This ensures a buttery smooth, flicker-free experience even over slow SSH connections.
- **CSS-like Styling**: Translates `ManyUI` declarative styles (flexbox constraints, borders, paddings, colors) into raw terminal characters and ANSI codes.
- **Event Parsing**: Parses complex ANSI escape sequences from standard input into rich Julia events (`Click`, `KeyPress`, `Scroll`, etc.).

## Installation

```julia
import Pkg; Pkg.add("ManyUITUI")
```

*(Note: You will typically use this in conjunction with `ManyUI`)*

## Quickstart

Since `ManyUITUI` is just a backend, you write your application logic exactly as you would for any other `ManyUI` target, and then provide `TUI()` to the `launch` function.

```julia
using ManyUI
using ManyUITUI

# 1. Domain Model
mutable struct CounterModel
    clicks::Int
end
struct Increment <: Action end

# 2. Logic
ManyUI.execute!(model::CounterModel, ::Increment) = model.clicks += 1

# 3. View
function ManyUI.render(model::CounterModel, proj::ManyUI.Projection)
    Container(
        Label("Count: $(model.clicks)"),
        Button("Click me", _ -> ManyUI.execute!(model, Increment()))
    )
end

# 4. Launch in the Terminal!
ManyUI.launch(CounterModel(0), TUI())
```

## Documentation

For the complete API reference, styling guides, and advanced examples, please see the central documentation repository:

👉 **[ManyUIDoc.jl](https://s-celles.github.io/ManyUIDoc.jl/)**
